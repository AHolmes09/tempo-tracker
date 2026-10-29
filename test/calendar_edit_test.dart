import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo/main.dart';
import 'package:tempo/tracker.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Off-grid resize snaps to wall-clock five-minute marks', (
    tester,
  ) async {
    final original = WorkSession(
      start: DateTime(2026, 1, 5, 8, 7),
      end: DateTime(2026, 1, 5, 9, 7, 23),
      label: 'Work',
    );
    WorkSession? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayTimeline(
            date: DateTime(2026, 1, 5),
            now: DateTime(2026, 1, 6),
            sessions: [original],
            onUpdate: (_, value) async {
              changed = value;
            },
            onDelete: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(ValueKey('${original.start.toIso8601String()}-end')),
      const Offset(0, 40),
    );
    await tester.pumpAndSettle();
    expect(changed!.end, DateTime(2026, 1, 5, 9, 35));
    expect(changed!.start, original.start);
  });

  testWidgets('Empty timeline double click and long press create sessions', (
    tester,
  ) async {
    WorkSession? created;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayTimeline(
            date: DateTime(2026, 1, 5),
            now: DateTime(2026, 1, 6),
            sessions: [],
            onUpdate: (_, value) async {},
            onDelete: (_) async {},
            onCreate: (value) async {
              created = value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Initial scroll is 7 AM; 80 px below the viewport top is 8 AM.
    const location = Offset(200, 81);
    await tester.tapAt(location);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(location);
    await tester.pumpAndSettle();
    expect(find.text('Create work session'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Manual work');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(created!.start, DateTime(2026, 1, 5, 8));
    expect(created!.label, 'Manual work');
    await tester.longPressAt(location);
    await tester.pumpAndSettle();
    expect(find.text('Create work session'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('Month fits without scrolling and Calendar resets day view', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();
    expect(find.byType(DayTimeline), findsOneWidget);
    final today = tester.getTopLeft(
      find.byKey(const ValueKey('calendar-today')),
    );
    final total = tester.getTopLeft(
      find.byKey(const ValueKey('calendar-total')),
    );
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('calendar-today'))),
        today,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('calendar-total'))),
        total,
      );
    }
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(DayTimeline), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Deleting from today persists and updates totals', (
    tester,
  ) async {
    final now = DateTime.now();
    final start = dayStart(now);
    final session = WorkSession(
      start: start,
      end: start.add(const Duration(seconds: 1)),
      label: 'Delete me',
    );
    SharedPreferences.setMockInitialValues({
      SessionStore.key: jsonEncode([session.toJson()]),
    });
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Delete session'));
    await tester.tap(find.byTooltip('Delete session'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(await SessionStore().load(), isEmpty);
    expect(find.text('Delete me'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Timeline moves and resizes both edges', (tester) async {
    final day = DateTime(2026, 1, 5);
    final original = WorkSession(
      start: DateTime(2026, 1, 5, 9),
      end: DateTime(2026, 1, 5, 11),
      label: 'Design',
    );
    WorkSession? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayTimeline(
            date: day,
            now: DateTime(2026, 1, 6),
            sessions: [original],
            onUpdate: (_, value) async {
              changed = value;
            },
            onDelete: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final prefix = original.start.toIso8601String();
    await tester.drag(
      find.byKey(ValueKey('$prefix-move')),
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();
    expect(changed!.start, original.start.add(const Duration(hours: 1)));
    expect(changed!.end, original.end!.add(const Duration(hours: 1)));
    await tester.drag(find.byKey(ValueKey('$prefix-end')), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(changed!.start, original.start);
    expect(changed!.end, original.end!.add(const Duration(minutes: 30)));
    await tester.drag(
      find.byKey(ValueKey('$prefix-start')),
      const Offset(0, -40),
    );
    await tester.pumpAndSettle();
    expect(
      changed!.start,
      original.start.subtract(const Duration(minutes: 30)),
    );
    expect(changed!.end, original.end);
  });

  testWidgets('Timeline details expose editing and deletion', (tester) async {
    final original = WorkSession(
      start: DateTime(2026, 1, 5, 9),
      end: DateTime(2026, 1, 5, 11),
      label: 'Design',
    );
    WorkSession? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayTimeline(
            date: DateTime(2026, 1, 5),
            now: DateTime(2026, 1, 6),
            sessions: [original],
            onUpdate: (_, value) async {},
            onDelete: (value) async {
              deleted = value;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('${original.start.toIso8601String()}-move')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit times'), findsOneWidget);
    await tester.tap(find.text('Delete session'));
    await tester.pumpAndSettle();
    expect(deleted, original);
  });
}

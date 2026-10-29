import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tempo/main.dart';
import 'package:tempo/tracker.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Splits overnight sessions and clips monthly totals', () {
    final session = WorkSession(
      start: DateTime.utc(2026, 10, 31, 23),
      end: DateTime.utc(2026, 11, 1, 2),
      label: 'Work',
    );
    expect(
      session.overlap(
        DateTime.utc(2026, 10, 31),
        DateTime.utc(2026, 11, 1),
        DateTime.utc(2026, 11, 2),
      ),
      const Duration(hours: 1),
    );
    expect(
      session.overlap(
        DateTime.utc(2026, 11, 1),
        DateTime.utc(2026, 11, 2),
        DateTime.utc(2026, 11, 2),
      ),
      const Duration(hours: 2),
    );
  });

  test('Restores an active session and completed sessions', () async {
    final store = SessionStore();
    await store.save([
      WorkSession(start: DateTime(2026, 10, 28, 9), label: 'Design'),
    ]);
    final restored = await store.load();
    expect(restored.single.label, 'Design');
    expect(restored.single.end, isNull);
    expect(
      restored.single.overlap(
        DateTime(2026, 10, 28),
        DateTime(2026, 10, 29),
        DateTime(2026, 10, 28, 11),
      ),
      const Duration(hours: 2),
    );
  });

  testWidgets('Clock in, clock out, and open calendar day', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Build Tempo');
    await tester.tap(find.text('Clock in'));
    await tester.pumpAndSettle();
    expect(find.text('Clock out'), findsOneWidget);
    expect((await SessionStore().load()).single.end, isNull);
    await tester.tap(find.text('Clock out'));
    await tester.pumpAndSettle();
    expect((await SessionStore().load()).single.end, isNotNull);
    await tester.tap(find.text('Calendar').first);
    await tester.pumpAndSettle();
    expect(find.text('Your time, mapped.'), findsOneWidget);
    await tester.tap(find.text('15').first);
    await tester.pumpAndSettle();
    expect(find.byType(DayTimeline), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Phone layouts fit and day navigation works', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(find.byType(DayTimeline), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}

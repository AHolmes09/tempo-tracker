import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'tracker.dart';

void main() => runApp(const MyApp());

const ink = Color(0xFF23382F);
const green = Color(0xFF34664E);
const muted = Color(0xFF758078);
const canvas = Color(0xFFF6F7F2);
const pale = Color(0xFFE8EFE5);
const months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
String dateLabel(DateTime date) =>
    '${months[date.month - 1]} ${date.day}, ${date.year}';
String timeLabel(DateTime date) =>
    '${date.hour % 12 == 0 ? 12 : date.hour % 12}:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'AM' : 'PM'}';

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tempo · Time well spent',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: Colors.white,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const TrackerPage(),
  );
}

class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});
  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  final store = SessionStore();
  final label = TextEditingController();
  List<WorkSession> sessions = [];
  late final Timer ticker;
  DateTime now = DateTime.now();
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selected = dayStart(DateTime.now());
  int page = 0;
  bool daily = false, loading = true, saving = false;
  String? loadError;
  WorkSession? get active => sessions.where((s) => s.end == null).firstOrNull;

  @override
  void initState() {
    super.initState();
    restore();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  Future<void> restore() async {
    try {
      final loaded = await store.load();
      if (mounted) {
        setState(() {
          sessions = loaded;
          loading = false;
          loadError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError =
              'Your saved sessions could not be loaded. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    ticker.cancel();
    label.dispose();
    super.dispose();
  }

  Duration total(DateTime start, DateTime end) => sessions.fold(
    Duration.zero,
    (sum, s) => sum + s.overlap(start, end, now),
  );
  List<WorkSession> onDay(DateTime date) => sessions
      .where(
        (s) =>
            s.overlap(dayStart(date), nextDay(date), now) > Duration.zero ||
            (s.end == null && dayStart(s.start) == dayStart(date)),
      )
      .toList();

  Future<void> toggleClock() async {
    if (saving || loading || loadError != null) return;
    final instant = DateTime.now();
    final current = active;
    final updated = [...sessions];
    if (current == null) {
      updated.add(
        WorkSession(
          start: instant,
          label: label.text.trim().isEmpty ? 'Work session' : label.text.trim(),
        ),
      );
    } else {
      updated[updated.indexOf(current)] = WorkSession(
        start: current.start,
        end: instant,
        label: current.label,
      );
    }
    setState(() => saving = true);
    try {
      await store.save(updated);
      if (!mounted) return;
      setState(() {
        sessions = updated;
        now = instant;
        saving = false;
      });
      if (current != null) label.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your session. Please try again.'),
        ),
      );
    }
  }

  void selectPage(int value) => setState(() {
    page = value;
    if (value == 1) daily = false;
  });

  Future<bool> saveSessions(List<WorkSession> updated) async {
    if (saving) return false;
    setState(() => saving = true);
    try {
      await store.save(updated);
      if (!mounted) return false;
      setState(() {
        sessions = updated;
        saving = false;
      });
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save changes. Please try again.'),
          ),
        );
      }
      return false;
    }
  }

  Future<void> deleteSession(WorkSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          'Delete “${session.label}” and its tracked time?${session.end == null ? ' This will also stop the running timer.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && !saving) {
      await saveSessions(sessions.where((s) => s != session).toList());
    }
  }

  Future<void> updateSession(WorkSession? original, WorkSession updated) async {
    if (saving || (original != null && !sessions.contains(original))) return;
    final end = updated.end ?? DateTime.now();
    if (!end.isAfter(updated.start) ||
        updated.start.isAfter(DateTime.now()) ||
        end.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choose a positive duration that ends no later than now.',
          ),
        ),
      );
      return;
    }
    if (sessions.any(
      (s) =>
          s != original &&
          s.start.isBefore(end) &&
          (s.end ?? DateTime.now()).isAfter(updated.start),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This time overlaps another session. Choose a free time.',
          ),
        ),
      );
      return;
    }
    final updatedSessions = [...sessions];
    if (original == null) {
      updatedSessions.add(updated);
    } else {
      updatedSessions[updatedSessions.indexOf(original)] = updated;
    }
    updatedSessions.sort((a, b) => a.start.compareTo(b.start));
    await saveSessions(updatedSessions);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 800;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                Container(
                  width: 220,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(right: BorderSide(color: Color(0xFFE3E7DF))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(28, 36, 24, 44),
                        child: Brand(),
                      ),
                      navItem(0, Icons.timer_outlined, 'Time tracker'),
                      navItem(1, Icons.calendar_month_outlined, 'Calendar'),
                      const Spacer(),
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'A little focus.\nA little more balance.',
                          style: TextStyle(color: muted, height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : loadError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(loadError!),
                            TextButton(
                              onPressed: restore,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: wide ? 40 : 24,
                              vertical: 22,
                            ),
                            child: Row(
                              children: [
                                if (!wide)
                                  const Brand()
                                else
                                  Text(
                                    page == 0
                                        ? 'YOUR WORKSPACE'
                                        : 'YOUR TIME, AT A GLANCE',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 2,
                                      color: muted,
                                    ),
                                  ),
                                const Spacer(),
                                if (active != null)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 12),
                                    child: Icon(
                                      Icons.circle,
                                      color: green,
                                      size: 9,
                                    ),
                                  ),
                                Text(
                                  '${months[now.month - 1].substring(0, 3)} ${now.day}, ${now.year}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: page == 0 ? home(wide) : calendar(wide),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: page,
                onDestinationSelected: selectPage,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.timer_outlined),
                    label: 'Time tracker',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    label: 'Calendar',
                  ),
                ],
              ),
      );
    },
  );

  Widget navItem(int index, IconData icon, String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: ListTile(
      selected: page == index,
      selectedTileColor: pale,
      selectedColor: green,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onTap: () => selectPage(index),
    ),
  );

  Widget home(bool wide) {
    final today = dayStart(now);
    final week = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final elapsed = active == null
        ? Duration.zero
        : now.difference(active!.start);
    final clock =
        '${elapsed.inHours.toString().padLeft(2, '0')}:${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 24, 12, wide ? 40 : 24, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Make time count.',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Find your focus. We’ll keep track of the time.',
                style: TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 30),
              panel(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: active == null ? muted : green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          active == null
                              ? 'READY WHEN YOU ARE'
                              : 'ON THE CLOCK',
                          style: const TextStyle(
                            fontSize: 11,
                            letterSpacing: 2,
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    FittedBox(
                      child: Text(
                        clock,
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w300,
                          letterSpacing: -2,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      active == null
                          ? 'A fresh start for your next work session.'
                          : 'Started at ${timeLabel(active!.start)} · ${active!.label}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 28),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: TextField(
                        controller: label,
                        enabled: active == null && !saving,
                        maxLength: 80,
                        decoration: InputDecoration(
                          hintText: active?.label ?? 'What are you working on?',
                          counterText: '',
                          prefixIcon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 360,
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: saving ? null : toggleClock,
                        icon: Icon(
                          active == null
                              ? Icons.play_arrow_rounded
                              : Icons.stop_rounded,
                        ),
                        label: Text(
                          saving
                              ? 'Saving…'
                              : active == null
                              ? 'Clock in'
                              : 'Clock out',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Your time, one session at a time.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: stat(
                      'TODAY',
                      durationLabel(total(today, nextDay(today))),
                      Icons.wb_sunny_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: stat(
                      'THIS WEEK',
                      durationLabel(
                        total(
                          week,
                          DateTime(week.year, week.month, week.day + 7),
                        ),
                      ),
                      Icons.date_range_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: stat(
                      'THIS MONTH',
                      durationLabel(
                        total(
                          DateTime(now.year, now.month),
                          DateTime(now.year, now.month + 1),
                        ),
                      ),
                      Icons.calendar_month_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Today’s sessions',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      page = 1;
                      daily = true;
                      selected = today;
                      month = DateTime(today.year, today.month);
                    }),
                    child: const Text('View day →'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (onDay(today).isEmpty)
                panel(
                  child: const Row(
                    children: [
                      Icon(Icons.coffee_outlined, color: muted),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'A clear day ahead. Clock in to start your first session.',
                          style: TextStyle(color: muted, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...onDay(today).reversed.map(sessionTile),
            ],
          ),
        ),
      ),
    );
  }

  Widget sessionTile(WorkSession session) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: panel(
      padding: 18,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: pale,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              session.end == null
                  ? Icons.play_arrow_rounded
                  : Icons.check_rounded,
              color: green,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${timeLabel(session.start)} – ${session.end == null ? 'In progress' : timeLabel(session.end!)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            durationLabel(session.overlap(dayStart(now), nextDay(now), now)),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          IconButton(
            tooltip: 'Delete session',
            onPressed: saving ? null : () => deleteSession(session),
            icon: const Icon(Icons.delete_outline, size: 20, color: muted),
          ),
        ],
      ),
    ),
  );

  Widget stat(String title, String value, IconData icon) => panel(
    padding: 16,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: green, size: 20),
        const SizedBox(height: 15),
        Text(
          value,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 5),
        Text(
          title,
          style: const TextStyle(fontSize: 9, letterSpacing: 1, color: muted),
        ),
      ],
    ),
  );

  Widget calendar(bool wide) => Padding(
    padding: EdgeInsets.fromLTRB(wide ? 40 : 16, 12, wide ? 40 : 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your time, mapped.',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Month')),
                ButtonSegment(value: true, label: Text('Day')),
              ],
              selected: {daily},
              onSelectionChanged: (value) =>
                  setState(() => daily = value.first),
            ),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final navigation = SizedBox(
              key: const ValueKey('calendar-date-navigation'),
              width: 380,
              child: Row(
                children: [
                  IconButton(
                    tooltip: daily ? 'Previous day' : 'Previous month',
                    onPressed: () => move(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      daily
                          ? '${weekdays[selected.weekday - 1]}, ${months[selected.month - 1].substring(0, 3)} ${selected.day}, ${selected.year}'
                          : '${months[month.month - 1]} ${month.year}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: daily ? 'Next day' : 'Next month',
                    onPressed: () => move(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  key: const ValueKey('calendar-today'),
                  onPressed: () => setState(() {
                    selected = dayStart(now);
                    month = DateTime(now.year, now.month);
                  }),
                  child: const Text('Today'),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: Chip(
                    key: const ValueKey('calendar-total'),
                    backgroundColor: pale,
                    side: BorderSide.none,
                    avatar: const Icon(Icons.schedule, size: 16, color: green),
                    label: FittedBox(
                      child: Text(
                        '${durationLabel(daily ? total(selected, nextDay(selected)) : total(month, DateTime(month.year, month.month + 1)))} worked',
                        style: const TextStyle(
                          color: green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
            return Column(
              children: [
                Center(child: navigation),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Expanded(
          child: daily
              ? DayTimeline(
                  key: ValueKey(selected),
                  date: selected,
                  now: now,
                  sessions: onDay(selected),
                  enabled: !saving,
                  onUpdate: updateSession,
                  onCreate: (session) => updateSession(null, session),
                  onDelete: deleteSession,
                )
              : monthGrid(),
        ),
        const SizedBox(height: 12),
        Text(
          daily
              ? 'Drag to move or resize · Double-click or hold empty space to add a session'
              : 'Select any day to explore your work sessions.',
          style: const TextStyle(fontSize: 12, color: muted),
        ),
      ],
    ),
  );

  void move(int offset) => setState(() {
    if (daily) {
      selected = DateTime(selected.year, selected.month, selected.day + offset);
      month = DateTime(selected.year, selected.month);
    } else {
      month = DateTime(month.year, month.month + offset);
      selected = month;
    }
  });

  Widget monthGrid() {
    final offset = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((days + offset) / 7).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = (constraints.maxHeight - 40) / rows < 68;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E6DD)),
          ),
          child: Column(
            children: [
              Row(
                children: weekdays
                    .map(
                      (d) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            d.substring(0, 3).toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1,
                              color: muted,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              ...List.generate(
                rows,
                (row) => Expanded(
                  child: Row(
                    children: List.generate(7, (col) {
                      final date = DateTime(
                        month.year,
                        month.month,
                        row * 7 + col - offset + 1,
                      );
                      final inside = date.month == month.month;
                      final today = date == dayStart(now);
                      final worked = total(date, nextDay(date));
                      return Expanded(
                        child: SizedBox.expand(
                          child: Material(
                            color: today
                                ? const Color(0xFFF0F5EC)
                                : inside
                                ? Colors.white
                                : const Color(0xFFFAFBF8),
                            child: InkWell(
                              onTap: () => setState(() {
                                selected = date;
                                month = DateTime(date.year, date.month);
                                daily = true;
                              }),
                              child: Container(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: Color(0xFFE6EAE2)),
                                    right: BorderSide(color: Color(0xFFE6EAE2)),
                                  ),
                                ),
                                padding: EdgeInsets.all(compact ? 2 : 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: compact ? 16 : 27,
                                      height: compact ? 16 : 27,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: today
                                            ? green
                                            : Colors.transparent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${date.day}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: today
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: today
                                              ? Colors.white
                                              : inside
                                              ? ink
                                              : muted.withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.symmetric(
                                        vertical: compact ? 0 : 5,
                                        horizontal: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: worked > Duration.zero
                                            ? pale
                                            : const Color(0xFFF4F5F0),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          durationLabel(worked),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: worked > Duration.zero
                                                ? green
                                                : muted,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DayTimeline extends StatefulWidget {
  const DayTimeline({
    super.key,
    required this.date,
    required this.now,
    required this.sessions,
    required this.onUpdate,
    required this.onDelete,
    this.enabled = true,
    this.onCreate,
  });
  final bool enabled;
  final Future<void> Function(WorkSession)? onCreate;
  final Future<void> Function(WorkSession, WorkSession) onUpdate;
  final Future<void> Function(WorkSession) onDelete;
  final DateTime date, now;
  final List<WorkSession> sessions;
  @override
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
  static const hourHeight = 80.0;
  late final ScrollController scroll;
  @override
  void initState() {
    super.initState();
    final first = widget.sessions.isEmpty
        ? 8
        : widget.sessions.first.start.isBefore(widget.date)
        ? 0
        : widget.sessions.first.start.hour;
    scroll = ScrollController(
      initialScrollOffset: math.max(0, first - 1) * hourHeight,
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  WorkSession? dragging;
  WorkSession? preview;
  double dragDistance = 0;

  void beginDrag(WorkSession session) {
    dragging = session;
    preview = session;
    dragDistance = 0;
  }

  void drag(DragUpdateDetails details, String mode) {
    final original = dragging;
    if (original == null || original.end == null) return;
    dragDistance += details.delta.dy;
    final delta = Duration(
      milliseconds: (dragDistance / hourHeight * 3600000).round(),
    );
    DateTime snap(DateTime time) => DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
      ((time.minute + time.second / 60 + time.millisecond / 60000) / 5)
              .round() *
          5,
    );
    var start = original.start;
    var end = original.end!;
    if (mode == 'move') {
      start = snap(start.add(delta));
      end = start.add(original.end!.difference(original.start));
    } else if (mode == 'start') {
      start = snap(start.add(delta));
    } else {
      end = snap(end.add(delta));
    }
    if (end.difference(start) < const Duration(minutes: 1)) return;
    if (end.isAfter(widget.now) ||
        !end.isAfter(widget.date) ||
        !start.isBefore(nextDay(widget.date))) {
      return;
    }
    setState(
      () =>
          preview = WorkSession(start: start, end: end, label: original.label),
    );
  }

  Future<void> finishDrag() async {
    final original = dragging;
    final changed = preview;
    if (original != null &&
        changed != null &&
        (original.start != changed.start || original.end != changed.end)) {
      await widget.onUpdate(original, changed);
    }
    if (mounted) {
      setState(() {
        dragging = null;
        preview = null;
      });
    }
  }

  Offset? emptyTap;
  Future<void> createAt(Offset position) async {
    if (!widget.enabled || widget.onCreate == null) return;
    final minutes = ((position.dy / hourHeight * 60 / 5).round() * 5).clamp(
      0,
      1435,
    );
    final start = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
      0,
      minutes,
    );
    var end = start.add(const Duration(hours: 1));
    if (start.isBefore(widget.now) && end.isAfter(widget.now)) end = widget.now;
    final created = await showDialog<WorkSession>(
      context: context,
      builder: (_) => SessionEditor(
        session: WorkSession(start: start, end: end, label: ''),
        creating: true,
      ),
    );
    if (created != null && mounted) await widget.onCreate!(created);
  }

  Future<void> showSession(WorkSession session) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(session.label),
        content: Text(
          '${dateLabel(session.start)} · ${timeLabel(session.start)}\n${session.end == null ? 'In progress — clock out to move or resize.' : '${dateLabel(session.end!)} · ${timeLabel(session.end!)}'}\n${durationLabel(session.overlap(widget.date, nextDay(widget.date), widget.now))} on this day',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete session'),
          ),
          if (session.end != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Edit times'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'delete') await widget.onDelete(session);
    if (action == 'edit' && mounted) {
      final updated = await showDialog<WorkSession>(
        context: context,
        builder: (_) => SessionEditor(session: session),
      );
      if (updated != null && mounted) await widget.onUpdate(session, updated);
    }
  }

  Widget sessionBlock(WorkSession session) {
    final displayed = dragging == session ? preview ?? session : session;
    final top = position(displayed.start);
    final height = math.max(32.0, position(displayed.end ?? widget.now) - top);
    final editable = widget.enabled && session.end != null;
    Widget handle(String mode) => GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      key: ValueKey('${session.start.toIso8601String()}-$mode'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: editable ? (_) => beginDrag(session) : null,
      onVerticalDragUpdate: editable ? (details) => drag(details, mode) : null,
      onVerticalDragEnd: editable ? (_) => finishDrag() : null,
      onVerticalDragCancel: () => setState(() {
        dragging = null;
        preview = null;
      }),
      child: MouseRegion(
        cursor: editable
            ? SystemMouseCursors.resizeUpDown
            : SystemMouseCursors.basic,
        child: SizedBox(
          height: 10,
          child: Center(
            child: Container(
              width: 28,
              height: 2,
              color: green.withValues(alpha: .5),
            ),
          ),
        ),
      ),
    );
    return Positioned(
      top: math.min(top, 24 * hourHeight - height),
      left: 76,
      right: 18,
      height: height,
      child: Material(
        color: pale,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(7)),
          side: BorderSide(color: Color(0xFFA9C4A5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            if (editable) handle('start'),
            Expanded(
              child: GestureDetector(
                dragStartBehavior: DragStartBehavior.down,
                key: ValueKey('${session.start.toIso8601String()}-move'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.enabled ? () => showSession(session) : null,
                onVerticalDragStart: editable
                    ? (_) => beginDrag(session)
                    : null,
                onVerticalDragUpdate: editable
                    ? (details) => drag(details, 'move')
                    : null,
                onVerticalDragEnd: editable ? (_) => finishDrag() : null,
                onVerticalDragCancel: () => setState(() {
                  dragging = null;
                  preview = null;
                }),
                child: MouseRegion(
                  cursor: editable
                      ? SystemMouseCursors.move
                      : SystemMouseCursors.click,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Text(
                          height > 65
                              ? '${displayed.label}\n${timeLabel(displayed.start)} – ${displayed.end == null ? 'In progress' : timeLabel(displayed.end!)}'
                              : displayed.label,
                          maxLines: height > 65 ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (editable) handle('end'),
          ],
        ),
      ),
    );
  }

  double position(DateTime time) => time.isBefore(widget.date)
      ? 0
      : !time.isBefore(nextDay(widget.date))
      ? 24 * hourHeight
      : (time.hour + time.minute / 60 + time.second / 3600) * hourHeight;
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE0E6DD)),
    ),
    child: SingleChildScrollView(
      controller: scroll,
      child: SizedBox(
        height: 24 * hourHeight + 24,
        child: Stack(
          children: [
            ...List.generate(
              25,
              (hour) => Positioned(
                top: hour * hourHeight,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    SizedBox(
                      width: 65,
                      child: Text(
                        hour == 24
                            ? '12 AM'
                            : '${hour % 12 == 0 ? 12 : hour % 12} ${hour < 12 ? 'AM' : 'PM'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: muted, fontSize: 10),
                      ),
                    ),
                    const Expanded(
                      child: Divider(height: 1, color: Color(0xFFE8EBE4)),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.sessions.isEmpty)
              const Positioned(
                top: 8 * hourHeight + 24,
                left: 80,
                right: 20,
                child: Text(
                  'No work sessions on this day.\nClock in from Time tracker to get started.',
                  style: TextStyle(color: muted, height: 1.7),
                ),
              ),
            Positioned.fill(
              left: 66,
              child: GestureDetector(
                key: const ValueKey('empty-day-timeline'),
                behavior: HitTestBehavior.opaque,
                onDoubleTapDown: (details) => emptyTap = details.localPosition,
                onDoubleTap: () {
                  if (emptyTap != null) createAt(emptyTap!);
                },
                onLongPressStart: (details) => createAt(details.localPosition),
                child: const SizedBox.expand(),
              ),
            ),
            ...widget.sessions.map((session) => sessionBlock(session)),
            if (dayStart(widget.now) == widget.date)
              Positioned(
                top: position(widget.now),
                left: 62,
                right: 0,
                child: const IgnorePointer(
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: Color(0xFFCA7350), size: 7),
                      Expanded(
                        child: Divider(
                          color: Color(0xFFCA7350),
                          thickness: 1,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.timelapse_rounded, color: green, size: 30),
      SizedBox(width: 9),
      Text(
        'tempo',
        style: TextStyle(
          fontSize: 25,
          letterSpacing: -1,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

Widget panel({required Widget child, double padding = 28}) => Container(
  width: double.infinity,
  padding: EdgeInsets.all(padding),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFFE3E7DF)),
  ),
  child: child,
);

class SessionEditor extends StatefulWidget {
  const SessionEditor({
    super.key,
    required this.session,
    this.creating = false,
  });
  final bool creating;
  final WorkSession session;
  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  late DateTime start = widget.session.start;
  late DateTime end = widget.session.end!;
  String? error;
  late final TextEditingController sessionLabel = TextEditingController(
    text: widget.session.label,
  );
  @override
  void dispose() {
    sessionLabel.dispose();
    super.dispose();
  }

  Future<void> pick(bool isStart) async {
    final current = isStart ? start : end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(math.min(2000, current.year)),
      lastDate: current.isAfter(DateTime.now()) ? current : DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    setState(() {
      final value = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        start = value;
      } else {
        end = value;
      }
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.creating ? 'Create work session' : 'Edit session times'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: sessionLabel,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Work label',
            hintText: 'What did you work on?',
          ),
        ),
        const SizedBox(height: 12),
        const Text('Start'),
        TextButton(
          onPressed: () => pick(true),
          child: Text('${dateLabel(start)} · ${timeLabel(start)}'),
        ),
        const SizedBox(height: 12),
        const Text('End'),
        TextButton(
          onPressed: () => pick(false),
          child: Text('${dateLabel(end)} · ${timeLabel(end)}'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!end.isAfter(start) || end.isAfter(DateTime.now())) {
            setState(
              () =>
                  error = 'End must follow start and cannot be in the future.',
            );
            return;
          }
          Navigator.pop(
            context,
            WorkSession(
              start: start,
              end: end,
              label: sessionLabel.text.trim().isEmpty
                  ? 'Work session'
                  : sessionLabel.text.trim(),
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

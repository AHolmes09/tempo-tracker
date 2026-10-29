import 'dart:convert';
import 'local_storage.dart' if (dart.library.js_interop) 'local_storage_web.dart' as storage;

class WorkSession {
  const WorkSession({required this.start, this.end, required this.label});
  final DateTime start;
  final DateTime? end;
  final String label;

  Duration overlap(DateTime from, DateTime to, DateTime now) {
    final a = start.isAfter(from) ? start : from;
    final finish = end ?? now;
    final b = finish.isBefore(to) ? finish : to;
    return b.isAfter(a) ? b.difference(a) : Duration.zero;
  }

  Map<String, dynamic> toJson() => {
    'start': start.toIso8601String(),
    'end': end?.toIso8601String(),
    'label': label,
  };
  factory WorkSession.fromJson(Map<String, dynamic> json) => WorkSession(
    start: DateTime.parse(json['start'] as String).toLocal(),
    end: json['end'] == null
        ? null
        : DateTime.parse(json['end'] as String).toLocal(),
    label: json['label'] as String,
  );
}

class SessionStore {
  static const key = 'tempo.sessions.v1';
  Future<List<WorkSession>> load() async {
    final data = await storage.readSessions();
    if (data == null) return [];
    return (jsonDecode(data) as List)
        .map((item) => WorkSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<WorkSession> sessions) async {
    await storage.writeSessions(jsonEncode(sessions.map((s) => s.toJson()).toList()));
  }
}

DateTime dayStart(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime nextDay(DateTime date) =>
    DateTime(date.year, date.month, date.day + 1);
String durationLabel(Duration value) {
  if (value.inSeconds > 0 && value.inMinutes == 0) return '<1m';
  final hours = value.inMinutes ~/ 60;
  final minutes = value.inMinutes % 60;
  return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
}

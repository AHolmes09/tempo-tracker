import 'package:shared_preferences/shared_preferences.dart';

Future<String?> readSessions() async =>
    (await SharedPreferences.getInstance()).getString('tempo.sessions.v1');
Future<void> writeSessions(String data) async {
  final saved = await (await SharedPreferences.getInstance()).setString('tempo.sessions.v1', data);
  if (!saved) throw StateError('Unable to save sessions');
}

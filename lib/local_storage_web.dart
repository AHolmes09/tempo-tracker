import 'dart:js_interop';

@JS('tempoStorage.read')
external JSPromise<JSAny?> _read();
@JS('tempoStorage.write')
external JSPromise<JSAny?> _write(JSString data);

Future<String?> readSessions() async {
  final value = await _read().toDart;
  return (value as JSString?)?.toDart;
}
Future<void> writeSessions(String data) async {
  await _write(data.toJS).toDart;
}

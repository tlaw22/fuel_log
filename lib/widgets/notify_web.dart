import 'dart:convert';
import 'dart:js_interop';

@JS('fuelLogNotifications.requestPermission')
external JSPromise<JSString> _requestPermission();

@JS('fuelLogNotifications.show')
external JSPromise<JSAny?> _show(JSString data);

@JS('fuelLogNotifications.cancel')
external JSPromise<JSAny?> _cancel();

@JS('fuelLogNotifications.cancelLunch')
external JSPromise<JSAny?> _cancelLunch();

Future<bool> requestPermission() async =>
    (await _requestPermission().toDart).toDart == 'granted';

Future<void> show(Map<String, Object?> data) async {
  await _show(jsonEncode(data).toJS).toDart;
}

Future<void> cancel() async {
  await _cancel().toDart;
}

Future<void> cancelLunch() async {
  await _cancelLunch().toDart;
}

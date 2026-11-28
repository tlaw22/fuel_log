// Web photo-folder picker adapter.
// Uses the browser folder API and returns file names and bytes for pump-photo storage.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

@JS('fuelLogFolderPicker.pick')
external JSPromise<JSArray<JSObject>?> _pick();

/// Lets the user pick a folder; returns null when cancelled.
Future<List<({String name, Uint8List bytes})>?> pickFolderImages() async {
  final result = await _pick().toDart;
  if (result == null) return null;
  return [
    for (final file in result.toDart)
      (
        name: file.getProperty<JSString>('name'.toJS).toDart,
        bytes: file.getProperty<JSUint8Array>('bytes'.toJS).toDart,
      ),
  ];
}

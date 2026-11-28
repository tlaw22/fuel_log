// Non-web photo-folder picker adapter.
// Reports that folder selection is unavailable when the native implementation is not loaded.
import 'dart:typed_data';

Future<List<({String name, Uint8List bytes})>?> pickFolderImages() =>
    Future.error(UnsupportedError('Folder selection is unavailable.'));

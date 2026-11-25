part of '../app.dart';

class _PumpPhoto {
  final String id;
  final String name;

  const _PumpPhoto({required this.id, required this.name});
}

class _ExternalPhoto {
  final XFile file;
  final Future<Uint8List> bytes;

  _ExternalPhoto(XFile file)
      : file = file,
        bytes = file.readAsBytes();
}

class PumpPhotosPage extends StatefulWidget {
  final bool isActive;

  const PumpPhotosPage({super.key, this.isActive = false});

  @override
  State<PumpPhotosPage> createState() => _PumpPhotosPageState();
}

class _PumpPhotosPageState extends State<PumpPhotosPage> {
  final Map<String, Future<Uint8List>> _photoBytes = {};
  List<_PumpPhoto> _photos = [];
  List<_ExternalPhoto> _externalPhotos = [];
  bool _isLoading = true;
  String? _error;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isAndroidOnlyPlatform =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _refresh();
  }

  @override
  void didUpdateWidget(covariant PumpPhotosPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) _refresh();
  }

  Future<void> _refresh() async {
    if (_isAndroidOnlyPlatform) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (!_isAndroid) {
      if (!kIsWeb && (Platform.isLinux || Platform.isMacOS)) {
        await _chooseExternalPhotos();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final sdkInt =
          await _androidNativeChannel.invokeMethod<int>('androidSdkInt');
      if (sdkInt == null) {
        throw StateError('Could not determine the Android version.');
      }
      if (sdkInt < 29) {
        var permission = await Permission.storage.status;
        if (!permission.isGranted) {
          permission = await Permission.storage.request();
        }
        if (!mounted) return;
        if (!permission.isGranted) {
          final message = permission.isPermanentlyDenied
              ? 'Storage permission is disabled. Enable it in app settings to view pump photos.'
              : 'Storage permission is required to view pump photos.';
          setState(() {
            _isLoading = false;
            _error = message;
          });
          return;
        }
      }

      final rawPhotos = await _androidNativeChannel
          .invokeListMethod<dynamic>('listPumpPhotos');
      final photos = (rawPhotos ?? const []).map(_parsePhoto).toList()
        ..sort((first, second) => second.name.compareTo(first.name));
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _photoBytes.clear();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load pump photos: $error';
      });
    }
  }

  _PumpPhoto _parsePhoto(dynamic value) {
    if (value is! Map || value['id'] is! String || value['name'] is! String) {
      throw const FormatException('Android returned an invalid pump photo.');
    }
    return _PumpPhoto(
      id: value['id'] as String,
      name: value['name'] as String,
    );
  }

  Future<Uint8List> _loadPhoto(String id) => _photoBytes.putIfAbsent(
        id,
        () async {
          final bytes = await _androidNativeChannel
              .invokeMethod<Uint8List>('readPumpPhoto', {'id': id});
          if (bytes == null || bytes.isEmpty) {
            throw StateError('Android returned an empty photo.');
          }
          return bytes;
        },
      );

  String? get _defaultPicturesDirectory {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    final path = '$home${Platform.pathSeparator}Pictures';
    return Directory(path).existsSync() ? path : null;
  }

  bool _isImageFile(FileSystemEntity entity) {
    if (entity is! File) return false;
    return const {
      '.bmp',
      '.gif',
      '.heic',
      '.heif',
      '.jpeg',
      '.jpg',
      '.png',
      '.webp',
    }.contains(
        '.${entity.uri.pathSegments.last.split('.').last.toLowerCase()}');
  }

  Future<void> _chooseExternalPhotos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      late final List<XFile> files;
      if (kIsWeb) {
        files = await openFiles(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Image files',
              extensions: [
                'bmp',
                'gif',
                'heic',
                'heif',
                'jpeg',
                'jpg',
                'png',
                'webp',
              ],
            ),
          ],
        );
      } else if (Platform.isIOS) {
        files = await ImagePicker().pickMultiImage();
      } else {
        final directory = await getDirectoryPath(
          initialDirectory: _defaultPicturesDirectory,
          confirmButtonText: 'Open folder',
        );
        if (directory == null) {
          if (mounted) setState(() => _isLoading = false);
          return;
        }
        final entities = await Directory(directory)
            .list(followLinks: false)
            .where(_isImageFile)
            .toList();
        files =
            entities.whereType<File>().map((file) => XFile(file.path)).toList();
      }

      if (!mounted) return;
      setState(() {
        _externalPhotos = files.map(_ExternalPhoto.new).toList()
          ..sort(
              (first, second) => first.file.name.compareTo(second.file.name));
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not open pictures: $error';
      });
    }
  }

  Future<void> _showExternalPhoto(_ExternalPhoto photo) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(photo.file.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          content: SizedBox(
            width: 420,
            height: 420,
            child: FutureBuilder<Uint8List>(
              future: photo.bytes,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not open photo: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return InteractiveViewer(
                  child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Widget _buildExternalPhotoTile(_ExternalPhoto photo) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showExternalPhoto(photo),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FutureBuilder<Uint8List>(
                  future: photo.bytes,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: Icon(Icons.broken_image_outlined),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Image.memory(snapshot.data!, fit: BoxFit.cover);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  photo.file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _showPhoto(_PumpPhoto photo) => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(photo.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          content: SizedBox(
            width: 420,
            height: 420,
            child: FutureBuilder<Uint8List>(
              future: _loadPhoto(photo.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not open photo: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return InteractiveViewer(
                  child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                );
              },
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _confirmDelete(photo),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Future<void> _confirmDelete(_PumpPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete pump photo?'),
        content: Text('This will permanently delete ${photo.name}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final deleted = await _androidNativeChannel.invokeMethod<bool>(
        'deletePumpPhoto',
        {'id': photo.id},
      );
      if (deleted != true) {
        throw StateError('The selected photo was not deleted.');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() {
        _photos.removeWhere((item) => item.id == photo.id);
        _photoBytes.remove(photo.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pump photo deleted'),
          duration: kAppSnackBarDuration,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete pump photo: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  Widget _buildPhotoTile(_PumpPhoto photo) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showPhoto(photo),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FutureBuilder<Uint8List>(
                  future: _loadPhoto(photo.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(
                        child: Icon(Icons.broken_image_outlined),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return Image.memory(snapshot.data!, fit: BoxFit.cover);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  photo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_isAndroidOnlyPlatform) return _buildAndroidOnlyFeature();
    if (!_isAndroid) return _buildExternalGallery();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Pump Photos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh photos',
                onPressed: _isLoading ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _refresh,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _photos.isEmpty
                      ? const Center(
                          child: Text(
                            'No pump photos saved in Documents/fuel-logs yet.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 700
                                ? 4
                                : constraints.maxWidth >= 450
                                    ? 3
                                    : 2;
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 0.9,
                              ),
                              itemCount: _photos.length,
                              itemBuilder: (context, index) =>
                                  _buildPhotoTile(_photos[index]),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildAndroidOnlyFeature() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Pump Photos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: FilledButton.tonal(
                onPressed: null,
                child: Text('Android Only Feature'),
              ),
            ),
          ),
        ],
      );

  Widget _buildExternalGallery() {
    final pickerLabel = kIsWeb
        ? 'Select Pictures'
        : Platform.isIOS
            ? 'Choose Photos'
            : 'Open Pictures Folder';
    final emptyMessage = kIsWeb
        ? 'Select pictures from your device to view them here.'
        : Platform.isIOS
            ? 'Choose photos from your library to view them here.'
            : 'Choose the Pictures folder to browse its images.';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Pictures',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _isLoading ? null : _chooseExternalPhotos,
                icon: const Icon(
                    kIsWeb ? Icons.image_search_outlined : Icons.folder_open),
                label: Text(pickerLabel),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ),
                    )
                  : _externalPhotos.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              emptyMessage,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 700
                                ? 4
                                : constraints.maxWidth >= 450
                                    ? 3
                                    : 2;
                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 0.9,
                              ),
                              itemCount: _externalPhotos.length,
                              itemBuilder: (context, index) =>
                                  _buildExternalPhotoTile(
                                      _externalPhotos[index]),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

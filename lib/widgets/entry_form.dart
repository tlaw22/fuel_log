/// Fuel fill-up add and edit form.
/// Validates purchase data, captures pump photos, saves entries, and provides delete actions.
part of '../app.dart';

// ======================= Entry form =======================

/// Modal form for creating or editing a fuel fill-up.
class EntryForm extends StatefulWidget {
  final FuelEntry? existing;
  final double? lastOdometer;
  final Future<void> Function()? onDelete;
  final VoidCallback? onNewSavePressed;
  final bool initialSoundMuted;
  final ValueChanged<bool>? onSoundMutedChanged;
  final ValueChanged<String>? onValidatedSavePressed;

  /// Creates an add or edit form, optionally with existing entry and delete actions.
  const EntryForm({
    super.key,
    this.existing,
    this.lastOdometer,
    this.onDelete,
    this.onNewSavePressed,
    this.initialSoundMuted = false,
    this.onSoundMutedChanged,
    this.onValidatedSavePressed,
  });

  /// Creates the entry form state.
  @override
  State<EntryForm> createState() => _EntryFormState();
}

/// State that validates and submits fuel fill-up form values.
class _EntryFormState extends State<EntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late DateTime _date;
  late final TextEditingController _price;
  late final TextEditingController _volume;
  late final TextEditingController _odo;
  late bool _soundMuted;

  /// Initializes form controllers and date from a new or existing entry.
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _soundMuted = widget.initialSoundMuted;
    _date = e?.date ?? DateTime.now();
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    _volume = TextEditingController(text: e != null ? '${e.volume}' : '');
    _odo = TextEditingController(text: e != null ? '${e.odometer}' : '');
  }

  /// Releases the form text editing controllers.
  @override
  void dispose() {
    _price.dispose();
    _volume.dispose();
    _odo.dispose();
    super.dispose();
  }

  /// Parses a localized decimal string into a double.
  double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  /// Validates that a required numeric field exists and is positive.
  String? _positive(String? s) {
    final v = _parse(s ?? '');
    if (v == null) return 'Enter a number';
    if (v <= 0) return 'Must be greater than 0';
    return null;
  }

  /// Calculates the current price-times-volume preview when both values parse.
  double? get _previewTotal {
    final p = _parse(_price.text);
    final v = _parse(_volume.text);
    return (p != null && v != null) ? p * v : null;
  }

  bool get _canTakePumpPhoto =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens a date picker and updates the selected fill-up date.
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  /// Captures a gas-pump photo and saves it to Documents/fuel-logs on Android.
  Future<void> _takePumpPhoto() async {
    if (!_canTakePumpPhoto) return;

    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (photo == null || !mounted) return;

      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Save pump photo?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 420),
            child: Image.file(File(photo.path), fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Discard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (shouldSave != true || !mounted) return;

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
              ? 'Storage permission is disabled. Enable it in app settings to save photos.'
              : 'Storage permission is required to save photos.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: kAppSnackBarDuration,
            ),
          );
          return;
        }
      }

      final name =
          'fuel_log_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg';
      final savedLocation =
          await _androidNativeChannel.invokeMethod<String>('savePumpPhoto', {
        'name': name,
        'bytes': await photo.readAsBytes(),
      });
      if (savedLocation == null) {
        throw StateError('Android did not return the saved photo location.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo saved to $savedLocation'),
          duration: kAppSnackBarDuration,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save pump photo: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  /// Validates the form and returns a created or edited entry to the caller.
  void _submit() {
    if (widget.existing == null && !_soundMuted) {
      widget.onNewSavePressed?.call();
    }
    if (!_formKey.currentState!.validate()) return;
    widget.onValidatedSavePressed?.call(_volume.text.trim());
    Navigator.pop(
      context,
      FuelEntry(
        id: widget.existing?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        date: DateTime(_date.year, _date.month, _date.day),
        price: _parse(_price.text)!,
        volume: _parse(_volume.text)!,
        odometer: _parse(_odo.text)!,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Builds the fill-up date, numeric fields, preview, and save controls.
  @override
  Widget build(BuildContext context) {
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (widget.existing == null) ...[
                    CircleAvatar(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.local_gas_station),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      widget.existing == null ? 'New fill-up' : 'Edit fill-up',
                      style: widget.existing == null
                          ? Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                    : kBlue,
                                fontWeight: FontWeight.bold,
                              )
                          : Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (widget.existing == null && _canTakePumpPhoto)
                    IconButton(
                      tooltip: 'Take pump photo',
                      visualDensity: VisualDensity.compact,
                      onPressed: _takePumpPhoto,
                      icon: const Icon(Icons.photo_camera_outlined, size: 40),
                    ),
                  if (widget.existing != null)
                    IconButton(
                      tooltip: 'Delete fill-up',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onDelete == null
                          ? null
                          : () async => widget.onDelete!(),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_dateFmt.format(_date)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: decimal,
                decoration: const InputDecoration(
                  labelText: 'Fuel price per $kVolumeUnit',
                  prefixText: '$kCurrency ',
                  border: OutlineInputBorder(),
                ),
                validator: _positive,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _volume,
                keyboardType: decimal,
                decoration: const InputDecoration(
                  labelText: 'Amount purchased',
                  suffixText: kVolumeUnit,
                  border: OutlineInputBorder(),
                ),
                validator: _positive,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _odo,
                keyboardType: decimal,
                decoration: InputDecoration(
                  labelText: 'Odometer reading',
                  suffixText: kDistanceUnit,
                  helperText: widget.lastOdometer != null
                      ? 'Latest logged: ${_num1.format(widget.lastOdometer)}'
                      : null,
                  border: const OutlineInputBorder(),
                ),
                validator: _positive,
              ),
              const SizedBox(height: 12),
              if (_previewTotal != null)
                Text('Total: ${_money.format(_previewTotal)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              if (widget.existing == null)
                Row(
                  children: [
                    _MuteSoundControl(
                      muted: _soundMuted,
                      onChanged: (muted) {
                        setState(() => _soundMuted = muted);
                        widget.onSoundMutedChanged?.call(muted);
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submit,
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                )
              else
                FilledButton(onPressed: _submit, child: const Text('Save')),
            ],
          ),
        ),
      ),
    );
  }
}

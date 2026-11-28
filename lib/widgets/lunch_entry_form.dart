/// Lunch add and edit form.
/// Offers restaurant search, date/time selection, custom prices, and recurring lunch saving.
part of '../app.dart';

class _LunchEntryForm extends StatefulWidget {
  const _LunchEntryForm({
    required this.restaurants,
    required this.onSave,
    required this.onValidatedSavePressed,
  });

  final List<String> restaurants;
  final Future<void> Function(_LunchEntry entry) onSave;
  final VoidCallback onValidatedSavePressed;

  @override
  State<_LunchEntryForm> createState() => _LunchEntryFormState();
}

class _LunchEntryFormState extends State<_LunchEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _restaurant = TextEditingController();
  final _price = TextEditingController();
  DateTime _date = DateTime.now();
  bool _showSuggestions = false;
  bool _otherSelected = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _restaurant.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() => _date = DateTime(selected.year, selected.month,
          selected.day, _date.hour, _date.minute));
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (selected != null && mounted) {
      setState(() => _date = DateTime(
          _date.year, _date.month, _date.day, selected.hour, selected.minute));
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    widget.onValidatedSavePressed();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final entry = _LunchEntry(
        restaurant: _restaurant.text.trim(),
        date: _date,
        price: double.parse(_price.text.trim()),
      );
      await widget.onSave(entry);
      if (mounted) Navigator.of(context).pop(entry);
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _error = error.toString());
      } else {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'FuelLog lunch entry',
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matching = widget.restaurants.where((name) =>
        name.toLowerCase().contains(_restaurant.text.trim().toLowerCase()));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New lunch', style: Theme.of(context).textTheme.titleLarge),
              TextFormField(
                key: const ValueKey('lunch-restaurant-input'),
                controller: _restaurant,
                decoration: const InputDecoration(
                  labelText: 'Restaurant',
                  suffixIcon: Icon(Icons.search),
                ),
                onTap: () => setState(() => _showSuggestions = true),
                onChanged: (_) =>
                    setState(() => _showSuggestions = !_otherSelected),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return 'Enter a restaurant';
                  if (!_otherSelected && !widget.restaurants.contains(name)) {
                    return 'Choose a suggestion or Other restaurant';
                  }
                  return null;
                },
              ),
              if (_showSuggestions)
                SizedBox(
                  height: math.min(200.0, (matching.length + 1) * 48.0),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      ListTile(
                        dense: true,
                        title: const Text('Other restaurant'),
                        onTap: () => setState(() {
                          _otherSelected = true;
                          _restaurant.clear();
                          _showSuggestions = false;
                        }),
                      ),
                      for (final name in matching)
                        ListTile(
                          dense: true,
                          title: Text(name),
                          onTap: () => setState(() {
                            _restaurant.text = name;
                            _otherSelected = false;
                            _showSuggestions = false;
                            FocusScope.of(context).unfocus();
                          }),
                        ),
                    ],
                  ),
                ),
              TextFormField(
                key: const ValueKey('lunch-price-input'),
                controller: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Price', prefixText: kCurrency),
                validator: _validateLunchAmount,
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_dateFmt.format(_date)),
                  ),
                  TextButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time),
                    label: Text(TimeOfDay.fromDateTime(_date).format(context)),
                  ),
                ],
              ),
              if (_error != null)
                Text('Could not save lunch: $_error',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save lunch'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

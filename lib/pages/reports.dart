part of '../app.dart';

const String _savedReportsPreferencesKey = 'fuel_reports_v1';

class _SavedFuelReport {
  final String fileName;
  final String contents;

  const _SavedFuelReport({
    required this.fileName,
    required this.contents,
  });

  Map<String, String> toJson() => {
        'fileName': fileName,
        'contents': contents,
      };

  factory _SavedFuelReport.fromJson(dynamic value) {
    if (value is! Map) {
      throw const FormatException('Invalid saved fuel report.');
    }
    final map = Map<String, dynamic>.from(value);
    final fileName = map['fileName'];
    final contents = map['contents'];
    if (fileName is! String || contents is! String) {
      throw const FormatException('Invalid saved fuel report fields.');
    }
    return _SavedFuelReport(fileName: fileName, contents: contents);
  }
}

/// Displays, creates, and opens plain-text snapshots of the fuel log.
class ReportsPage extends StatefulWidget {
  final List<FuelEntry> entries;
  final Map<String, double> distances;

  /// Creates the reports page for the supplied fuel log snapshot.
  const ReportsPage({
    super.key,
    required this.entries,
    required this.distances,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  List<_SavedFuelReport> _reports = [];
  bool _loading = true;
  bool _generating = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadReports());
  }

  Future<void> _loadReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_savedReportsPreferencesKey);
      final reports = raw == null
          ? <_SavedFuelReport>[]
          : (jsonDecode(raw) as List<dynamic>)
              .map(_SavedFuelReport.fromJson)
              .toList();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
        _loadError = null;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'FuelLog saved reports',
        ),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  String _createReportContents(DateTime generatedAt) {
    final entries = [...widget.entries]..sort((a, b) {
        final dateOrder = a.date.compareTo(b.date);
        return dateOrder != 0 ? dateOrder : a.odometer.compareTo(b.odometer);
      });
    final totals = Stats.from(entries, widget.distances);
    final entriesByMonth = <DateTime, List<FuelEntry>>{};
    for (final entry in entries) {
      final month = DateTime(entry.date.year, entry.date.month);
      entriesByMonth.putIfAbsent(month, () => []).add(entry);
    }
    final months = entriesByMonth.keys.toList()
      ..sort((first, second) => second.compareTo(first));
    final lines = <String>[
      'Fuel Log Report',
      'Generated: ${DateFormat.yMMMd().add_jm().format(generatedAt)}',
      '',
      'Fill-ups: ${totals.fills}',
      'Total fuel: ${_num1.format(totals.volume)} $kVolumeUnit',
      'Total distance: ${_num1.format(totals.distance)} $kDistanceUnit',
      'Overall efficiency: ${fmtEfficiency(totals.efficiency)}',
      '',
      'Monthly summary (up to 2 most recent months):',
      if (months.isEmpty) 'No monthly data available.',
      for (final month in months.take(2))
        _formatMonthlySummary(month, entriesByMonth[month]!),
      '',
      'Fill-up details (oldest to newest):',
    ];

    if (entries.isEmpty) {
      lines.add('No fill-ups recorded.');
    } else {
      for (final entry in entries) {
        final distance = widget.distances[entry.id];
        final efficiency = distance == null || entry.volume <= 0
            ? '—'
            : fmtEfficiency(distance / entry.volume);
        lines.add(
          '${_dateFmt.format(entry.date)} | '
          'Odometer: ${_num1.format(entry.odometer)} $kDistanceUnit | '
          'Price: ${_money.format(entry.price)} per $kVolumeUnit | '
          'Fuel: ${_num1.format(entry.volume)} $kVolumeUnit | '
          'Cost: ${_money.format(entry.total)} | '
          'Distance since last: ${distance == null ? '—' : '${_num1.format(distance)} $kDistanceUnit'} | '
          'Efficiency: $efficiency',
        );
      }
    }
    return lines.join('\n');
  }

  String _formatMonthlySummary(DateTime month, List<FuelEntry> entries) {
    final totals = Stats.from(entries, widget.distances);
    return '${_monthFmt.format(month)} | '
        'Fill-ups: ${totals.fills} | '
        'Spending: ${_money.format(totals.spent)} | '
        'Fuel: ${_num1.format(totals.volume)} $kVolumeUnit | '
        'Distance: ${_num1.format(totals.distance)} $kDistanceUnit | '
        'Efficiency: ${fmtEfficiency(totals.efficiency)}';
  }

  Future<String> _saveReportToDocuments(_SavedFuelReport report) async {
    final sdkInt =
        await fuelLogNativeChannel.invokeMethod<int>('androidSdkInt');
    if (sdkInt == null) {
      throw StateError('Could not determine the Android version.');
    }
    if (sdkInt < 29) {
      var permission = await Permission.storage.status;
      if (!permission.isGranted) {
        permission = await Permission.storage.request();
      }
      if (!permission.isGranted) {
        throw StateError('Storage permission is required to save reports.');
      }
    }
    return await fuelLogNativeChannel.invokeMethod<String>('saveTextReport', {
          'name': report.fileName,
          'bytes': Uint8List.fromList(utf8.encode(report.contents)),
        }) ??
        (throw StateError('Android did not return the saved report path.'));
  }

  Future<void> _generateReport() async {
    setState(() => _generating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final now = DateTime.now();
      final report = _SavedFuelReport(
        fileName:
            'fuel_log_report_${DateFormat('yyyy-MM-dd_HHmmss_SSS').format(now)}.txt',
        contents: _createReportContents(now),
      );
      String? savedPath;
      if (!kIsWeb && Platform.isAndroid) {
        savedPath = await _saveReportToDocuments(report);
      }

      final reports = [report, ..._reports];
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(
        _savedReportsPreferencesKey,
        jsonEncode(reports.map((savedReport) => savedReport.toJson()).toList()),
      )) {
        throw StateError('The generated report could not be saved locally.');
      }
      if (!mounted) return;
      setState(() => _reports = reports);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            savedPath == null
                ? 'Report generated and saved locally.'
                : 'Report saved to $savedPath',
          ),
          duration: kAppSnackBarDuration,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not generate report: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _downloadReport(_SavedFuelReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      String savedPath;
      if (!kIsWeb && Platform.isAndroid) {
        savedPath = await _saveReportToDocuments(report);
      } else {
        final location = await getSaveLocation(
          suggestedName: report.fileName,
        );
        if (location == null) return;
        await XFile.fromData(
          Uint8List.fromList(utf8.encode(report.contents)),
          mimeType: 'text/plain',
          name: report.fileName,
        ).saveTo(location.path);
        savedPath = kIsWeb ? report.fileName : location.path;
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Report saved to $savedPath'),
          duration: kAppSnackBarDuration,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not download report: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  Future<void> _shareReport(_SavedFuelReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (kIsWeb) {
        final mailto = Uri(
          scheme: 'mailto',
          queryParameters: {
            'subject': 'Fuel Log Report',
            'body': report.contents,
          },
        );
        if (!await launchUrl(
          mailto,
          mode: LaunchMode.externalApplication,
        )) {
          throw StateError('The default mail app could not be opened.');
        }
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                Uint8List.fromList(utf8.encode(report.contents)),
                mimeType: 'text/plain',
                name: report.fileName,
              ),
            ],
            fileNameOverrides: [report.fileName],
            subject: 'Fuel Log Report',
            text: 'Fuel Log report attached.',
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not share report: $error'),
          duration: kAppSnackBarDuration,
        ),
      );
    }
  }

  void _openReport(_SavedFuelReport report) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ReportPreviewSheet(
        report: report,
        onDownload: () => unawaited(_downloadReport(report)),
        onShare: () => unawaited(_shareReport(report)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reports')),
        body: Column(
          children: [
            Expanded(child: _buildReportList()),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading || _generating || _loadError != null
                      ? null
                      : () => unawaited(_generateReport()),
                  icon: _generating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.description_outlined),
                  label: const Text('Generate Report'),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildReportList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Could not load saved reports: $_loadError'),
        ),
      );
    }
    if (_reports.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No reports yet. Select Generate Report to create one.'),
        ),
      );
    }
    return ListView.separated(
      itemCount: _reports.length,
      itemBuilder: (context, index) {
        final report = _reports[index];
        return ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(report.fileName),
          subtitle: const Text('Tap to read or download'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openReport(report),
        );
      },
      separatorBuilder: (context, index) => const Divider(height: 1),
    );
  }
}

class _ReportPreviewSheet extends StatelessWidget {
  final _SavedFuelReport report;
  final VoidCallback onDownload;
  final VoidCallback onShare;

  const _ReportPreviewSheet({
    required this.report,
    required this.onDownload,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      report.fileName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close report',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(report.contents),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onDownload,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Download Report'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('Share Report'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../models/biometry_measurement.dart';
import '../../services/biometry_service.dart';
import '../../utils/date_formatter.dart';

class BiometryScreen extends StatefulWidget {
  final Bill bill;

  const BiometryScreen({super.key, required this.bill});

  @override
  State<BiometryScreen> createState() => _BiometryScreenState();
}

class _BiometryScreenState extends State<BiometryScreen> {
  List<BiometryMeasurement>? _measurements;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.bill.accessionNumber == null) {
      setState(() {
        _error = 'No accession number on this bill.';
        _loading = false;
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final measurements = await context
          .read<BiometryService>()
          .getMeasurements(widget.bill.accessionNumber!);
      if (mounted) setState(() { _measurements = measurements; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Biometry — ${widget.bill.patientName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _meta('Patient', widget.bill.patientName),
                    if (widget.bill.patientId?.isNotEmpty == true)
                      _meta('ID', widget.bill.patientId!),
                    if (widget.bill.patientAge != null)
                      _meta('Age', '${widget.bill.patientAge} yrs'),
                    _meta('Accession', widget.bill.accessionNumber ?? '-'),
                    _meta('Study date', formatDateTime(widget.bill.createdAt)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 40, color: Colors.orange),
                      const SizedBox(height: 8),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.orange)),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_measurements == null || _measurements!.isEmpty)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.hourglass_empty,
                          size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No measurements found yet.\n'
                        'Images may still be uploading to Orthanc.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_measurements!.length} measurement${_measurements!.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Card(
                        child: ListView.separated(
                          itemCount: _measurements!.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = _measurements![i];
                            return ListTile(
                              dense: true,
                              title: Text(m.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500)),
                              trailing: Text(
                                m.displayUnit.isNotEmpty
                                    ? '${m.displayValue} ${m.displayUnit}'
                                    : m.displayValue,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _meta(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

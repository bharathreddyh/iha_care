import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import 'dart:io';

import '../../models/billing/incentive_record.dart';
import '../../models/billing/referral_doctor.dart';
import '../../services/billing_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
import '../../utils/excel_exporter.dart';
import '../../utils/pdf_generator.dart';

class IncentiveReportScreen extends StatefulWidget {
  const IncentiveReportScreen({super.key});

  @override
  State<IncentiveReportScreen> createState() => _IncentiveReportScreenState();
}

class _IncentiveReportScreenState extends State<IncentiveReportScreen> {
  final _now = DateTime.now();
  late int _selectedYear;
  late int _selectedMonth;

  List<IncentiveRecord> _records = [];
  Map<String, ReferralDoctor> _doctors = {};
  // Per-doctor list of individual bills (patient, date, scan, incentive)
  Map<String, List<Map<String, dynamic>>> _detailByDoctor = {};
  bool _loading = false;
  bool _exporting = false;
  bool _exportingExcel = false;

  @override
  void initState() {
    super.initState();
    _selectedYear = _now.year;
    _selectedMonth = _now.month;
    _calculate();
  }

  String get _monthKey =>
      '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

  Future<void> _calculate() async {
    setState(() => _loading = true);
    final service = context.read<BillingService>();
    final records = await service.calculateMonthlyIncentives(_monthKey);
    final allDocs = await service.getReferralDoctors();
    final docMap = {for (final d in allDocs) d.id: d};

    // Per-bill detail rows, grouped by doctor
    final detailRows = await service.getReferralDetailForMonth(_monthKey);
    final detailByDoctor = <String, List<Map<String, dynamic>>>{};
    for (final row in detailRows) {
      detailByDoctor
          .putIfAbsent(row['referral_doctor_id'] as String, () => [])
          .add(row);
    }

    if (mounted) {
      setState(() {
        _records = records;
        _doctors = docMap;
        _detailByDoctor = detailByDoctor;
        _loading = false;
      });
    }
  }

  Future<void> _exportExcel() async {
    // 1. Load raw rows first (needed to know which doctors have data)
    final service = context.read<BillingService>();
    final allRows = await service.getReferralDetailForMonth(_monthKey);

    if (allRows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No referral data for this month.')),
        );
      }
      return;
    }

    // 2. Collect distinct doctor IDs that have rows this month
    final doctorIds = allRows
        .map((r) => r['referral_doctor_id'] as String)
        .toSet()
        .toList()
      ..sort((a, b) {
        final na = _doctors[a]?.name ?? a;
        final nb = _doctors[b]?.name ?? b;
        return na.compareTo(nb);
      });

    // 3. Show doctor-picker dialog
    if (!mounted) return;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _DoctorPickerDialog(
        doctorIds: doctorIds,
        doctors: _doctors,
      ),
    );
    if (selected == null || selected.isEmpty) return;

    // 4. Filter rows to selected doctors and export
    setState(() => _exportingExcel = true);
    try {
      final filteredRows =
          allRows.where((r) => selected.contains(r['referral_doctor_id'])).toList();
      final filePath = await exportReferralSummaryExcel(
        month: _monthKey,
        rows: filteredRows,
        doctors: _doctors,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: $filePath'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openFile(filePath),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  void _openFile(String path) {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else {
      Process.run('xdg-open', [path]);
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final service = context.read<BillingService>();
      final rows = await service.getReferralDetailForMonth(_monthKey);
      final bytes = await generateIncentiveReport(
        month: _monthKey,
        rows: rows,
        doctors: _doctors,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'incentives_$_monthKey.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _markAllPaid() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark All Paid?'),
        content: Text(
            'Mark all incentives for ${formatMonthYear(_monthKey)} as paid?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed == true) {
      final service = context.read<BillingService>();
      for (final r in _records) {
        if (r.paymentStatus == 'unpaid') {
          await service.markIncentivePaid(r.id);
        }
      }
      _calculate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalReferrals =
        _records.fold<int>(0, (s, r) => s + r.referralCount);
    final totalBilled =
        _records.fold<double>(0, (s, r) => s + r.totalBilled);
    final totalIncentive =
        _records.fold<double>(0, (s, r) => s + r.incentiveAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incentive Report'),
        actions: [
          if (_exportingExcel)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: 'Export Excel',
              onPressed: _exportExcel,
            ),
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Export PDF',
              onPressed: _records.isEmpty ? null : _exportPdf,
            ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            tooltip: 'Mark All Paid',
            onPressed: _records.isEmpty ? null : _markAllPaid,
          ),
        ],
      ),
      body: Column(
        children: [
          // Month picker
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Month: ',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _selectedMonth,
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text([
                        'Jan','Feb','Mar','Apr','May','Jun',
                        'Jul','Aug','Sep','Oct','Nov','Dec'
                      ][i]),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedMonth = v);
                    _calculate();
                  },
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: _selectedYear,
                  items: List.generate(
                    5,
                    (i) => DropdownMenuItem(
                      value: _now.year - i,
                      child: Text((_now.year - i).toString()),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedYear = v);
                    _calculate();
                  },
                ),
              ],
            ),
          ),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_records.isEmpty)
            const Expanded(
                child: Center(child: Text('No referral data for this month.')))
          else
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _records.length + 1,
                itemBuilder: (ctx, index) {
                  // Last item: totals summary card
                  if (index == _records.length) {
                    return Card(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      margin: const EdgeInsets.only(top: 8, bottom: 24),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$totalReferrals referrals',
                                    style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Collection: ',
                                        style: TextStyle(fontSize: 12)),
                                    Text(formatCurrency(totalBilled),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Incentive: ',
                                        style: TextStyle(fontSize: 13)),
                                    Text(
                                      formatCurrency(totalIncentive),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final r = _records[index];
                  final doc = _doctors[r.referralDoctorId];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      tilePadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(doc?.name ?? r.referralDoctorId,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                if (doc?.clinicName != null)
                                  Text(doc!.clinicName!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Collection: ',
                                      style: Theme.of(context).textTheme.bodySmall),
                                  Text(formatCurrency(r.totalBilled),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Incentive: ',
                                      style: Theme.of(context).textTheme.bodySmall),
                                  Text(formatCurrency(r.incentiveAmount),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                ],
                              ),
                              Text('${r.referralCount} referral${r.referralCount == 1 ? '' : 's'}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                          const SizedBox(width: 8),
                          _statusChip(context, r.paymentStatus),
                        ],
                      ),
                      children: [
                        Builder(builder: (context) {
                          final bills =
                              _detailByDoctor[r.referralDoctorId] ?? const [];
                          if (bills.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'No bill details available.',
                                style: TextStyle(fontSize: 12),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Table(
                              columnWidths: const {
                                0: FlexColumnWidth(3),
                                1: FlexColumnWidth(2),
                                2: FlexColumnWidth(3),
                                3: FlexColumnWidth(2),
                              },
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                  children: [
                                    _cell('Patient', bold: true),
                                    _cell('Date', bold: true),
                                    _cell('Scan', bold: true),
                                    _cell('Incentive', bold: true),
                                  ],
                                ),
                                ...bills.map((b) => TableRow(children: [
                                      _cell((b['patient_name'] as String?) ??
                                          '—'),
                                      _cell(formatDate(
                                          (b['created_at'] as String?) ?? '')),
                                      _cell(
                                          (b['scan_type_name'] as String?) ??
                                              'Unknown'),
                                      _cell(formatCurrency(
                                          (b['incentive_rate'] as num? ?? 0)
                                              .toDouble())),
                                    ])),
                              ],
                            ),
                          );
                        }),
                        if (r.paymentStatus == 'unpaid')
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Mark Paid'),
                              onPressed: () async {
                                await context
                                    .read<BillingService>()
                                    .markIncentivePaid(r.id);
                                _calculate();
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status) {
    final isPaid = status == 'paid';
    return Chip(
      label: Text(
        isPaid ? 'Paid' : 'Unpaid',
        style: TextStyle(
            fontSize: 11, color: isPaid ? Colors.green : Colors.orange),
      ),
      side: BorderSide(color: isPaid ? Colors.green : Colors.orange),
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _cell(String text, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        ),
      );
}

// ── Doctor picker dialog ───────────────────────────────────────────────────────

class _DoctorPickerDialog extends StatefulWidget {
  final List<String> doctorIds;
  final Map<String, ReferralDoctor> doctors;

  const _DoctorPickerDialog({
    required this.doctorIds,
    required this.doctors,
  });

  @override
  State<_DoctorPickerDialog> createState() => _DoctorPickerDialogState();
}

class _DoctorPickerDialogState extends State<_DoctorPickerDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.doctorIds); // all selected by default
  }

  bool get _allSelected => _selected.length == widget.doctorIds.length;

  void _toggleAll() => setState(() {
        _selected = _allSelected ? {} : Set.from(widget.doctorIds);
      });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Doctors'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Select All toggle
            CheckboxListTile(
              value: _allSelected,
              tristate: false,
              onChanged: (_) => _toggleAll(),
              title: const Text('Select All',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  children: widget.doctorIds.map((id) {
                    final doc = widget.doctors[id];
                    return CheckboxListTile(
                      value: _selected.contains(id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(id);
                        } else {
                          _selected.remove(id);
                        }
                      }),
                      title: Text(doc != null ? 'Dr. ${doc.name}' : id),
                      subtitle: doc?.clinicName != null &&
                              doc!.clinicName!.isNotEmpty
                          ? Text(doc.clinicName!)
                          : null,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: Text('Export (${_selected.length})'),
        ),
      ],
    );
  }
}

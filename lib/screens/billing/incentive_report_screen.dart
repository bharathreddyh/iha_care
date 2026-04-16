import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../models/billing/incentive_record.dart';
import '../../models/billing/referral_doctor.dart';
import '../../services/billing_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
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
  bool _loading = false;
  bool _exporting = false;

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
    if (mounted) {
      setState(() {
        _records = records;
        _doctors = docMap;
        _loading = false;
      });
    }
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    final bytes = await generateIncentiveReport(_records, _doctors, _monthKey);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'incentives_$_monthKey.pdf',
    );
    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _markAllPaid() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark All Paid?'),
        content: Text('Mark all incentives for ${formatMonthYear(_monthKey)} as paid?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
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
    final totalReferrals = _records.fold<int>(0, (s, r) => s + r.referralCount);
    final totalBilled = _records.fold<double>(0, (s, r) => s + r.totalBilled);
    final totalIncentive = _records.fold<double>(0, (s, r) => s + r.incentiveAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incentive Report'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
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
                const Text('Month: ', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _selectedMonth,
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                        ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][i],
                      ),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) setState(() { _selectedMonth = v; });
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
                    if (v != null) setState(() { _selectedYear = v; });
                    _calculate();
                  },
                ),
              ],
            ),
          ),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_records.isEmpty)
            const Expanded(child: Center(child: Text('No referral data for this month.')))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 20,
                    columns: const [
                      DataColumn(label: Text('Doctor')),
                      DataColumn(label: Text('Clinic')),
                      DataColumn(label: Text('Referrals'), numeric: true),
                      DataColumn(label: Text('Billed'), numeric: true),
                      DataColumn(label: Text('Incentive'), numeric: true),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: [
                      ..._records.map((r) {
                        final doc = _doctors[r.referralDoctorId];
                        return DataRow(cells: [
                          DataCell(Text(doc?.name ?? r.referralDoctorId)),
                          DataCell(Text(doc?.clinicName ?? '-')),
                          DataCell(Text(r.referralCount.toString())),
                          DataCell(Text(formatCurrency(r.totalBilled))),
                          DataCell(Text(formatCurrency(r.incentiveAmount))),
                          DataCell(
                            Chip(
                              label: Text(
                                r.paymentStatus == 'paid' ? 'Paid' : 'Unpaid',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: r.paymentStatus == 'paid'
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                              side: BorderSide(
                                color: r.paymentStatus == 'paid'
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              backgroundColor: Colors.transparent,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ]);
                      }),
                      // Totals row
                      DataRow(
                        color: WidgetStateProperty.all(
                            Theme.of(context).colorScheme.surfaceContainerHighest),
                        cells: [
                          const DataCell(Text('TOTAL',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                          const DataCell(Text('')),
                          DataCell(Text(totalReferrals.toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(formatCurrency(totalBilled),
                              style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(formatCurrency(totalIncentive),
                              style: const TextStyle(fontWeight: FontWeight.bold))),
                          const DataCell(Text('')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

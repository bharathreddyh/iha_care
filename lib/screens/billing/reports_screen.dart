import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../services/billing_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
import '../../utils/pdf_generator.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _now = DateTime.now();
  late int _selectedYear;
  late int _selectedMonth;
  Map<String, dynamic>? _data;
  bool _loading = false;
  bool _includeExcluded = false;
  bool _includeCancelled = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _selectedYear = _now.year;
    _selectedMonth = _now.month;
    _load();
  }

  String get _monthKey =>
      '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await context.read<BillingService>().getReportData(
          _monthKey,
          includeExcluded: _includeExcluded,
          includeCancelled: _includeCancelled,
        );
    if (mounted) setState(() { _data = data; _loading = false; });
  }

  Future<void> _export() async {
    if (_data == null) return;
    setState(() => _exporting = true);
    try {
      final bytes = await generateMonthlyReport(
        month: _monthKey,
        data: _data!,
        includeExcluded: _includeExcluded,
        includeCancelled: _includeCancelled,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'report_$_monthKey.pdf',
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
              onPressed: _data != null ? _export : null,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                Row(
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
                          child: Text(['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][i]),
                        ),
                      ),
                      onChanged: (v) {
                        if (v != null) setState(() { _selectedMonth = v; });
                        _load();
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
                        _load();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilterChip(
                      label: const Text('Include excluded'),
                      selected: _includeExcluded,
                      onSelected: (v) { setState(() => _includeExcluded = v); _load(); },
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Include cancelled'),
                      selected: _includeCancelled,
                      onSelected: (v) { setState(() => _includeCancelled = v); _load(); },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_data == null)
            const Expanded(child: Center(child: Text('No data')))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryCard(data: _data!),
                    const SizedBox(height: 16),

                    _sectionTitle('Scan Volume — ${formatMonthYear(_monthKey)}'),
                    const SizedBox(height: 8),
                    _ScanVolumeTable(rows: (_data!['scanVolume'] as List).cast()),
                    const SizedBox(height: 24),

                    _sectionTitle('Payment Mode Split'),
                    const SizedBox(height: 8),
                    _PaymentSplitTable(rows: (_data!['paymentSplit'] as List).cast()),
                    const SizedBox(height: 16),

                    _StatCard(
                      title: 'PCPNDT Form-F Count',
                      value: (_data!['pcpdntCount'] as int? ?? 0).toString(),
                      subtitle: formatMonthYear(_monthKey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

class _SummaryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = (data['totalRevenue'] as num? ?? 0).toDouble();
    final discount = (data['totalDiscount'] as num? ?? 0).toDouble();
    final count = data['totalCount'] as int? ?? 0;
    final excluded = data['excludedCount'] as int? ?? 0;
    final cancelled = data['cancelledCount'] as int? ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _row('Total Bills', count.toString()),
            _row('Gross Revenue', formatCurrency(total)),
            if (discount > 0) _row('Total Discount Given', formatCurrency(discount)),
            if (excluded > 0)
              _row('Excluded from this report', '$excluded bills', orange: true),
            if (cancelled > 0)
              _row('Cancelled this month', '$cancelled bills', orange: false, grey: true),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool orange = false, bool grey = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: orange ? Colors.orange.shade700 : grey ? Colors.grey : null)),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: orange ? Colors.orange.shade700 : grey ? Colors.grey : null)),
          ],
        ),
      );
}

class _ScanVolumeTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ScanVolumeTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Text('No scan data for this month.');

    final maxCount = rows.fold<int>(
        0, (m, r) => (r['cnt'] as int? ?? 0) > m ? r['cnt'] as int : m);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: rows.map((r) {
            final count = r['cnt'] as int? ?? 0;
            final revenue = (r['revenue'] as num? ?? 0).toDouble();
            final name = r['name'] as String? ?? 'Unknown';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(width: 140, child: Text(name, overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: maxCount > 0 ? count / maxCount : 0,
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 30,
                    child: Text('$count', textAlign: TextAlign.right),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: Text(formatCurrency(revenue),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PaymentSplitTable extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _PaymentSplitTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Text('No payment data for this month.');

    return Card(
      child: DataTable(
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text('Mode')),
          DataColumn(label: Text('Count'), numeric: true),
          DataColumn(label: Text('Total'), numeric: true),
        ],
        rows: rows.map((r) {
          return DataRow(cells: [
            DataCell(Text(r['payment_mode'] as String? ?? '-')),
            DataCell(Text((r['cnt'] as int? ?? 0).toString())),
            DataCell(Text(formatCurrency((r['total'] as num? ?? 0).toDouble()))),
          ]);
        }).toList(),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;

  const _StatCard({required this.title, required this.value, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}


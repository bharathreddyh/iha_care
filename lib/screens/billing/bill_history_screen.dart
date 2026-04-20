import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../models/billing/referral_doctor.dart';
import '../../models/billing/scan_type.dart';
import '../../services/billing_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
import '../../widgets/bill_actions.dart';
import 'patient_images_screen.dart';
import 'receipt_preview_screen.dart';

class BillHistoryScreen extends StatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  List<Bill> _bills = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_load);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_load);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setToday() {
    final today = DateTime.now();
    setState(() {
      _fromDate = DateTime(today.year, today.month, today.day);
      _toDate = _fromDate!.add(const Duration(days: 1));
    });
    _load();
  }

  void _clearDateFilter() {
    setState(() { _fromDate = null; _toDate = null; });
    _load();
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (range != null) {
      setState(() {
        _fromDate = range.start;
        _toDate = range.end.add(const Duration(days: 1));
      });
      _load();
    }
  }

  Future<void> _load() async {
    final bills = await context.read<BillingService>().getBills(
          searchTerm: _searchCtrl.text,
          statusFilter: _statusFilter,
          fromDate: _fromDate,
          toDate: _toDate,
        );
    if (mounted) setState(() { _bills = bills; _loading = false; });
  }

  Future<void> _openDetail(Bill bill) async {
    final service = context.read<BillingService>();
    final scan = bill.scanTypeId != null ? await service.getScanType(bill.scanTypeId!) : null;
    final doc = bill.referralDoctorId != null
        ? await service.getReferralDoctor(bill.referralDoctorId!)
        : null;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _BillDetailDialog(
        bill: bill,
        scanType: scan,
        referralDoctor: doc,
        onViewReceipt: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiptPreviewScreen(
                bill: bill,
                scanType: scan,
                referralDoctor: doc,
              ),
            ),
          );
        },
        onViewImages: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PatientImagesScreen(bill: bill),
            ),
          );
        },
        onMarkCompleted: () async {
          await service.markScanCompleted(bill.id);
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bill History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Search patient or bill ID…',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('All')),
                        DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                        DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                      ],
                      onChanged: (v) => setState(() {
                        _statusFilter = v ?? 'All';
                        _load();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: _setToday,
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      child: const Text('Today'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _pickDateRange,
                      icon: const Icon(Icons.date_range, size: 16),
                      label: Text(_fromDate == null
                          ? 'Date Range'
                          : '${_fromDate!.day}/${_fromDate!.month} – ${_toDate!.subtract(const Duration(days: 1)).day}/${_toDate!.subtract(const Duration(days: 1)).month}'),
                      style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                    if (_fromDate != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: _clearDateFilter,
                        tooltip: 'Clear date filter',
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _bills.isEmpty
                    ? const Center(child: Text('No bills found.'))
                    : ListView.builder(
                        itemCount: _bills.length,
                        itemBuilder: (_, i) {
                          final bill = _bills[i];
                          final cancelled = bill.isCancelled;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: cancelled
                                  ? Colors.red.shade100
                                  : bill.status == 'paid'
                                      ? Colors.green.shade100
                                      : Colors.orange.shade100,
                              child: Icon(
                                cancelled
                                    ? Icons.cancel
                                    : bill.status == 'paid'
                                        ? Icons.check
                                        : Icons.hourglass_empty,
                                color: cancelled
                                    ? Colors.red
                                    : bill.status == 'paid'
                                        ? Colors.green
                                        : Colors.orange,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              bill.patientName,
                              style: TextStyle(
                                decoration: cancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: cancelled ? Colors.grey : null,
                              ),
                            ),
                            subtitle: Text(
                              cancelled
                                  ? '${bill.id} · ${formatDate(bill.createdAt)} · Cancelled${bill.cancelReason != null ? ' — ${bill.cancelReason}' : ''}'
                                  : bill.reportExcluded
                                      ? '${bill.id} · ${formatDate(bill.createdAt)} · Excluded from report'
                                      : '${bill.id} · ${formatDate(bill.createdAt)}',
                              style: cancelled
                                  ? const TextStyle(color: Colors.red)
                                  : bill.reportExcluded
                                      ? TextStyle(color: Colors.orange.shade700)
                                  : null,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatCurrency(bill.finalAmount),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: cancelled
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: cancelled ? Colors.grey : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _worklistIcon(bill),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 18),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                        value: 'open', child: Text('Open')),
                                    if (!cancelled)
                                      PopupMenuItem(
                                        value: 'exclude',
                                        child: Text(bill.reportExcluded
                                            ? 'Include in reports'
                                            : 'Exclude from reports'),
                                      ),
                                    if (!cancelled)
                                      const PopupMenuItem(
                                        value: 'cancel',
                                        child: Text('Cancel Bill',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    if (canHardDelete(bill))
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete (recent only)',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                    if (bill.patientId != null && bill.patientId!.isNotEmpty)
                                      const PopupMenuItem(
                                        value: 'delete_patient',
                                        child: Text('Delete Patient',
                                            style: TextStyle(color: Colors.red)),
                                      ),
                                  ],
                                  onSelected: (v) async {
                                    if (v == 'open') _openDetail(bill);
                                    if (v == 'exclude') {
                                      await toggleReportExclusion(context, bill);
                                      _load();
                                    }
                                    if (v == 'cancel') {
                                      if (await cancelBillFlow(context, bill)) {
                                        _load();
                                      }
                                    }
                                    if (v == 'delete') {
                                      if (await deleteBillFlow(context, bill)) {
                                        _load();
                                      }
                                    }
                                    if (v == 'delete_patient') {
                                      if (await deletePatientFlow(context, bill)) {
                                        _load();
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            onTap: () => _openDetail(bill),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _worklistIcon(Bill bill) {
    if (bill.scanCompleted) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 18);
    }
    if (bill.worklistPushed) {
      return const Icon(Icons.wifi, color: Colors.blue, size: 18);
    }
    return const Icon(Icons.circle_outlined, color: Colors.grey, size: 18);
  }
}

class _BillDetailDialog extends StatelessWidget {
  final Bill bill;
  final ScanType? scanType;
  final ReferralDoctor? referralDoctor;
  final VoidCallback onViewReceipt;
  final VoidCallback onViewImages;
  final VoidCallback onMarkCompleted;

  const _BillDetailDialog({
    required this.bill,
    this.scanType,
    this.referralDoctor,
    required this.onViewReceipt,
    required this.onViewImages,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(bill.id),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _row('Patient', bill.patientName),
            _row('Scan', scanType?.name ?? 'N/A'),
            _row('Amount', formatCurrency(bill.finalAmount)),
            _row('Payment', bill.paymentMode),
            _row('Status', bill.status.toUpperCase()),
            _row('Worklist', bill.worklistPushed ? (bill.scanCompleted ? 'Completed' : 'In Progress') : 'Not pushed'),
            if (referralDoctor != null) _row('Referred By', 'Dr. ${referralDoctor!.name}'),
            _row('Date', formatDateTime(bill.createdAt)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!bill.scanCompleted)
          TextButton(
            onPressed: onMarkCompleted,
            child: const Text('Mark Completed'),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('View Images'),
          onPressed: onViewImages,
        ),
        FilledButton(
          onPressed: onViewReceipt,
          child: const Text('View Receipt'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

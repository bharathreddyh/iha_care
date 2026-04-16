import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../models/billing/referral_doctor.dart';
import '../../models/billing/scan_type.dart';
import '../../services/billing_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
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

  Future<void> _load() async {
    final bills = await context.read<BillingService>().getBills(
          searchTerm: _searchCtrl.text,
          statusFilter: _statusFilter,
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
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
                const SizedBox(width: 12),
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
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: bill.status == 'paid'
                                  ? Colors.green.shade100
                                  : Colors.orange.shade100,
                              child: Icon(
                                bill.status == 'paid' ? Icons.check : Icons.hourglass_empty,
                                color: bill.status == 'paid'
                                    ? Colors.green
                                    : Colors.orange,
                                size: 20,
                              ),
                            ),
                            title: Text(bill.patientName),
                            subtitle: Text('${bill.id} · ${formatDate(bill.createdAt)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatCurrency(bill.finalAmount),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                _worklistIcon(bill),
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
  final VoidCallback onMarkCompleted;

  const _BillDetailDialog({
    required this.bill,
    this.scanType,
    this.referralDoctor,
    required this.onViewReceipt,
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

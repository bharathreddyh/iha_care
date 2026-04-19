import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

class BillingDashboardScreen extends StatefulWidget {
  const BillingDashboardScreen({super.key});

  @override
  State<BillingDashboardScreen> createState() =>
      _BillingDashboardScreenState();
}

class _BillingDashboardScreenState extends State<BillingDashboardScreen> {
  DateTime _viewDate = DateTime.now();
  List<Bill> _bills = [];
  Map<String, ScanType> _scanTypes = {};
  Map<String, ReferralDoctor> _doctors = {};
  Map<String, dynamic> _stats = {};
  bool _loading = true;
  Timer? _refreshTimer;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_load);
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final service = context.read<BillingService>();
    final start = DateTime(_viewDate.year, _viewDate.month, _viewDate.day);
    final end = start.add(const Duration(days: 1));

    final results = await Future.wait([
      service.getBills(
        fromDate: start,
        toDate: end,
        searchTerm: _searchCtrl.text,
      ),
      service.getScanTypes(),
      service.getReferralDoctors(),
      service.getDashboardStats(),
    ]);

    if (!mounted) return;
    setState(() {
      _bills = results[0] as List<Bill>;
      _scanTypes = {
        for (final s in results[1] as List<ScanType>) s.id: s,
      };
      _doctors = {
        for (final d in results[2] as List<ReferralDoctor>) d.id: d,
      };
      _stats = results[3] as Map<String, dynamic>;
      _loading = false;
    });
  }

  void _shiftDate(int days) {
    setState(() => _viewDate = _viewDate.add(Duration(days: days)));
    _load();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _viewDate.year == now.year &&
        _viewDate.month == now.month &&
        _viewDate.day == now.day;
  }

  Future<void> _toggleStatus(Bill bill, String field) async {
    final service = context.read<BillingService>();
    switch (field) {
      case 'scan_completed':
        await service.markScanCompleted(bill.id);
      case 'report_created':
        await service.markReportCreated(bill.id, value: !bill.reportCreated);
      case 'dispatched':
        await service.markDispatched(bill.id, value: !bill.dispatched);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final todayRevenue =
        (_stats['todayRevenue'] as num? ?? 0).toDouble();
    final pendingScans = _stats['pendingScans'] as int? ?? 0;
    final monthCount = _stats['monthBillCount'] as int? ?? 0;

    final activeBills = _bills.where((b) => !b.isCancelled);
    final totalToday = activeBills.fold(0.0, (s, b) => s + b.finalAmount);
    final collectedToday = activeBills.fold(0.0, (s, b) => s + b.amountPaid);
    final pendingToday = activeBills.fold(0.0, (s, b) => s + b.pendingAmount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Worklist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Stats row ──────────────────────────────────────────
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _statChip(Icons.people, '${_bills.length} patients',
                    Colors.blue),
                const SizedBox(width: 12),
                _statChip(Icons.currency_rupee,
                    formatCurrency(totalToday), Colors.green),
                const SizedBox(width: 12),
                if (pendingToday > 0)
                  _statChip(Icons.pending_actions,
                      'Pending ${formatCurrency(pendingToday)}',
                      Colors.orange),
                if (pendingToday > 0) const SizedBox(width: 12),
                _statChip(Icons.calendar_month,
                    '$monthCount this month',
                    Theme.of(context).colorScheme.primary),
                const Spacer(),
                _statChip(Icons.hourglass_empty,
                    '$pendingScans in queue',
                    pendingScans > 0 ? Colors.orange : Colors.grey),
              ],
            ),
          ),

          // ── Filter bar ─────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shiftDate(-1),
                  tooltip: 'Previous day',
                ),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _viewDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setState(() => _viewDate = picked);
                      _load();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(context).colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                      color: _isToday
                          ? Theme.of(context)
                              .colorScheme
                              .primaryContainer
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _isToday
                              ? 'Today  ${DateFormat('dd MMM').format(_viewDate)}'
                              : DateFormat('EEE, dd MMM yyyy')
                                  .format(_viewDate),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!_isToday) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => _viewDate = DateTime.now());
                      _load();
                    },
                    child: const Text('Today'),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shiftDate(1),
                  tooltip: 'Next day',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search patient...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchCtrl.clear();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Status legend ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              children: [
                _legendItem(Icons.wifi, 'MWL', Colors.blue),
                _legendItem(Icons.image_outlined, 'Images', Colors.purple),
                _legendItem(Icons.description_outlined, 'Report',
                    Colors.teal),
                _legendItem(Icons.send_outlined, 'Dispatched',
                    Colors.green),
              ],
            ),
          ),

          // ── Patient list ───────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _bills.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outline),
                            const SizedBox(height: 8),
                            Text(
                              _isToday
                                  ? 'No patients today yet.'
                                  : 'No patients on ${DateFormat('dd MMM').format(_viewDate)}.',
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _bills.length,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemBuilder: (_, i) =>
                            _PatientRow(
                          bill: _bills[i],
                          scanType: _scanTypes[_bills[i].scanTypeId],
                          doctor: _doctors[_bills[i].referralDoctorId],
                          onToggle: _toggleStatus,
                          onReceipt: () => _openReceipt(_bills[i]),
                          onImages: () => _openImages(_bills[i]),
                          onPayment: () => _editPayment(_bills[i]),
                          onCancel: () async {
                            if (await cancelBillFlow(context, _bills[i])) _load();
                          },
                          onDelete: () async {
                            if (await deleteBillFlow(context, _bills[i])) _load();
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      );

  Widget _legendItem(IconData icon, String label, Color color) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline)),
          ],
        ),
      );

  Future<void> _openReceipt(Bill bill) async {
    final service = context.read<BillingService>();
    final scan = bill.scanTypeId != null
        ? await service.getScanType(bill.scanTypeId!)
        : null;
    final doc = bill.referralDoctorId != null
        ? await service.getReferralDoctor(bill.referralDoctorId!)
        : null;
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptPreviewScreen(
            bill: bill, scanType: scan, referralDoctor: doc),
      ),
    );
  }

  void _openImages(Bill bill) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PatientImagesScreen(bill: bill)));
  }

  Future<void> _editPayment(Bill bill) async {
    final ctrl =
        TextEditingController(text: bill.amountPaid.toStringAsFixed(0));
    final confirmed = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Payment — ${bill.patientName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: ${formatCurrency(bill.finalAmount)}'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                  labelText: 'Amount Paid', prefixText: '₹ '),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, double.tryParse(ctrl.text) ?? bill.amountPaid),
              child: const Text('Save')),
        ],
      ),
    );
    if (confirmed != null && mounted) {
      await context
          .read<BillingService>()
          .updateAmountPaid(bill.id, confirmed, bill.finalAmount);
      _load();
    }
  }
}

// ── Patient row widget ────────────────────────────────────────────────────────

class _PatientRow extends StatelessWidget {
  final Bill bill;
  final ScanType? scanType;
  final ReferralDoctor? doctor;
  final Future<void> Function(Bill, String) onToggle;
  final VoidCallback onReceipt;
  final VoidCallback onImages;
  final VoidCallback onPayment;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  const _PatientRow({
    required this.bill,
    required this.scanType,
    required this.doctor,
    required this.onToggle,
    required this.onReceipt,
    required this.onImages,
    required this.onPayment,
    required this.onCancel,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = () {
      try {
        return DateFormat('hh:mm a').format(DateTime.parse(bill.createdAt));
      } catch (_) {
        return '';
      }
    }();

    final hasPending = !bill.isFullyPaid;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: bill.isCancelled
          ? theme.colorScheme.errorContainer.withValues(alpha: 0.25)
          : bill.dispatched
              ? theme.colorScheme.surfaceContainerLowest
              : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Time
            SizedBox(
              width: 60,
              child: Text(time,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),

            // Patient info
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bill.patientName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      decoration: (bill.dispatched || bill.isCancelled)
                          ? TextDecoration.lineThrough
                          : null,
                      color: bill.isCancelled
                          ? theme.colorScheme.outline
                          : null,
                    ),
                  ),
                  if (bill.isCancelled)
                    Text(
                      'Cancelled${bill.cancelReason != null ? ' — ${bill.cancelReason}' : ''}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  Row(
                    children: [
                      if (bill.patientId != null)
                        Text('${bill.patientId}  ',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline)),
                      if (bill.patientSex != null)
                        Text(bill.patientSex!,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline)),
                    ],
                  ),
                ],
              ),
            ),

            // Scan type
            Expanded(
              flex: 2,
              child: Text(
                scanType?.name ?? '—',
                style: theme.textTheme.bodySmall,
              ),
            ),

            // Payment
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(bill.finalAmount),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (hasPending)
                    GestureDetector(
                      onTap: onPayment,
                      child: Text(
                        'Pending ${formatCurrency(bill.pendingAmount)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.orange,
                            fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    Text(
                      bill.paymentMode,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Ref doctor
            SizedBox(
              width: 90,
              child: Text(
                doctor != null ? 'Dr. ${doctor!.name.split(' ').first}' : '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(width: 4),

            // Status toggles
            _statusBtn(
              Icons.wifi,
              bill.worklistPushed,
              Colors.blue,
              null, // MWL is auto-set, not manually toggled
              'MWL pushed',
            ),
            _statusBtn(
              Icons.image_outlined,
              bill.scanCompleted,
              Colors.purple,
              bill.isCancelled ? null : () => onToggle(bill, 'scan_completed'),
              'Images received',
            ),
            _statusBtn(
              Icons.description_outlined,
              bill.reportCreated,
              Colors.teal,
              bill.isCancelled ? null : () => onToggle(bill, 'report_created'),
              'Report done',
            ),
            _statusBtn(
              Icons.send_outlined,
              bill.dispatched,
              Colors.green,
              bill.isCancelled ? null : () => onToggle(bill, 'dispatched'),
              'Dispatched',
            ),

            // Action menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'receipt', child: Text('View Receipt')),
                const PopupMenuItem(
                    value: 'images', child: Text('View Images')),
                if (!bill.isCancelled)
                  const PopupMenuItem(
                      value: 'payment', child: Text('Update Payment')),
                if (!bill.isCancelled) const PopupMenuDivider(),
                if (!bill.isCancelled)
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
              ],
              onSelected: (v) {
                if (v == 'receipt') onReceipt();
                if (v == 'images') onImages();
                if (v == 'payment') onPayment();
                if (v == 'cancel') onCancel();
                if (v == 'delete') onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBtn(IconData icon, bool active, Color color,
      VoidCallback? onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            active ? icon : Icons.check_box_outline_blank,
            size: 18,
            color: active ? color : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }
}

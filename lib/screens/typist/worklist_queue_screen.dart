import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../models/billing/scan_type.dart';
import '../../models/billing/referral_doctor.dart';
import '../../services/billing_service.dart';
import '../../services/biometry_service.dart';
import '../../services/mwl_service.dart';
import '../../utils/date_formatter.dart';
import '../billing/patient_images_screen.dart';
import 'biometry_screen.dart';

class WorklistQueueScreen extends StatefulWidget {
  const WorklistQueueScreen({super.key});

  @override
  State<WorklistQueueScreen> createState() => _WorklistQueueScreenState();
}

class _WorklistQueueScreenState extends State<WorklistQueueScreen> {
  List<Bill> _bills = [];
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Auto-refresh every 30 s so new bills from billing PC appear
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final bills = await context.read<BillingService>().getBills(
          statusFilter: 'All',
        );
    // Show active (non-cancelled, non-completed) bills oldest-first
    final queue = bills
        .where((b) => !b.isCancelled && !b.scanCompleted)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (mounted) setState(() { _bills = queue; _loading = false; });
  }

  Future<void> _pushToMwl(Bill bill) async {
    final service = context.read<BillingService>();
    final mwl = context.read<MwlService>();

    final scan = bill.scanTypeId != null
        ? await service.getScanType(bill.scanTypeId!)
        : null;
    final doc = bill.referralDoctorId != null
        ? await service.getReferralDoctor(bill.referralDoctorId!)
        : null;

    final result = await mwl.pushToWorklist(
      bill: bill,
      scanType: scan,
      referralDoctor: doc,
    );

    if (!mounted) return;
    if (result.success) {
      await service.markWorklistPushed(bill.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${bill.patientName} pushed to worklist.')),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MWL push failed: ${result.error}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _markComplete(Bill bill) async {
    await context.read<BillingService>().markScanCompleted(bill.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${bill.patientName} marked complete.')),
      );
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worklist Queue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _bills.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 48, color: Colors.green),
                      SizedBox(height: 12),
                      Text('Queue empty — all scans complete.'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _bills.length,
                  itemBuilder: (_, i) => _QueueCard(
                    bill: _bills[i],
                    onPush: () => _pushToMwl(_bills[i]),
                    onComplete: () => _markComplete(_bills[i]),
                    onViewImages: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PatientImagesScreen(bill: _bills[i]),
                      ),
                    ),
                    onViewBiometry: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            BiometryScreen(bill: _bills[i]),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _QueueCard extends StatefulWidget {
  final Bill bill;
  final VoidCallback onPush;
  final VoidCallback onComplete;
  final VoidCallback onViewImages;
  final VoidCallback onViewBiometry;

  const _QueueCard({
    required this.bill,
    required this.onPush,
    required this.onComplete,
    required this.onViewImages,
    required this.onViewBiometry,
  });

  @override
  State<_QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends State<_QueueCard> {
  bool _hasImages = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (widget.bill.worklistPushed && widget.bill.accessionNumber != null) {
      _checkImages();
    }
  }

  Future<void> _checkImages() async {
    if (!mounted) return;
    setState(() => _checking = true);
    final has = await context
        .read<BiometryService>()
        .isStudyInOrthanc(widget.bill.accessionNumber!);
    if (mounted) setState(() { _hasImages = has; _checking = false; });
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final statusColor = bill.worklistPushed
        ? (_hasImages ? Colors.green : Colors.blue)
        : Colors.orange;
    final statusLabel = bill.worklistPushed
        ? (_hasImages ? 'Images received' : 'In worklist')
        : 'Waiting — not pushed';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bill.patientName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      if (bill.patientId != null && bill.patientId!.isNotEmpty)
                        Text(bill.patientId!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _checking
                          ? const SizedBox(
                              width: 10,
                              height: 10,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5))
                          : Icon(
                              _hasImages
                                  ? Icons.check_circle
                                  : bill.worklistPushed
                                      ? Icons.wifi
                                      : Icons.hourglass_empty,
                              size: 12,
                              color: statusColor,
                            ),
                      const SizedBox(width: 4),
                      Text(statusLabel,
                          style: TextStyle(
                              fontSize: 11, color: statusColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(
                icon: Icons.document_scanner_outlined,
                label: bill.scanTypeId ?? 'Unknown scan'),
            _InfoRow(
                icon: Icons.access_time_outlined,
                label: formatDateTime(bill.createdAt)),
            if (bill.accessionNumber != null)
              _InfoRow(
                  icon: Icons.tag,
                  label: bill.accessionNumber!),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!bill.worklistPushed)
                  FilledButton.icon(
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text('Push to MWL'),
                    onPressed: widget.onPush,
                  ),
                if (bill.worklistPushed && _hasImages) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('View Images'),
                    onPressed: widget.onViewImages,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.analytics_outlined, size: 16),
                    label: const Text('Biometry'),
                    onPressed: widget.onViewBiometry,
                  ),
                ],
                if (bill.worklistPushed)
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Mark Complete'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.green),
                    onPressed: widget.onComplete,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Icon(icon, size: 14,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      );
}

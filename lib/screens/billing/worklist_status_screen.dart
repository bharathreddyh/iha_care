import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../models/billing/scan_type.dart';
import '../../services/billing_service.dart';
import '../../services/orthanc_service.dart';
import '../../utils/date_formatter.dart';

class WorklistStatusScreen extends StatefulWidget {
  const WorklistStatusScreen({super.key});

  @override
  State<WorklistStatusScreen> createState() => _WorklistStatusScreenState();
}

class _WorklistStatusScreenState extends State<WorklistStatusScreen> {
  List<Bill> _bills = [];
  Map<String, ScanType?> _scanTypes = {};
  bool _loading = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = context.read<BillingService>();
    final bills = await service.getWorklistBills();
    final scanMap = <String, ScanType?>{};
    for (final b in bills) {
      if (b.scanTypeId != null && !scanMap.containsKey(b.scanTypeId)) {
        scanMap[b.scanTypeId!] = await service.getScanType(b.scanTypeId!);
      }
    }
    if (mounted) {
      setState(() {
        _bills = bills;
        _scanTypes = scanMap;
        _loading = false;
      });
    }
  }

  Future<void> _checkAllCompletion() async {
    setState(() => _checking = true);
    final billing = context.read<BillingService>();
    final orthanc = context.read<OrthancService>();

    final pending = _bills.where((b) => !b.scanCompleted).toList();
    for (final bill in pending) {
      final accession = bill.accessionNumber ?? bill.id;
      final completed = await orthanc.isStudyCompleted(accession);
      if (completed) {
        await billing.markScanCompleted(bill.id);
      }
    }

    await _load();
    if (mounted) setState(() => _checking = false);
  }

  Color _statusColor(Bill bill) {
    if (bill.scanCompleted) return Colors.green;
    if (bill.worklistPushed) return Colors.blue;
    return Colors.orange;
  }

  String _statusLabel(Bill bill) {
    if (bill.scanCompleted) return 'Completed';
    if (bill.worklistPushed) return 'In Progress';
    return 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worklist Status'),
        actions: [
          if (_checking)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Check Orthanc for completions',
              onPressed: _checkAllCompletion,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
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
                      Icon(Icons.queue_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No worklist entries yet.'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _bills.length,
                    itemBuilder: (_, i) {
                      final bill = _bills[i];
                      final scan = _scanTypes[bill.scanTypeId];
                      final color = _statusColor(bill);

                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withAlpha(30),
                            child: Icon(
                              bill.scanCompleted
                                  ? Icons.check_circle
                                  : Icons.hourglass_empty,
                              color: color,
                            ),
                          ),
                          title: Text(bill.patientName),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${bill.id} · ${scan?.name ?? 'N/A'}'),
                              Text(formatDateTime(bill.createdAt),
                                  style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                          trailing: Chip(
                            label: Text(
                              _statusLabel(bill),
                              style: TextStyle(color: color, fontSize: 12),
                            ),
                            side: BorderSide(color: color),
                            backgroundColor: color.withAlpha(20),
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

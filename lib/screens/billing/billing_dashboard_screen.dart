import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../models/billing/scan_type.dart';
import '../../services/billing_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';
import 'receipt_preview_screen.dart';

class BillingDashboardScreen extends StatefulWidget {
  const BillingDashboardScreen({super.key});

  @override
  State<BillingDashboardScreen> createState() => _BillingDashboardScreenState();
}

class _BillingDashboardScreenState extends State<BillingDashboardScreen> {
  Map<String, dynamic> _stats = {
    'todayRevenue': 0.0,
    'pendingScans': 0,
    'monthBillCount': 0,
  };
  List<Bill> _recentBills = [];
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final service = context.read<BillingService>();
    final stats = await service.getDashboardStats();
    final recent = await service.getBills();
    final bills = recent.take(10).toList();
    if (mounted) {
      setState(() {
        _stats = stats;
        _recentBills = bills;
        _loading = false;
      });
    }
  }

  int get _pendingScans => _stats['pendingScans'] as int? ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IHA Care — Billing Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Stats row
                  LayoutBuilder(builder: (_, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    return Flex(
                      direction: isWide ? Axis.horizontal : Axis.vertical,
                      children: [
                        Flexible(
                          fit: isWide ? FlexFit.tight : FlexFit.loose,
                          child: _StatCard(
                            icon: Icons.currency_rupee,
                            label: "Today's Revenue",
                            value: formatCurrency(
                                (_stats['todayRevenue'] as num? ?? 0).toDouble()),
                            color: Colors.green,
                          ),
                        ),
                        SizedBox(width: isWide ? 12 : 0, height: isWide ? 0 : 12),
                        Flexible(
                          fit: isWide ? FlexFit.tight : FlexFit.loose,
                          child: _StatCard(
                            icon: Icons.hourglass_empty,
                            label: 'Pending Scans',
                            value: _pendingScans.toString(),
                            color: _pendingScans > 0 ? Colors.orange : Colors.grey,
                          ),
                        ),
                        SizedBox(width: isWide ? 12 : 0, height: isWide ? 0 : 12),
                        Flexible(
                          fit: isWide ? FlexFit.tight : FlexFit.loose,
                          child: _StatCard(
                            icon: Icons.receipt_long,
                            label: 'Bills This Month',
                            value: (_stats['monthBillCount'] as int? ?? 0).toString(),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 16),

                  // Worklist status card
                  _WorklistStatusCard(
                    pendingCount: _pendingScans,
                    onTap: () {},
                  ),

                  const SizedBox(height: 16),

                  // Recent bills
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Bills',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_recentBills.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No bills yet. Create the first one!'),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: _recentBills.map((bill) {
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: bill.scanCompleted
                                  ? Colors.green.shade100
                                  : bill.worklistPushed
                                      ? Colors.blue.shade100
                                      : Colors.grey.shade100,
                              child: Icon(
                                bill.scanCompleted
                                    ? Icons.check
                                    : bill.worklistPushed
                                        ? Icons.wifi
                                        : Icons.receipt,
                                size: 16,
                                color: bill.scanCompleted
                                    ? Colors.green
                                    : bill.worklistPushed
                                        ? Colors.blue
                                        : Colors.grey,
                              ),
                            ),
                            title: Text(bill.patientName,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                '${bill.id} · ${formatDate(bill.createdAt)}',
                                style: const TextStyle(fontSize: 11)),
                            trailing: Text(
                              formatCurrency(bill.finalAmount),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onTap: () => _openReceipt(bill),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _openReceipt(Bill bill) async {
    final service = context.read<BillingService>();
    final scan = bill.scanTypeId != null ? await service.getScanType(bill.scanTypeId!) : null;
    final doc = bill.referralDoctorId != null
        ? await service.getReferralDoctor(bill.referralDoctorId!)
        : null;
    if (!mounted) return;
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
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withAlpha(30),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
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
}

class _WorklistStatusCard extends StatelessWidget {
  final int pendingCount;
  final VoidCallback onTap;

  const _WorklistStatusCard({required this.pendingCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = pendingCount == 0
        ? Colors.green
        : pendingCount < 5
            ? Colors.orange
            : Colors.red;

    return Card(
      color: color.withAlpha(20),
      child: ListTile(
        leading: Icon(Icons.queue, color: color),
        title: Text(
          'MWL Queue',
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        subtitle: Text(
          pendingCount == 0
              ? 'All scans completed'
              : '$pendingCount scan(s) in progress on worklist',
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: color),
        onTap: onTap,
      ),
    );
  }
}

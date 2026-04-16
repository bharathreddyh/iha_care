import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/scan_type.dart';
import '../../services/billing_service.dart';
import '../../utils/currency_formatter.dart';

class ScanTypesScreen extends StatefulWidget {
  const ScanTypesScreen({super.key});

  @override
  State<ScanTypesScreen> createState() => _ScanTypesScreenState();
}

class _ScanTypesScreenState extends State<ScanTypesScreen> {
  List<ScanType> _scanTypes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = context.read<BillingService>();
    final types = await service.getScanTypes();
    if (mounted) setState(() { _scanTypes = types; _loading = false; });
  }

  Future<void> _editPrice(ScanType scan) async {
    final ctrl = TextEditingController(text: scan.price.toStringAsFixed(0));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(scan.name),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Price (₹)',
            prefixText: '₹ ',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newPrice = double.tryParse(ctrl.text) ?? scan.price;
      final updated = scan.copyWith(price: newPrice);
      await context.read<BillingService>().updateScanType(updated);
      _load();
    }
  }

  Future<void> _toggleActive(ScanType scan) async {
    final updated = scan.copyWith(isActive: !scan.isActive);
    await context.read<BillingService>().updateScanType(updated);
    _load();
  }

  Map<String, List<ScanType>> get _grouped {
    final map = <String, List<ScanType>>{};
    for (final s in _scanTypes) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final grouped = _grouped;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Types'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: grouped.entries.map((entry) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  entry.key,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Card(
                child: Column(
                  children: entry.value.map((scan) {
                    return ListTile(
                      title: Text(
                        scan.name,
                        style: TextStyle(
                          color: scan.isActive ? null : Colors.grey,
                          decoration: scan.isActive ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(formatCurrency(scan.price)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: scan.isActive,
                            onChanged: (_) => _toggleActive(scan),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editPrice(scan),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          );
        }).toList(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/inventory/inventory_item.dart';
import '../../models/inventory/inventory_scan_usage.dart';
import '../../models/inventory/inventory_transaction.dart';
import '../../models/billing/scan_type.dart';
import '../../services/billing_service.dart';
import '../../services/inventory_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/date_formatter.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem> _items = [];
  bool _loading = true;
  bool _lowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = _lowStockOnly
        ? await context.read<InventoryService>().getLowStockItems()
        : await context.read<InventoryService>().getItems();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _openItemForm([InventoryItem? existing]) async {
    await showDialog(
      context: context,
      builder: (_) => _ItemFormDialog(
        existing: existing,
        onSave: (item) async {
          if (existing == null) {
            await context.read<InventoryService>().saveItem(item);
          } else {
            await context.read<InventoryService>().updateItem(item);
          }
          _load();
        },
      ),
    );
  }

  Future<void> _openDetail(InventoryItem item) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _ItemDetailDialog(item: item, onRefresh: _load),
    );
  }

  Future<void> _openScanUsageConfig() async {
    final scanTypes = await context.read<BillingService>().getScanTypes();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _ScanUsageConfigDialog(
        scanTypes: scanTypes,
        items: _items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lowCount = _items.where((i) => i.isLowStock).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          if (lowCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                label: Text('$lowCount low stock',
                    style: const TextStyle(fontSize: 11)),
                backgroundColor:
                    Colors.orange.withAlpha(40),
                side: const BorderSide(color: Colors.orange),
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            icon: Icon(_lowStockOnly
                ? Icons.filter_alt
                : Icons.filter_alt_outlined),
            tooltip: _lowStockOnly ? 'Show all' : 'Show low stock only',
            onPressed: () {
              setState(() => _lowStockOnly = !_lowStockOnly);
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune_outlined),
            tooltip: 'Configure per-scan usage',
            onPressed: _openScanUsageConfig,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openItemForm(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(_lowStockOnly
                          ? 'No low-stock items.'
                          : 'No items yet. Tap + to add.'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                  itemCount: _items.length,
                  itemBuilder: (_, i) => _ItemCard(
                    item: _items[i],
                    onTap: () => _openDetail(_items[i]),
                    onEdit: () => _openItemForm(_items[i]),
                    onAddStock: () => _showAddStockDialog(_items[i]),
                  ),
                ),
    );
  }

  Future<void> _showAddStockDialog(InventoryItem item) async {
    final qtyCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Stock — ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Current: ${item.currentQuantity.toStringAsFixed(1)} ${item.unit}',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              decoration: InputDecoration(
                  labelText: 'Quantity received *',
                  suffixText: item.unit),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: costCtrl,
              decoration: const InputDecoration(
                  labelText: 'Cost (optional)', prefixText: '₹ '),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text);
              if (qty == null || qty <= 0) return;
              await context.read<InventoryService>().addPurchase(
                    item.id,
                    qty,
                    double.tryParse(costCtrl.text),
                    notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ── Item card ─────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onAddStock;

  const _ItemCard({
    required this.item,
    required this.onTap,
    required this.onEdit,
    required this.onAddStock,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color stockColor;
    if (item.isOutOfStock) {
      stockColor = Colors.red;
    } else if (item.isLowStock) {
      stockColor = Colors.orange;
    } else {
      stockColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      color: item.isLowStock
          ? Colors.orange.withAlpha(15)
          : null,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: stockColor.withAlpha(30),
          child: Icon(Icons.inventory_2_outlined, color: stockColor, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (item.isLowStock)
              const Chip(
                label: Text('Low', style: TextStyle(fontSize: 10)),
                backgroundColor: Colors.orange,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text:
                        '${item.currentQuantity.toStringAsFixed(item.currentQuantity.truncateToDouble() == item.currentQuantity ? 0 : 1)} ${item.unit}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: stockColor),
                  ),
                  if (item.minQuantity > 0)
                    TextSpan(
                      text:
                          '  (min ${item.minQuantity.toStringAsFixed(0)} ${item.unit})',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                ],
              ),
            ),
            if (item.pricePerUnit != null)
              Text(formatCurrency(item.pricePerUnit!),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
        isThreeLine: item.pricePerUnit != null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Add stock',
              onPressed: onAddStock,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit item',
              onPressed: onEdit,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Item form dialog ──────────────────────────────────────────────────────────

class _ItemFormDialog extends StatefulWidget {
  final InventoryItem? existing;
  final Future<void> Function(InventoryItem) onSave;

  const _ItemFormDialog({this.existing, required this.onSave});

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _unit;
  late final TextEditingController _qty;
  late final TextEditingController _minQty;
  late final TextEditingController _price;
  bool _saving = false;

  static const _units = ['pcs', 'bottle', 'box', 'roll', 'ml', 'L', 'g', 'kg'];

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _name = TextEditingController(text: d?.name ?? '');
    _unit = TextEditingController(text: d?.unit ?? 'pcs');
    _qty = TextEditingController(
        text: d?.currentQuantity != null
            ? d!.currentQuantity.toStringAsFixed(0)
            : '');
    _minQty = TextEditingController(
        text: d?.minQuantity != null && d!.minQuantity > 0
            ? d.minQuantity.toStringAsFixed(0)
            : '');
    _price = TextEditingController(
        text: d?.pricePerUnit != null
            ? d!.pricePerUnit!.toStringAsFixed(0)
            : '');
  }

  @override
  void dispose() {
    for (final c in [_name, _unit, _qty, _minQty, _price]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final item = InventoryItem(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
      currentQuantity: double.tryParse(_qty.text) ?? 0,
      minQuantity: double.tryParse(_minQty.text) ?? 0,
      pricePerUnit: double.tryParse(_price.text),
    );
    await widget.onSave(item);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Item' : 'Edit Item'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Item Name *'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration:
                          const InputDecoration(labelText: 'Unit (e.g. bottle)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 4,
                    children: _units
                        .map((u) => ActionChip(
                              label: Text(u, style: const TextStyle(fontSize: 11)),
                              onPressed: () =>
                                  setState(() => _unit.text = u),
                              visualDensity: VisualDensity.compact,
                            ))
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _qty,
                      decoration: const InputDecoration(
                          labelText: 'Current Stock'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _minQty,
                      decoration: const InputDecoration(
                          labelText: 'Low Stock Alert At'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(
                    labelText: 'Price per unit (optional)',
                    prefixText: '₹ '),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

// ── Item detail + transaction log dialog ──────────────────────────────────────

class _ItemDetailDialog extends StatefulWidget {
  final InventoryItem item;
  final VoidCallback onRefresh;

  const _ItemDetailDialog({required this.item, required this.onRefresh});

  @override
  State<_ItemDetailDialog> createState() => _ItemDetailDialogState();
}

class _ItemDetailDialogState extends State<_ItemDetailDialog> {
  List<InventoryTransaction> _txns = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTxns();
  }

  Future<void> _loadTxns() async {
    final txns = await context
        .read<InventoryService>()
        .getTransactions(widget.item.id);
    if (mounted) setState(() { _txns = txns; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item.name),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Current stock: '),
                Text(
                  '${widget.item.currentQuantity.toStringAsFixed(1)} ${widget.item.unit}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.item.isLowStock
                        ? Colors.orange
                        : Colors.green,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            const Text('Transaction History',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _txns.isEmpty
                      ? const Center(child: Text('No transactions yet.'))
                      : ListView.builder(
                          itemCount: _txns.length,
                          itemBuilder: (_, i) {
                            final t = _txns[i];
                            final isIn = t.quantity > 0;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                isIn
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: isIn ? Colors.green : Colors.red,
                                size: 18,
                              ),
                              title: Text(
                                '${isIn ? '+' : ''}${t.quantity.toStringAsFixed(1)} ${widget.item.unit}',
                                style: TextStyle(
                                    color: isIn ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${t.type.toUpperCase()}'
                                '${t.billId != null ? ' · ${t.billId}' : ''}'
                                '${t.notes != null ? ' · ${t.notes}' : ''}'
                                '${t.cost != null ? ' · ${formatCurrency(t.cost!)}' : ''}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Text(
                                formatDate(t.createdAt),
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}

// ── Scan usage config dialog ──────────────────────────────────────────────────

class _ScanUsageConfigDialog extends StatefulWidget {
  final List<ScanType> scanTypes;
  final List<InventoryItem> items;

  const _ScanUsageConfigDialog(
      {required this.scanTypes, required this.items});

  @override
  State<_ScanUsageConfigDialog> createState() =>
      _ScanUsageConfigDialogState();
}

class _ScanUsageConfigDialogState extends State<_ScanUsageConfigDialog> {
  ScanType? _selectedScan;
  List<InventoryScanUsage> _usages = [];
  Map<String, TextEditingController> _controllers = {};
  bool _loading = false;

  Future<void> _loadUsage(ScanType scan) async {
    setState(() => _loading = true);
    final usages = await context.read<InventoryService>().getScanUsage(scan.id);
    final map = {for (final u in usages) u.itemId: u};
    _controllers = {
      for (final item in widget.items)
        item.id: TextEditingController(
          text: map[item.id] != null
              ? map[item.id]!.quantity.toStringAsFixed(1)
              : '',
        ),
    };
    setState(() {
      _selectedScan = scan;
      _usages = usages;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_selectedScan == null) return;
    final usages = widget.items.map((item) {
      final qty = double.tryParse(_controllers[item.id]?.text ?? '') ?? 0;
      return InventoryScanUsage(
        id: _usages
                .where((u) => u.itemId == item.id)
                .firstOrNull
                ?.id ??
            const Uuid().v4(),
        scanTypeId: _selectedScan!.id,
        itemId: item.id,
        quantity: qty,
      );
    }).toList();
    await context
        .read<InventoryService>()
        .saveScanUsage(_selectedScan!.id, usages);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Usage configuration saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>[];
    final byCategory = <String, List<ScanType>>{};
    for (final s in widget.scanTypes) {
      byCategory.putIfAbsent(s.category, () { categories.add(s.category); return []; }).add(s);
    }

    return AlertDialog(
      title: const Text('Configure Usage per Scan'),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Row(
          children: [
            // Scan type picker
            SizedBox(
              width: 200,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select scan type:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView(
                      children: categories.expand((cat) => [
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 2),
                          child: Text(cat,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold)),
                        ),
                        ...byCategory[cat]!.map((s) => ListTile(
                              dense: true,
                              title: Text(s.name,
                                  style: const TextStyle(fontSize: 13)),
                              selected: _selectedScan?.id == s.id,
                              selectedTileColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              onTap: () => _loadUsage(s),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            )),
                      ]).toList(),
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(),
            // Item quantity config
            Expanded(
              child: _selectedScan == null
                  ? const Center(
                      child: Text('Select a scan type to configure.',
                          textAlign: TextAlign.center))
                  : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Items used per ${_selectedScan!.name}:',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            const Text('Leave blank or 0 = not used',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView(
                                children: widget.items.map((item) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                              child: Text(item.name,
                                                  style: const TextStyle(
                                                      fontSize: 13))),
                                          SizedBox(
                                            width: 90,
                                            child: TextField(
                                              controller:
                                                  _controllers[item.id],
                                              decoration: InputDecoration(
                                                suffixText: item.unit,
                                                hintText: '0',
                                                isDense: true,
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )).toList(),
                              ),
                            ),
                            FilledButton(
                              onPressed: _save,
                              child: const Text('Save Configuration'),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}

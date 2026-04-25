import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

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

  static const _categories = ['OB-GYN', 'General', 'Small Parts', 'MSK'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final types = await context.read<BillingService>().getScanTypes();
    if (mounted) setState(() { _scanTypes = types; _loading = false; });
  }

  Future<void> _openForm([ScanType? existing]) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ScanTypeForm(
        existing: existing,
        categories: _categories,
        onSave: (scan) async {
          final service = context.read<BillingService>();
          if (existing == null) {
            await service.saveScanType(scan);
          } else {
            await service.updateScanType(scan);
          }
          _load();
        },
      ),
    );
  }

  Future<void> _toggleActive(ScanType scan) async {
    await context.read<BillingService>().updateScanType(
          scan.copyWith(isActive: !scan.isActive));
    _load();
  }

  Future<void> _delete(ScanType scan) async {
    final service = context.read<BillingService>();
    final refs = await service.rawBillCountForScanType(scan.id);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${scan.name}"?'),
        content: Text(
          refs == 0
              ? 'This permanently removes the scan type from the database.'
              : 'This scan type appears in $refs bill${refs == 1 ? '' : 's'}. '
                'It will be permanently deleted and those bills will show '
                '"Unknown" for scan type.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await service.deleteScanType(scan.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${scan.name}" deleted.')),
      );
    }
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New Scan'),
      ),
      body: _scanTypes.isEmpty
          ? const Center(child: Text('No scan types. Tap + to add.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
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
                                decoration: scan.isActive
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            subtitle: Text('${formatCurrency(scan.price)}  ·  ${scan.modality}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: scan.isActive,
                                  onChanged: (_) => _toggleActive(scan),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _openForm(scan),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  tooltip: 'Delete',
                                  onPressed: () => _delete(scan),
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

class _ScanTypeForm extends StatefulWidget {
  final ScanType? existing;
  final List<String> categories;
  final Future<void> Function(ScanType) onSave;

  const _ScanTypeForm({
    this.existing,
    required this.categories,
    required this.onSave,
  });

  @override
  State<_ScanTypeForm> createState() => _ScanTypeFormState();
}

class _ScanTypeFormState extends State<_ScanTypeForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late String _category;
  late String _modality;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _price = TextEditingController(text: s?.price.toStringAsFixed(0) ?? '');
    _category = s?.category ?? widget.categories.first;
    _modality = s?.modality ?? 'US';
    _isActive = s?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final scan = ScanType(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      price: double.tryParse(_price.text) ?? 0,
      category: _category,
      modality: _modality,
      isActive: _isActive,
    );
    await widget.onSave(scan);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null ? 'Add Scan Type' : 'Edit Scan Type',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Scan Name *'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(
                  labelText: 'Price (₹) *',
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if ((double.tryParse(v) ?? -1) < 0) return 'Enter valid price';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category *'),
                items: widget.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 16),
              Text('Modality', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'US',  label: Text('USG')),
                  ButtonSegment(value: 'CT',  label: Text('CT')),
                  ButtonSegment(value: 'MRI', label: Text('MRI')),
                  ButtonSegment(value: 'XR',  label: Text('X-Ray')),
                ],
                selected: {_modality},
                onSelectionChanged: (s) =>
                    setState(() => _modality = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
                title: const Text('Active'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.existing == null ? 'Add Scan Type' : 'Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

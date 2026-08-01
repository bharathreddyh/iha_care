import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../models/billing/referral_doctor.dart';
import '../../models/billing/scan_type.dart';
import '../../services/app_settings_service.dart';
import '../../services/billing_service.dart';
import '../../services/inventory_service.dart';
import '../../utils/currency_formatter.dart';
import 'receipt_preview_screen.dart';

class NewBillScreen extends StatefulWidget {
  const NewBillScreen({super.key});

  @override
  State<NewBillScreen> createState() => NewBillScreenState();
}

class NewBillScreenState extends State<NewBillScreen> {
  final _formKey = GlobalKey<FormState>();

  // Patient controllers
  final _patientName = TextEditingController();
  final _patientId = TextEditingController();
  final _patientAge = TextEditingController();
  final _patientPhone = TextEditingController();
  String _patientSex = 'F';

  // Scan / billing
  ScanType? _selectedScan;
  ReferralDoctor? _selectedDoctor;
  final _price = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _amountPaid = TextEditingController();
  String _paymentMode = 'Cash';
  final _notes = TextEditingController();

  List<ScanType> _scanTypes = [];
  List<ReferralDoctor> _doctors = [];
  bool _loading = true;
  bool _saving = false;
  int _autocompleteResetKey = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _price.addListener(() {
      setState(() {});
      _amountPaid.text = _finalAmount.toStringAsFixed(0);
    });
    _discount.addListener(() {
      setState(() {});
      _amountPaid.text = _finalAmount.toStringAsFixed(0);
    });
  }

  Future<void> _loadData() async {
    final service = context.read<BillingService>();
    final scans = await service.getScanTypes(activeOnly: true);
    final docs = await service.getReferralDoctors(activeOnly: true);
    final patientId = await service.generatePatientId();
    if (mounted) {
      setState(() {
        _scanTypes = scans;
        _doctors = docs;
        _loading = false;
      });
      if (_patientId.text.isEmpty) _patientId.text = patientId;
    }
  }

  /// Public hook so the navigation shell can refresh lists when this tab
  /// becomes visible (e.g. after adding a new referral doctor).
  Future<void> refresh() => _loadData();

  @override
  void dispose() {
    _patientName.dispose();
    _patientId.dispose();
    _patientAge.dispose();
    _patientPhone.dispose();
    _price.dispose();
    _discount.dispose();
    _amountPaid.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _scanFee => double.tryParse(_price.text) ?? _selectedScan?.price ?? 0;
  double get _discountAmt => double.tryParse(_discount.text) ?? 0;
  double get _finalAmount => (_scanFee - _discountAmt).clamp(0, double.infinity);

  /// Approximates a DICOM birth date (YYYYMMDD) from an age in years so the
  /// modality worklist still receives a PatientBirthDate.
  String? _ageToDicomDob(int? age) {
    if (age == null || age < 0 || age > 130) return null;
    final now = DateTime.now();
    final y = now.year - age;
    return '${y.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedScan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a scan type')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final billingService = context.read<BillingService>();

      final draftBill = Bill(
        id: '',
        patientName: _patientName.text.trim(),
        patientId: _patientId.text.trim().isEmpty ? null : _patientId.text.trim(),
        patientAge: int.tryParse(_patientAge.text.trim()),
        patientDob: _ageToDicomDob(int.tryParse(_patientAge.text.trim())),
        patientSex: _patientSex,
        patientPhone: _patientPhone.text.trim().isEmpty ? null : _patientPhone.text.trim(),
        scanTypeId: _selectedScan!.id,
        referralDoctorId: _selectedDoctor?.id,
        scanFee: _scanFee,
        discount: _discountAmt,
        finalAmount: _finalAmount,
        amountPaid: double.tryParse(_amountPaid.text) ?? _finalAmount,
        paymentMode: _paymentMode,
        status: (double.tryParse(_amountPaid.text) ?? _finalAmount) >= _finalAmount
            ? 'paid'
            : 'pending',
        createdAt: DateTime.now().toIso8601String(),
      );

      final savedBill = await billingService.createBill(draftBill);

      // Auto-deduct inventory for this scan type (best-effort)
      if (savedBill.scanTypeId != null) {
        try {
          await context
              .read<InventoryService>()
              .deductForBill(savedBill.id, savedBill.scanTypeId!);
        } catch (_) {}
      }

      // MWL push is handled by the typist workstation — bill is saved only.
      if (mounted) {
        final scanSnapshot = _selectedScan;
        final doctorSnapshot = _selectedDoctor;
        _resetForm();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptPreviewScreen(
              bill: savedBill,
              scanType: scanSnapshot,
              referralDoctor: doctorSnapshot,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _patientName.clear();
    _patientId.clear();
    _patientAge.clear();
    _patientPhone.clear();
    _price.clear();
    _discount.text = '0';
    _amountPaid.clear();
    _notes.clear();
    // Regenerate patient ID for next patient
    context.read<BillingService>().generatePatientId().then((id) {
      if (mounted) _patientId.text = id;
    });
    setState(() {
      _selectedScan = null;
      _selectedDoctor = null;
      _patientSex = 'F';
      _paymentMode = 'Cash';
      _autocompleteResetKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text('New Bill'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset form',
            onPressed: () { _resetForm(); _loadData(); },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Patient Details'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _patientName,
                decoration: const InputDecoration(labelText: 'Patient Name *'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().length < 2 ? 'Enter patient name' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _patientId,
                      decoration: const InputDecoration(labelText: 'Patient ID'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _patientPhone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _patientAge,
                      decoration: const InputDecoration(
                        labelText: 'Age',
                        hintText: 'Years',
                        suffixText: 'yrs',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = int.tryParse(v.trim());
                        if (n == null || n < 0 || n > 130) {
                          return 'Enter a valid age';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _patientSex,
                      decoration: const InputDecoration(labelText: 'Sex'),
                      items: const [
                        DropdownMenuItem(value: 'F', child: Text('Female')),
                        DropdownMenuItem(value: 'M', child: Text('Male')),
                        DropdownMenuItem(value: 'O', child: Text('Other')),
                      ],
                      onChanged: (v) => setState(() => _patientSex = v ?? 'F'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              _sectionTitle('Scan Details'),
              const SizedBox(height: 8),

              Autocomplete<ScanType>(
                key: ValueKey(_autocompleteResetKey),
                initialValue: TextEditingValue(
                  text: _selectedScan == null
                      ? ''
                      : '${_selectedScan!.name}  (${formatCurrency(_selectedScan!.price)})',
                ),
                displayStringForOption: (s) =>
                    '${s.name}  (${formatCurrency(s.price)})',
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.trim().toLowerCase();
                  final sorted = [..._scanTypes]..sort((a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()));
                  if (query.isEmpty) return sorted;
                  return sorted.where((s) =>
                      s.name.toLowerCase().contains(query) ||
                      s.category.toLowerCase().contains(query));
                },
                onSelected: (s) => setState(() {
                  _selectedScan = s;
                  _price.text = s.price.toStringAsFixed(0);
                  _discount.text = '0';
                  _amountPaid.text = s.price.toStringAsFixed(0);
                }),
                fieldViewBuilder:
                    (ctx, controller, focusNode, onFieldSubmitted) {
                  controller.addListener(() {
                    final text = controller.text.trim();
                    if (_selectedScan != null &&
                        text !=
                            '${_selectedScan!.name}  (${formatCurrency(_selectedScan!.price)})') {
                      setState(() => _selectedScan = null);
                    }
                  });
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Scan Type *',
                      hintText: 'Type to search…',
                      suffixIcon: Icon(Icons.search),
                    ),
                    validator: (_) =>
                        _selectedScan == null ? 'Select a scan type' : null,
                  );
                },
                optionsViewBuilder: (ctx, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxHeight: 240, maxWidth: 480),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (ctx, i) {
                            final s = options.elementAt(i);
                            return ListTile(
                              dense: true,
                              title: Text(s.name),
                              subtitle: Text(s.category),
                              trailing: Text(formatCurrency(s.price)),
                              onTap: () => onSelected(s),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<ReferralDoctor?>(
                value: _selectedDoctor,
                decoration: const InputDecoration(labelText: 'Referred By'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('(None)')),
                  ..._doctors.map(
                    (d) => DropdownMenuItem(value: d, child: Text('Dr. ${d.name}')),
                  ),
                ],
                onChanged: (d) => setState(() => _selectedDoctor = d),
              ),

              const SizedBox(height: 20),
              _sectionTitle('Payment'),
              const SizedBox(height: 8),

              // ── Price field ───────────────────────────────────────────────
              TextFormField(
                controller: _price,
                decoration: InputDecoration(
                  labelText: 'Price',
                  prefixText: '₹ ',
                  hintText: _selectedScan != null
                      ? _selectedScan!.price.toStringAsFixed(0)
                      : '0',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final p = double.tryParse(v ?? '');
                  if (p == null || p < 0) return 'Enter a valid price';
                  return null;
                },
              ),
              const SizedBox(height: 8),

              // ── Quick-price chips ─────────────────────────────────────────
              _QuickPriceChips(
                price: _price,
                onEditTap: () => _openManagePrices(context),
              ),
              const SizedBox(height: 12),

              // ── Discount field ────────────────────────────────────────────
              TextFormField(
                controller: _discount,
                decoration: const InputDecoration(
                  labelText: 'Discount',
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final d = double.tryParse(v ?? '0') ?? 0;
                  if (d < 0) return 'Cannot be negative';
                  if (d > _scanFee) return 'Discount exceeds price';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              Text('Payment Mode', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Cash', 'UPI', 'Card', 'Credit'].map((mode) {
                  return ChoiceChip(
                    label: Text(mode),
                    selected: _paymentMode == mode,
                    onSelected: (_) => setState(() => _paymentMode = mode),
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
              ),

              const SizedBox(height: 20),
              // Amount summary + partial payment
              if (_selectedScan != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            formatCurrency(_finalAmount),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Amount Paid  ',
                              style: TextStyle(fontSize: 13)),
                          Expanded(
                            child: TextFormField(
                              controller: _amountPaid,
                              decoration: InputDecoration(
                                prefixText: '₹ ',
                                isDense: true,
                                hintText: _finalAmount.toStringAsFixed(0),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      if (() {
                        final paid = double.tryParse(_amountPaid.text) ?? _finalAmount;
                        return paid < _finalAmount;
                      }()) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Pending',
                                style: TextStyle(color: Colors.orange)),
                            Text(
                              formatCurrency(_finalAmount -
                                  (double.tryParse(_amountPaid.text) ?? _finalAmount)),
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Generate Bill'),
                  onPressed: _saving ? null : _submit,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
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

  void _openManagePrices(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ManageQuickPricesSheet(),
    );
  }
}

// ── Quick-price chip row ───────────────────────────────────────────────────────

class _QuickPriceChips extends StatelessWidget {
  final TextEditingController price;
  final VoidCallback onEditTap;

  const _QuickPriceChips({required this.price, required this.onEditTap});

  @override
  Widget build(BuildContext context) {
    final quickPrices = context.watch<AppSettingsService>().quickPrices;
    final currentPrice = price.text;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        ...quickPrices.map((p) {
          final label = '₹${p.toString()}';
          final selected = currentPrice == p.toString();
          return ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => price.text = p.toString(),
          );
        }),
        ActionChip(
          avatar: const Icon(Icons.edit_outlined, size: 14),
          label: const Text('Edit'),
          onPressed: onEditTap,
        ),
      ],
    );
  }
}

// ── Manage quick prices bottom sheet ──────────────────────────────────────────

class _ManageQuickPricesSheet extends StatefulWidget {
  const _ManageQuickPricesSheet();

  @override
  State<_ManageQuickPricesSheet> createState() =>
      _ManageQuickPricesSheetState();
}

class _ManageQuickPricesSheetState extends State<_ManageQuickPricesSheet> {
  late List<int> _prices;
  final _addCtrl = TextEditingController();
  final _addKey = GlobalKey<FormFieldState>();

  @override
  void initState() {
    super.initState();
    _prices = [...context.read<AppSettingsService>().quickPrices];
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<AppSettingsService>().setQuickPrices(_prices);
    if (mounted) Navigator.pop(context);
  }

  void _addPrice() {
    if (!(_addKey.currentState?.validate() ?? false)) return;
    final val = int.tryParse(_addCtrl.text.trim());
    if (val == null || val <= 0) return;
    if (_prices.contains(val)) {
      _addCtrl.clear();
      return;
    }
    setState(() {
      _prices.add(val);
      _prices.sort();
      _addCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Quick Prices',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(onPressed: _save, child: const Text('Done')),
            ],
          ),
          const SizedBox(height: 12),
          if (_prices.isEmpty)
            const Text('No prices added yet.',
                style: TextStyle(color: Colors.grey))
          else
            ..._prices.map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('₹ $p'),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Colors.red),
                    onPressed: _prices.length > 1
                        ? () => setState(() => _prices.remove(p))
                        : null,
                    tooltip: _prices.length > 1 ? 'Remove' : 'Need at least one',
                  ),
                )),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: _addKey,
                  controller: _addCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Add price',
                    prefixText: '₹ ',
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onFieldSubmitted: (_) => _addPrice(),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.trim());
                    if (n == null || n <= 0) return 'Enter a positive number';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _addPrice, child: const Text('Add')),
            ],
          ),
        ],
      ),
    );
  }
}

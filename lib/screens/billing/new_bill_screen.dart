import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing/bill.dart';
import '../../models/billing/referral_doctor.dart';
import '../../models/billing/scan_type.dart';
import '../../services/billing_service.dart';
import '../../services/mwl_service.dart';
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
  final _patientDob = TextEditingController();
  final _patientPhone = TextEditingController();
  String _patientSex = 'F';

  // Scan / billing
  ScanType? _selectedScan;
  ReferralDoctor? _selectedDoctor;
  final _discount = TextEditingController(text: '0');
  String _paymentMode = 'Cash';
  final _notes = TextEditingController();

  List<ScanType> _scanTypes = [];
  List<ReferralDoctor> _doctors = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _discount.addListener(() => setState(() {}));
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
    _patientDob.dispose();
    _patientPhone.dispose();
    _discount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _scanFee => _selectedScan?.price ?? 0;
  double get _discountAmt => double.tryParse(_discount.text) ?? 0;
  double get _finalAmount => (_scanFee - _discountAmt).clamp(0, double.infinity);

  Future<void> _pickDob() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final dd = picked.day.toString().padLeft(2, '0');
      final mm = picked.month.toString().padLeft(2, '0');
      _patientDob.text = '$dd/$mm/${picked.year}';
    }
  }

  /// Converts DD/MM/YYYY user input to YYYYMMDD for DICOM storage.
  String? _dobToDicom(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    final parts = s.split(RegExp(r'[/\-.]'));
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    if (d < 1 || d > 31 || m < 1 || m > 12 || y < 1900 || y > DateTime.now().year) {
      return null;
    }
    return '${y.toString().padLeft(4, '0')}'
        '${m.toString().padLeft(2, '0')}'
        '${d.toString().padLeft(2, '0')}';
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
      final mwlService = context.read<MwlService>();

      final draftBill = Bill(
        id: '',
        patientName: _patientName.text.trim(),
        patientId: _patientId.text.trim().isEmpty ? null : _patientId.text.trim(),
        patientDob: _dobToDicom(_patientDob.text),
        patientSex: _patientSex,
        patientPhone: _patientPhone.text.trim().isEmpty ? null : _patientPhone.text.trim(),
        scanTypeId: _selectedScan!.id,
        referralDoctorId: _selectedDoctor?.id,
        scanFee: _scanFee,
        discount: _discountAmt,
        finalAmount: _finalAmount,
        paymentMode: _paymentMode,
        createdAt: DateTime.now().toIso8601String(),
      );

      final savedBill = await billingService.createBill(draftBill);

      // Best-effort MWL push
      final mwlResult = await mwlService.pushToWorklist(
        bill: savedBill,
        scanType: _selectedScan!,
        referralDoctor: _selectedDoctor,
      );

      if (mwlResult.success) {
        await billingService.markWorklistPushed(savedBill.id);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bill saved. MWL push failed: ${mwlResult.error}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReceiptPreviewScreen(
              bill: savedBill,
              scanType: _selectedScan,
              referralDoctor: _selectedDoctor,
            ),
          ),
        );
        _resetForm();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _patientName.clear();
    _patientId.clear();
    _patientDob.clear();
    _patientPhone.clear();
    _discount.text = '0';
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
            tooltip: 'Reload scan types & doctors',
            onPressed: _loadData,
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
                      controller: _patientDob,
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        hintText: 'DD/MM/YYYY',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today_outlined),
                          onPressed: _pickDob,
                        ),
                      ),
                      keyboardType: TextInputType.datetime,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        return _dobToDicom(v) == null
                            ? 'Use DD/MM/YYYY'
                            : null;
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
                  _discount.text = '0';
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

              TextFormField(
                controller: _discount,
                decoration: InputDecoration(
                  labelText: 'Discount',
                  prefixText: '₹ ',
                  helperText: _selectedScan != null
                      ? 'Scan fee: ${formatCurrency(_scanFee)}'
                      : null,
                ),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final d = double.tryParse(v ?? '0') ?? 0;
                  if (d < 0) return 'Cannot be negative';
                  if (d > _scanFee) return 'Discount exceeds scan fee';
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
              // Amount summary
              if (_selectedScan != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Amount to Collect',
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
                ),
                const SizedBox(height: 20),
              ],

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Generate Bill & Push to MWL'),
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
}

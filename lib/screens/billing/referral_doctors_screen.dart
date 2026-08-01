import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/billing/doctor_scan_incentive.dart';
import '../../models/billing/referral_doctor.dart';
import '../../models/billing/scan_type.dart';
import '../../services/billing_service.dart';

class ReferralDoctorsScreen extends StatefulWidget {
  const ReferralDoctorsScreen({super.key});

  @override
  State<ReferralDoctorsScreen> createState() => _ReferralDoctorsScreenState();
}

class _ReferralDoctorsScreenState extends State<ReferralDoctorsScreen> {
  List<ReferralDoctor> _doctors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docs = await context.read<BillingService>().getReferralDoctors();
    if (mounted) setState(() { _doctors = docs; _loading = false; });
  }

  Future<void> _openForm([ReferralDoctor? existing]) async {
    final service = context.read<BillingService>();
    final scanTypes = await service.getScanTypes(activeOnly: true);
    final existingRates = existing != null
        ? await service.getDoctorRates(existing.id)
        : <String, DoctorScanIncentive>{};

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DoctorForm(
        existing: existing,
        scanTypes: scanTypes,
        existingRates: existingRates,
        onSave: (doc, rates) async {
          if (existing == null) {
            await service.saveReferralDoctor(doc);
          } else {
            await service.updateReferralDoctor(doc);
          }
          await service.saveAllDoctorRates(doc.id, rates);
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Referral Doctors')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _doctors.isEmpty
              ? const Center(child: Text('No referral doctors yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _doctors.length,
                  itemBuilder: (_, i) {
                    final doc = _doctors[i];
                    return ListTile(
                      leading: CircleAvatar(child: Text(doc.name[0].toUpperCase())),
                      title: Text(doc.name),
                      subtitle: Text(doc.clinicName ?? ''),
                      trailing: doc.isActive
                          ? null
                          : const Chip(label: Text('Inactive')),
                      onTap: () => _openForm(doc),
                    );
                  },
                ),
    );
  }
}

class _DoctorForm extends StatefulWidget {
  final ReferralDoctor? existing;
  final List<ScanType> scanTypes;
  final Map<String, DoctorScanIncentive> existingRates;
  final Future<void> Function(ReferralDoctor, List<DoctorScanIncentive>) onSave;

  const _DoctorForm({
    this.existing,
    required this.scanTypes,
    required this.existingRates,
    required this.onSave,
  });

  @override
  State<_DoctorForm> createState() => _DoctorFormState();
}

class _DoctorFormState extends State<_DoctorForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _clinic;
  late final TextEditingController _specialty;
  late final Map<String, TextEditingController> _rateControllers;
  final _bulkRate = TextEditingController();
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _name = TextEditingController(text: d?.name ?? '');
    _phone = TextEditingController(text: d?.phone ?? '');
    _clinic = TextEditingController(text: d?.clinicName ?? '');
    _specialty = TextEditingController(text: d?.specialty ?? '');
    _isActive = d?.isActive ?? true;

    _rateControllers = {
      for (final st in widget.scanTypes)
        st.id: TextEditingController(
          text: () {
            final rate = widget.existingRates[st.id]?.rate;
            return (rate == null || rate == 0) ? '' : rate.toStringAsFixed(0);
          }(),
        ),
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _clinic.dispose();
    _specialty.dispose();
    _bulkRate.dispose();
    for (final c in _rateControllers.values) c.dispose();
    super.dispose();
  }

  /// Fills every scan-type rate with the amount typed in the bulk field.
  void _applyToAll() {
    final raw = _bulkRate.text.trim();
    final value = double.tryParse(raw);
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount first.')),
      );
      return;
    }
    final text = value.toStringAsFixed(0);
    for (final c in _rateControllers.values) {
      c.text = text;
    }
    FocusScope.of(context).unfocus();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final docId = widget.existing?.id ?? const Uuid().v4();

    final doc = ReferralDoctor(
      id: docId,
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      clinicName: _clinic.text.trim().isEmpty ? null : _clinic.text.trim(),
      specialty: _specialty.text.trim().isEmpty ? null : _specialty.text.trim(),
      isActive: _isActive,
    );

    final rates = widget.scanTypes.map((st) {
      final raw = _rateControllers[st.id]?.text.trim() ?? '';
      final rate = double.tryParse(raw) ?? 0.0;
      final existingId = widget.existingRates[st.id]?.id ?? const Uuid().v4();
      return DoctorScanIncentive(
        id: existingId,
        doctorId: docId,
        scanTypeId: st.id,
        rate: rate,
      );
    }).toList();

    await widget.onSave(doc, rates);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Group scan types by category
    final categories = <String>[];
    final byCategory = <String, List<ScanType>>{};
    for (final st in widget.scanTypes) {
      if (!byCategory.containsKey(st.category)) {
        categories.add(st.category);
        byCategory[st.category] = [];
      }
      byCategory[st.category]!.add(st);
    }

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
                widget.existing == null ? 'Add Referral Doctor' : 'Edit Doctor',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Doctor Name *'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().length < 2 ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  if (v.trim().length != 10) return 'Enter 10-digit number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clinic,
                decoration: const InputDecoration(labelText: 'Clinic / Hospital'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _specialty,
                decoration: const InputDecoration(labelText: 'Specialty'),
              ),
              const SizedBox(height: 16),

              // Per-scan incentive rates
              Text('Incentive Rates (₹ per referral)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                'Leave blank or 0 for no incentive on that scan.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 10),

              // Set the same amount for every scan type at once.
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _bulkRate,
                      decoration: const InputDecoration(
                        prefixText: '₹ ',
                        hintText: 'Amount',
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      onSubmitted: (_) => _applyToAll(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _applyToAll,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: const Text('Apply to all'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              ...categories.expand((cat) {
                final scans = byCategory[cat]!;
                return [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, top: 4),
                    child: Text(
                      cat,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  ...scans.map((st) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(st.name,
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: TextFormField(
                                controller: _rateControllers[st.id],
                                decoration: const InputDecoration(
                                  prefixText: '₹ ',
                                  hintText: '0',
                                  isDense: true,
                                ),
                                keyboardType: TextInputType.number,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  final d = double.tryParse(v.trim());
                                  if (d == null || d < 0) return 'Invalid';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      )),
                  const Divider(height: 16),
                ];
              }),

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
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

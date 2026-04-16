import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/billing/referral_doctor.dart';
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
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DoctorForm(
        existing: existing,
        onSave: (doc) async {
          final service = context.read<BillingService>();
          if (existing == null) {
            await service.saveReferralDoctor(doc);
          } else {
            await service.updateReferralDoctor(doc);
          }
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
                    final incentiveLabel = doc.incentiveType == 'percentage'
                        ? '${doc.incentiveValue.toStringAsFixed(0)}%'
                        : '₹${doc.incentiveValue.toStringAsFixed(0)}';
                    return ListTile(
                      leading: CircleAvatar(child: Text(doc.name[0].toUpperCase())),
                      title: Text(doc.name),
                      subtitle: Text('${doc.clinicName ?? ''} · Incentive: $incentiveLabel'),
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
  final Future<void> Function(ReferralDoctor) onSave;

  const _DoctorForm({this.existing, required this.onSave});

  @override
  State<_DoctorForm> createState() => _DoctorFormState();
}

class _DoctorFormState extends State<_DoctorForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _clinic;
  late final TextEditingController _specialty;
  late final TextEditingController _incentiveValue;
  String _incentiveType = 'flat';
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
    _incentiveValue = TextEditingController(
        text: d?.incentiveValue.toStringAsFixed(0) ?? '0');
    _incentiveType = d?.incentiveType ?? 'flat';
    _isActive = d?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _clinic.dispose();
    _specialty.dispose();
    _incentiveValue.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final doc = ReferralDoctor(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      clinicName: _clinic.text.trim().isEmpty ? null : _clinic.text.trim(),
      specialty: _specialty.text.trim().isEmpty ? null : _specialty.text.trim(),
      incentiveType: _incentiveType,
      incentiveValue: double.tryParse(_incentiveValue.text) ?? 0,
      isActive: _isActive,
    );
    await widget.onSave(doc);
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
                widget.existing == null ? 'Add Referral Doctor' : 'Edit Doctor',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Doctor Name *'),
                validator: (v) => v == null || v.trim().length < 2 ? 'Required' : null,
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
              Text('Incentive Type', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'flat', label: Text('Flat (₹)')),
                  ButtonSegment(value: 'percentage', label: Text('Percentage (%)')),
                ],
                selected: {_incentiveType},
                onSelectionChanged: (s) => setState(() => _incentiveType = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _incentiveValue,
                decoration: InputDecoration(
                  labelText: 'Incentive Value',
                  prefixText: _incentiveType == 'flat' ? '₹ ' : null,
                  suffixText: _incentiveType == 'percentage' ? '%' : null,
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
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

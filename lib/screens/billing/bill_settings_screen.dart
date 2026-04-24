import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_service.dart';

class BillSettingsScreen extends StatefulWidget {
  const BillSettingsScreen({super.key});

  @override
  State<BillSettingsScreen> createState() => _BillSettingsScreenState();
}

class _BillSettingsScreenState extends State<BillSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _header1;
  late final TextEditingController _header2;
  late final TextEditingController _footer;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppSettingsService>();
    _header1 = TextEditingController(text: s.receiptHeader1);
    _header2 = TextEditingController(text: s.receiptHeader2);
    _footer  = TextEditingController(text: s.receiptFooter);
  }

  @override
  void dispose() {
    _header1.dispose();
    _header2.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    await context.read<AppSettingsService>().setReceiptText(
      header1: _header1.text.trim(),
      header2: _header2.text.trim(),
      footer:  _footer.text.trim(),
    );
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill settings saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bill Settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionTitle(context, 'Receipt Header'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _header1,
              decoration: const InputDecoration(
                labelText: 'Line 1 — Clinic name (bold)',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _header2,
              decoration: const InputDecoration(
                labelText: 'Line 2 — Subtitle (optional)',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Receipt Footer'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _footer,
              decoration: const InputDecoration(
                labelText: 'Footer text',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 32),

            // Live preview card
            _sectionTitle(context, 'Preview'),
            const SizedBox(height: 8),
            ListenableBuilder(
              listenable: Listenable.merge([_header1, _header2, _footer]),
              builder: (context, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  child: Column(
                    children: [
                      Text(
                        _header1.text.isEmpty
                            ? '(Clinic name)'
                            : _header1.text,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      if (_header2.text.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _header2.text,
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const Divider(height: 20),
                      Text(
                        '— bill content —',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.outline),
                      ),
                      const Divider(height: 20),
                      Text(
                        _footer.text.isEmpty ? '(Footer text)' : _footer.text,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

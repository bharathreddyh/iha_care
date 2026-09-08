import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';

/// Shown after sign-up (or after signing in with no centre) so a user can
/// either create their own centre or join an existing one by its code.
class CentreSetupScreen extends StatefulWidget {
  const CentreSetupScreen({super.key});

  @override
  State<CentreSetupScreen> createState() => _CentreSetupScreenState();
}

enum _Mode { create, join }

class _CentreSetupScreenState extends State<CentreSetupScreen> {
  _Mode _mode = _Mode.create;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      final centre = _mode == _Mode.create
          ? await auth.createCentre(_name.text.trim(), _code.text.trim())
          : await auth.joinCentre(_code.text.trim());
      await auth.selectCentre(centre);
      if (!mounted) return;
      // Selecting a centre flips AuthService.isLoggedIn → the app gate takes
      // over. Drop back to the root route so the app shell shows.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e.toString());
          _loading = false;
        });
      }
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('CENTRE_CODE_TAKEN')) {
      return 'That centre code is already taken. Choose a different one.';
    }
    if (raw.contains('CENTRE_NOT_FOUND')) {
      return 'No centre found with that code. Check it with the centre owner.';
    }
    if (raw.contains('network') || raw.contains('SocketException')) {
      return 'No internet connection. Check your network.';
    }
    return _mode == _Mode.create
        ? 'Could not create the centre. Please try again.'
        : 'Could not join the centre. Please try again.';
  }

  void _switchMode(_Mode m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = _mode == _Mode.create;
    return Scaffold(
      appBar: AppBar(title: const Text('Set Up Centre')),
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Card(
              elevation: 4,
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<_Mode>(
                        segments: const [
                          ButtonSegment(
                            value: _Mode.create,
                            label: Text('Create new'),
                            icon: Icon(Icons.add_business_outlined),
                          ),
                          ButtonSegment(
                            value: _Mode.join,
                            label: Text('Join existing'),
                            icon: Icon(Icons.group_add_outlined),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: _loading
                            ? null
                            : (s) => _switchMode(s.first),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        isCreate ? 'Set up your centre' : 'Join a centre',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCreate
                            ? 'You\'ll be the owner and can add staff later.'
                            : 'Ask the centre owner for the centre code.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      if (isCreate) ...[
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Centre name',
                            prefixIcon: Icon(Icons.local_hospital_outlined),
                            hintText: 'e.g. your scan & diagnostics centre',
                          ),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter a centre name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _code,
                        decoration: InputDecoration(
                          labelText: 'Centre code',
                          prefixIcon: const Icon(Icons.tag),
                          hintText: isCreate
                              ? 'e.g. IHA01 — a short unique ID'
                              : 'Enter the code from the owner',
                        ),
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter the centre code'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                                fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(isCreate
                                ? 'Create centre & continue'
                                : 'Join centre & continue'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

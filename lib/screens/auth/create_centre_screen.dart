import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';

/// Shown after sign-up (or after signing in with no centre yet) so a user can
/// create their own centre and enter the app as its owner.
class CreateCentreScreen extends StatefulWidget {
  const CreateCentreScreen({super.key});

  @override
  State<CreateCentreScreen> createState() => _CreateCentreScreenState();
}

class _CreateCentreScreenState extends State<CreateCentreScreen> {
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

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthService>();
      final centre =
          await auth.createCentre(_name.text.trim(), _code.text.trim());
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
    if (raw.contains('network') || raw.contains('SocketException')) {
      return 'No internet connection. Check your network.';
    }
    return 'Could not create the centre. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Your Centre')),
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
                      Text(
                        'Set up your centre',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You\'ll be the owner and can add staff later.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          labelText: 'Centre name',
                          prefixIcon: Icon(Icons.local_hospital_outlined),
                          hintText: 'e.g. Sahyadri Scan and Diagnostics',
                        ),
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter a centre name'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(
                          labelText: 'Centre code',
                          prefixIcon: Icon(Icons.tag),
                          hintText: 'e.g. IHA01 — a short unique ID',
                        ),
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _create(),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter a short centre code'
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
                        onPressed: _loading ? null : _create,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Create centre & continue'),
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

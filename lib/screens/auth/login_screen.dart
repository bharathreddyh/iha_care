import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/auth/app_centre.dart';
import '../../services/auth_service.dart';
import 'centre_picker_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final auth = context.read<AuthService>();
      final centres = await auth.signIn(_email.text.trim(), _password.text);

      if (!mounted) return;

      if (centres.isEmpty) {
        setState(() {
          _error = 'No centres assigned to this account. Contact the administrator.';
          _loading = false;
        });
        return;
      }

      if (centres.length == 1) {
        await auth.selectCentre(centres.first);
      } else {
        final picked = await Navigator.push<AppCentre>(
          context,
          MaterialPageRoute(
            builder: (_) => CentrePickerScreen(centres: centres),
          ),
        );
        if (!mounted) return;
        if (picked != null) {
          await auth.selectCentre(picked);
        } else {
          setState(() => _loading = false);
          return;
        }
      }
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
    if (raw.contains('Invalid login credentials')) return 'Incorrect email or password.';
    if (raw.contains('network') || raw.contains('SocketException')) {
      return 'No internet connection. Check your network.';
    }
    return 'Sign in failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
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
                      'Sahyadri Scan and Diagnostics',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'USG Billing System',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          v == null || !v.contains('@') ? 'Enter a valid email' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _signIn(),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Enter password' : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer,
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
                      onPressed: _loading ? null : _signIn,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign In'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

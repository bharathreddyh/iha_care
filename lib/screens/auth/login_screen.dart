import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth/app_centre.dart';
import '../../services/auth_service.dart';
import 'centre_picker_screen.dart';
import 'centre_setup_screen.dart';
import 'reset_password_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _kRemember = 'login_remember';
  static const _kSavedEmail = 'login_email';
  static const _kSavedPassword = 'login_password';

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kRemember) ?? false) {
      if (!mounted) return;
      setState(() {
        _remember = true;
        _email.text = prefs.getString(_kSavedEmail) ?? '';
        _password.text = prefs.getString(_kSavedPassword) ?? '';
      });
    }
  }

  Future<void> _persistRemember() async {
    final prefs = await SharedPreferences.getInstance();
    if (_remember) {
      await prefs.setBool(_kRemember, true);
      await prefs.setString(_kSavedEmail, _email.text.trim());
      await prefs.setString(_kSavedPassword, _password.text);
    } else {
      await prefs.remove(_kRemember);
      await prefs.remove(_kSavedEmail);
      await prefs.remove(_kSavedPassword);
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      final auth = context.read<AuthService>();
      final centres = await auth.signIn(_email.text.trim(), _password.text);

      // Credentials were valid — honour the "remember me" choice.
      await _persistRemember();

      if (!mounted) return;

      if (centres.isEmpty) {
        // No centre yet → let the user create their own.
        setState(() => _loading = false);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CentreSetupScreen()),
        );
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
    final r = raw.toLowerCase();
    if (r.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (r.contains('email not confirmed')) {
      return 'Email not confirmed. Confirm it, or turn off "Confirm email" in Supabase.';
    }
    if (r.contains('failed host lookup') ||
        r.contains('socketexception') ||
        r.contains('connection refused') ||
        r.contains('network is unreachable') ||
        r.contains('connection closed') ||
        r.contains('handshake') ||
        r.contains('timed out') ||
        r.contains('timeout')) {
      return 'Can\'t reach the server. Internet may work in the browser but be '
          'blocked for this app — allow iha_care.exe OUTBOUND in the firewall '
          '(for the active network profile), and check any VPN/proxy.\n\n$raw';
    }
    // Surface the real error so problems can be diagnosed.
    return 'Sign in failed: $raw';
  }

  void _forgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ResetPasswordScreen(initialEmail: _email.text.trim()),
      ),
    );
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
                      'IHA Care',
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
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _loading
                                ? null
                                : () =>
                                    setState(() => _remember = !_remember),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _remember,
                                  onChanged: _loading
                                      ? null
                                      : (v) => setState(
                                          () => _remember = v ?? false),
                                ),
                                const Flexible(child: Text('Remember me')),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _forgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ],
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
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const SignUpScreen()),
                              ),
                      child: const Text('New here? Create an account'),
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

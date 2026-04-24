import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_service.dart';

class RolePickerScreen extends StatelessWidget {
  const RolePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_hospital_outlined, size: 56),
                const SizedBox(height: 16),
                Text(
                  'Sahyadri Scan and Diagnostics',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select the role for this workstation.\nThis is saved and only needs to be set once.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 40),
                _RoleCard(
                  icon: Icons.receipt_long_outlined,
                  title: 'Receptionist',
                  subtitle: 'Patient registration · Billing · Reports',
                  onTap: () => _pick(context, AppRole.receptionist),
                ),
                const SizedBox(height: 16),
                _RoleCard(
                  icon: Icons.medical_services_outlined,
                  title: 'Typist / Reporting',
                  subtitle: 'Worklist · Push to scanner · Images · Biometry',
                  onTap: () => _pick(context, AppRole.typist),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, AppRole role) async {
    await context.read<AppSettingsService>().setRole(role);
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/billing/bill_settings_screen.dart';
import '../screens/billing/billing_dashboard_screen.dart';
import '../screens/billing/bill_history_screen.dart';
import '../screens/billing/incentive_report_screen.dart';
import '../screens/billing/new_bill_screen.dart';
import '../screens/billing/referral_doctors_screen.dart';
import '../screens/billing/reports_screen.dart';
import '../screens/billing/scan_types_screen.dart';
import '../screens/auth/change_password_screen.dart';
import '../screens/auth/members_screen.dart';
import '../screens/inventory/inventory_screen.dart';
import '../screens/typist/worklist_queue_screen.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/sync_service.dart';

class NavigationShell extends StatelessWidget {
  const NavigationShell({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsService>();
    if (settings.isTypist) return const _TypistShell();
    return const _ReceptionistShell();
  }
}

// ── Receptionist shell ────────────────────────────────────────────────────────

class _ReceptionistShell extends StatefulWidget {
  const _ReceptionistShell();

  @override
  State<_ReceptionistShell> createState() => _ReceptionistShellState();
}

class _ReceptionistShellState extends State<_ReceptionistShell> {
  int _selectedIndex = 0;
  final _newBillKey = GlobalKey<NewBillScreenState>();

  late final List<Widget> _screens = [
    const BillingDashboardScreen(),
    NewBillScreen(key: _newBillKey),
    const BillHistoryScreen(),
    const ReferralDoctorsScreen(),
    const ReportsScreen(),
  ];

  void _onTabSelected(int i) {
    setState(() => _selectedIndex = i);
    if (i == 1) _newBillKey.currentState?.refresh();
  }

  static const _destinations = [
    NavigationRailDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: Text('Dashboard'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: Text('New Bill'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.history_outlined),
      selectedIcon: Icon(Icons.history),
      label: Text('History'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.people_outline),
      selectedIcon: Icon(Icons.people),
      label: Text('Referrals'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.bar_chart_outlined),
      selectedIcon: Icon(Icons.bar_chart),
      label: Text('Reports'),
    ),
  ];

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 700;
      if (isWide) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onTabSelected,
                extended: constraints.maxWidth > 1000,
                destinations: _destinations,
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SyncIndicator(),
                          const SizedBox(height: 4),
                          _CentreLabel(),
                          const SizedBox(height: 8),
                          IconButton(
                            icon: const Icon(Icons.category_outlined),
                            tooltip: 'Scan Types',
                            onPressed: () =>
                                _push(context, const ScanTypesScreen()),
                          ),
                          IconButton(
                            icon: const Icon(Icons.receipt_outlined),
                            tooltip: 'Bill Settings',
                            onPressed: () =>
                                _push(context, const BillSettingsScreen()),
                          ),
                          IconButton(
                            icon: const Icon(Icons.assessment_outlined),
                            tooltip: 'Incentive Report',
                            onPressed: () =>
                                _push(context, const IncentiveReportScreen()),
                          ),
                          IconButton(
                            icon: const Icon(Icons.inventory_2_outlined),
                            tooltip: 'Inventory',
                            onPressed: () =>
                                _push(context, const InventoryScreen()),
                          ),
                          IconButton(
                            icon: const Icon(Icons.groups_outlined),
                            tooltip: 'Members',
                            onPressed: () =>
                                _push(context, const MembersScreen()),
                          ),
                          IconButton(
                            icon: const Icon(Icons.password_outlined),
                            tooltip: 'Change Password',
                            onPressed: () =>
                                _push(context, const ChangePasswordScreen()),
                          ),
                          IconButton(
                            icon: const Icon(Icons.switch_account_outlined),
                            tooltip: 'Switch Role',
                            onPressed: () =>
                                _confirmSwitchRole(context),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout),
                            tooltip: 'Sign Out',
                            onPressed: () => _confirmSignOut(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _screens,
                ),
              ),
            ],
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: _CentreLabel(),
          actions: [
            _SyncIndicator(),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign Out',
              onPressed: () => _confirmSignOut(context),
            ),
          ],
        ),
        body: IndexedStack(index: _selectedIndex, children: _screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onTabSelected,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'New Bill',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Referrals',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Reports',
            ),
          ],
        ),
      );
    });
  }

  Future<void> _confirmSwitchRole(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Role?'),
        content: const Text(
            'This will reset the workstation role. You will need to pick again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppSettingsService>().clearRole();
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthService>().signOut();
    }
  }
}

// ── Typist shell ──────────────────────────────────────────────────────────────

class _TypistShell extends StatelessWidget {
  const _TypistShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.queue_outlined),
                selectedIcon: Icon(Icons.queue),
                label: Text('Worklist'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SyncIndicator(),
                      const SizedBox(height: 4),
                      _CentreLabel(),
                      const SizedBox(height: 8),
                      IconButton(
                        icon: const Icon(Icons.password_outlined),
                        tooltip: 'Change Password',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ChangePasswordScreen()),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.switch_account_outlined),
                        tooltip: 'Switch Role',
                        onPressed: () => _confirmSwitchRole(context),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: 'Sign Out',
                        onPressed: () => _confirmSignOut(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          const Expanded(child: WorklistQueueScreen()),
        ],
      ),
    );
  }

  Future<void> _confirmSwitchRole(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Role?'),
        content: const Text(
            'This will reset the workstation role. You will need to pick again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppSettingsService>().clearRole();
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('You will need to sign in again to continue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AuthService>().signOut();
    }
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SyncIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final auth = context.watch<AuthService>();

    Widget icon;
    String tooltip;
    switch (sync.status) {
      case SyncStatus.syncing:
        icon = const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2));
        tooltip = 'Syncing…';
      case SyncStatus.offline:
        icon = const Icon(Icons.cloud_off_outlined, size: 20);
        tooltip = 'Offline — changes saved locally';
      case SyncStatus.error:
        icon = const Icon(Icons.sync_problem_outlined,
            size: 20, color: Colors.orange);
        tooltip = 'Sync error: ${sync.lastError ?? ''}';
      case SyncStatus.idle:
        icon = const Icon(Icons.cloud_done_outlined, size: 20);
        final t = sync.lastSync;
        tooltip = t != null ? 'Synced ${_timeAgo(t)}' : 'Cloud sync active';
    }

    final deviceCount = auth.activeDeviceCount;
    return Tooltip(
      message:
          '$tooltip${deviceCount > 1 ? '\n$deviceCount devices active' : ''}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: icon,
            onPressed: sync.status == SyncStatus.syncing
                ? null
                : () => sync.syncAll(),
          ),
          if (deviceCount > 1)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                constraints:
                    const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text(
                  '$deviceCount',
                  style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.onPrimary),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _CentreLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = context.watch<AuthService>().centreName;
    if (name == null) return const SizedBox.shrink();
    return Text(
      name,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
      overflow: TextOverflow.ellipsis,
    );
  }
}

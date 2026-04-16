import 'package:flutter/material.dart';

import '../screens/billing/billing_dashboard_screen.dart';
import '../screens/billing/bill_history_screen.dart';
import '../screens/billing/incentive_report_screen.dart';
import '../screens/billing/new_bill_screen.dart';
import '../screens/billing/referral_doctors_screen.dart';
import '../screens/billing/reports_screen.dart';
import '../screens/billing/scan_types_screen.dart';
import '../screens/billing/worklist_status_screen.dart';

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _selectedIndex = 0;

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
    NavigationRailDestination(
      icon: Icon(Icons.queue_outlined),
      selectedIcon: Icon(Icons.queue),
      label: Text('Worklist'),
    ),
  ];

  static const _screens = [
    BillingDashboardScreen(),
    NewBillScreen(),
    BillHistoryScreen(),
    ReferralDoctorsScreen(),
    ReportsScreen(),
    WorklistStatusScreen(),
  ];

  // Extra screens accessible via AppBar navigation from main screens
  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (i) =>
                      setState(() => _selectedIndex = i),
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
                            IconButton(
                              icon: const Icon(Icons.category_outlined),
                              tooltip: 'Scan Types',
                              onPressed: () => _navigateTo(
                                  context, const ScanTypesScreen()),
                            ),
                            IconButton(
                              icon: const Icon(Icons.assessment_outlined),
                              tooltip: 'Incentive Report',
                              onPressed: () => _navigateTo(
                                  context, const IncentiveReportScreen()),
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

        // Narrow (mobile/small window) layout
        return Scaffold(
          body: IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
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
                icon: Icon(Icons.queue_outlined),
                selectedIcon: Icon(Icons.queue),
                label: 'Worklist',
              ),
            ],
          ),
        );
      },
    );
  }
}

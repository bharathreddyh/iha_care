import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app_theme.dart';
import 'app/navigation_shell.dart';
import 'config/supabase_config.dart';
import 'screens/auth/login_screen.dart';
import 'services/auth_service.dart';
import 'services/billing_service.dart';
import 'services/inventory_service.dart';
import 'services/mwl_service.dart';
import 'services/orthanc_service.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await initializeDateFormatting('en_IN', null);

  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
  );

  final authService = AuthService();
  await authService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authService),
        ChangeNotifierProxyProvider<AuthService, SyncService>(
          create: (ctx) => SyncService(ctx.read<AuthService>()),
          update: (ctx, auth, prev) => prev ?? SyncService(auth),
        ),
        Provider<BillingService>(create: (_) => BillingService()),
        Provider<InventoryService>(create: (_) => InventoryService()),
        Provider<MwlService>(create: (_) => MwlService()),
        Provider<OrthancService>(create: (_) => OrthancService()),
      ],
      child: const IhaCareApp(),
    ),
  );
}

class IhaCareApp extends StatelessWidget {
  const IhaCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IHA Care — USG Billing',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.isLoggedIn) return const NavigationShell();
    return const LoginScreen();
  }
}

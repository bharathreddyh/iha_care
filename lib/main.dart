import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/app_theme.dart';
import 'app/navigation_shell.dart';
import 'services/billing_service.dart';
import 'services/mwl_service.dart';
import 'services/orthanc_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  await initializeDateFormatting('en_IN', null);

  runApp(
    MultiProvider(
      providers: [
        Provider<BillingService>(create: (_) => BillingService()),
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
      home: const NavigationShell(),
    );
  }
}

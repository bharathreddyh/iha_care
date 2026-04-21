import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = join(dir.path, 'iha_care_billing.db');
    return openDatabase(
      dbPath,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE scan_types (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        category TEXT NOT NULL,
        modality TEXT NOT NULL DEFAULT 'US',
        is_active INTEGER NOT NULL DEFAULT 1,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE referral_doctors (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        clinic_name TEXT,
        specialty TEXT,
        incentive_type TEXT NOT NULL DEFAULT 'flat',
        incentive_value REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE bills (
        id TEXT PRIMARY KEY,
        patient_name TEXT NOT NULL,
        patient_id TEXT,
        patient_dob TEXT,
        patient_sex TEXT,
        patient_phone TEXT,
        scan_type_id TEXT,
        referral_doctor_id TEXT,
        scan_fee REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0,
        final_amount REAL NOT NULL,
        payment_mode TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'paid',
        accession_number TEXT UNIQUE,
        worklist_pushed INTEGER NOT NULL DEFAULT 0,
        scan_completed INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        report_created INTEGER NOT NULL DEFAULT 0,
        dispatched INTEGER NOT NULL DEFAULT 0,
        amount_paid REAL,
        cancelled_at TEXT,
        cancel_reason TEXT,
        report_excluded INTEGER NOT NULL DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE pcpndt_form_f (
        id TEXT PRIMARY KEY,
        bill_id TEXT NOT NULL,
        patient_id TEXT,
        referral_doctor_id TEXT,
        indication TEXT,
        declaration_signed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    batch.execute('''
      CREATE TABLE incentive_ledger (
        id TEXT PRIMARY KEY,
        referral_doctor_id TEXT NOT NULL,
        month TEXT NOT NULL,
        referral_count INTEGER NOT NULL DEFAULT 0,
        total_billed REAL NOT NULL DEFAULT 0,
        incentive_amount REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'unpaid',
        paid_date TEXT,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE doctor_scan_incentives (
        id TEXT PRIMARY KEY,
        doctor_id TEXT NOT NULL,
        scan_type_id TEXT NOT NULL,
        rate REAL NOT NULL DEFAULT 0,
        synced INTEGER NOT NULL DEFAULT 0,
        UNIQUE(doctor_id, scan_type_id)
      )
    ''');

    batch.execute('''
      CREATE TABLE inventory_items (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT 'pcs',
        current_quantity REAL NOT NULL DEFAULT 0,
        min_quantity REAL NOT NULL DEFAULT 0,
        price_per_unit REAL,
        is_active INTEGER NOT NULL DEFAULT 1,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE inventory_scan_usage (
        id TEXT PRIMARY KEY,
        scan_type_id TEXT NOT NULL,
        item_id TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        synced INTEGER NOT NULL DEFAULT 0,
        UNIQUE(scan_type_id, item_id)
      )
    ''');

    batch.execute('''
      CREATE TABLE inventory_transactions (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        type TEXT NOT NULL,
        quantity REAL NOT NULL,
        bill_id TEXT,
        cost REAL,
        notes TEXT,
        created_at TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    batch.execute('''
      CREATE TABLE app_settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
    await _seedScanTypes(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS doctor_scan_incentives (
          id TEXT PRIMARY KEY,
          doctor_id TEXT NOT NULL,
          scan_type_id TEXT NOT NULL,
          rate REAL NOT NULL DEFAULT 0,
          UNIQUE(doctor_id, scan_type_id)
        )
      ''');
    }
    if (oldVersion < 3) {
      const tables = [
        'bills',
        'scan_types',
        'referral_doctors',
        'doctor_scan_incentives',
        'incentive_ledger',
      ];
      for (final t in tables) {
        try {
          await db.execute(
              'ALTER TABLE $t ADD COLUMN synced INTEGER NOT NULL DEFAULT 0');
        } catch (_) {}
      }
    }
    if (oldVersion < 4) {
      try { await db.execute('ALTER TABLE bills ADD COLUMN report_created INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE bills ADD COLUMN dispatched INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE bills ADD COLUMN amount_paid REAL'); } catch (_) {}
    }
    if (oldVersion < 5) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS inventory_items (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, unit TEXT NOT NULL DEFAULT 'pcs',
            current_quantity REAL NOT NULL DEFAULT 0, min_quantity REAL NOT NULL DEFAULT 0,
            price_per_unit REAL, is_active INTEGER NOT NULL DEFAULT 1, synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS inventory_scan_usage (
            id TEXT PRIMARY KEY, scan_type_id TEXT NOT NULL, item_id TEXT NOT NULL,
            quantity REAL NOT NULL DEFAULT 1, synced INTEGER NOT NULL DEFAULT 0,
            UNIQUE(scan_type_id, item_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS inventory_transactions (
            id TEXT PRIMARY KEY, item_id TEXT NOT NULL, type TEXT NOT NULL,
            quantity REAL NOT NULL, bill_id TEXT, cost REAL, notes TEXT,
            created_at TEXT NOT NULL, synced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try { await db.execute('ALTER TABLE bills ADD COLUMN cancelled_at TEXT'); } catch (_) {}
      try { await db.execute('ALTER TABLE bills ADD COLUMN cancel_reason TEXT'); } catch (_) {}
    }
    if (oldVersion < 7) {
      try { await db.execute('ALTER TABLE bills ADD COLUMN report_excluded INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS app_settings (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
  }

  Future<void> _seedScanTypes(Database db) async {
    final seeds = [
      {'id': 'st_001', 'name': 'OB Scan', 'price': 800.0, 'category': 'OB-GYN'},
      {'id': 'st_002', 'name': 'TVS', 'price': 1200.0, 'category': 'OB-GYN'},
      {'id': 'st_003', 'name': 'NT Scan', 'price': 1500.0, 'category': 'OB-GYN'},
      {'id': 'st_004', 'name': 'Anomaly Scan', 'price': 2000.0, 'category': 'OB-GYN'},
      {'id': 'st_005', 'name': 'Growth Scan', 'price': 1000.0, 'category': 'OB-GYN'},
      {'id': 'st_006', 'name': 'Doppler', 'price': 1800.0, 'category': 'OB-GYN'},
      {'id': 'st_007', 'name': 'Abdomen', 'price': 700.0, 'category': 'General'},
      {'id': 'st_008', 'name': 'Pelvis', 'price': 800.0, 'category': 'General'},
      {'id': 'st_009', 'name': 'KUB', 'price': 700.0, 'category': 'General'},
      {'id': 'st_010', 'name': 'Thyroid', 'price': 600.0, 'category': 'Small Parts'},
      {'id': 'st_011', 'name': 'Breast', 'price': 800.0, 'category': 'Small Parts'},
      {'id': 'st_012', 'name': 'Scrotal', 'price': 700.0, 'category': 'Small Parts'},
      {'id': 'st_013', 'name': 'Neck', 'price': 600.0, 'category': 'Small Parts'},
      {'id': 'st_014', 'name': 'MSK USG', 'price': 900.0, 'category': 'MSK'},
    ];

    for (final seed in seeds) {
      await db.insert(
        'scan_types',
        {...seed, 'modality': 'US', 'is_active': 1},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<int> insert(String table, Map<String, dynamic> row) async {
    final db = await database;
    return db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> query(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
    String? columns,
  }) async {
    final db = await database;
    return db.query(
      table,
      columns: columns != null ? columns.split(',').map((c) => c.trim()).toList() : null,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? args,
  ]) async {
    final db = await database;
    return db.rawQuery(sql, args);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> row,
    String where,
    List<dynamic> whereArgs,
  ) async {
    final db = await database;
    return db.update(table, row, where: where, whereArgs: whereArgs);
  }

  Future<int> delete(
    String table,
    String where,
    List<dynamic> whereArgs,
  ) async {
    final db = await database;
    return db.delete(table, where: where, whereArgs: whereArgs);
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action);
  }

  Future<int> rawUpdate(String sql, [List<dynamic>? args]) async {
    final db = await database;
    return db.rawUpdate(sql, args);
  }
}

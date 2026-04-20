import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../data/models/bill.dart';
import '../../data/models/email_data.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/models/app_configuration.dart';
import '../../data/models/server_config.dart';

/// Singleton low-level SQLite helper built on top of `sqflite`.
///
/// Owns the full database schema (currently version 14) and exposes raw CRUD
/// methods for all four tables: `bills`, `rentors`, `payments`, and
/// `email_data`.  Higher-level helpers (`BillsHelper`, `PaymentsHelper`, etc.)
/// delegate here for all local-DB operations.
///
/// **Platform bootstrapping** (must happen in `main` before any DB access):
/// - Web   → `databaseFactory = databaseFactoryFfiWeb`
/// - Desktop → `sqfliteFfiInit(); databaseFactory = databaseFactoryFfi`
/// - Mobile  → nothing (default factory is fine)
class DatabaseHelper {
  //region Initialization
  static const _databaseName = 'utility_manager.db';

  /// Current schema version.  Bump this and add a corresponding
  /// `if (oldVersion < N)` block in [_onUpgrade] for every schema change.
  static const _databaseVersion = 16;

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  static Database? _database;

  DatabaseHelper._internal();

  /// Lazily initialises and caches the database connection.
  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }
  //endregion

  //region Schema Lifecycle
  /// Opens the database using the active [databaseFactory].
  ///
  /// **Platform setup (must run before first access):**
  /// - **Web:** `databaseFactory = databaseFactoryFfiWeb` (see sqflite_common_ffi_web).
  /// - **Desktop:** `sqfliteFfiInit()` then `databaseFactory = databaseFactoryFfi`.
  /// - **Mobile (iOS/Android):** use default factory (do not set FFI in `main`).
  ///
  /// Web persists under a logical name only (IndexedDB); mobile/desktop use
  /// [getDatabasesPath] + file name.
  Future<Database> _initDatabase() async {
    final path = kIsWeb
        ? _databaseName
        : join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        // SQLite does not enforce FKs unless this pragma is enabled per connection.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Called once when the database file is first created.  Builds the full
  /// schema in a single pass (equivalent to the latest migration state).
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        billId TEXT NOT NULL,
        company TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        dueDate TEXT NOT NULL,
        status TEXT NOT NULL,
        notes TEXT,
        amountPaid REAL
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_bills_billId_unique ON bills (billId)
    ''');

    await db.execute('''
      CREATE TABLE rentors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rentorId TEXT NOT NULL,
        name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        defaultPercentage REAL NOT NULL,
        billPercentages TEXT,
        excludedBillTypes TEXT,
        lastPaymentDate TEXT
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_rentors_rentorId_unique ON rentors (rentorId)
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        paymentId TEXT NOT NULL,
        rentorId TEXT,
        amountPaid REAL NOT NULL,
        paymentDate TEXT NOT NULL,
        FOREIGN KEY (rentorId) REFERENCES rentors (rentorId)
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_payments_paymentId_unique ON payments (paymentId)
    ''');

    await db.execute('''
      CREATE TABLE payment_bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        paymentId TEXT NOT NULL,
        billId TEXT NOT NULL,
        applied INTEGER NOT NULL DEFAULT 0,
        appliedAmount REAL,
        FOREIGN KEY (paymentId) REFERENCES payments (paymentId) ON DELETE CASCADE,
        FOREIGN KEY (billId) REFERENCES bills (billId) ON DELETE CASCADE,
        UNIQUE (paymentId, billId)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_payment_bills_paymentId ON payment_bills (paymentId)
    ''');

    await db.execute('''
      CREATE INDEX idx_payment_bills_billId ON payment_bills (billId)
    ''');

    await db.execute('''
      CREATE TABLE email_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        emailDataId TEXT NOT NULL,
        emailSubject TEXT NOT NULL,
        emailBody TEXT NOT NULL,
        emailId INTEGER,
        billId TEXT,
        paymentId TEXT,
        processed INTEGER NOT NULL,
        FOREIGN KEY (billId) REFERENCES bills (billId) ON DELETE CASCADE,
        FOREIGN KEY (paymentId) REFERENCES payments (paymentId) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX idx_email_data_emailDataId_unique ON email_data (emailDataId)
    ''');

    await db.execute('''
      CREATE INDEX idx_email_data_paymentId ON email_data (paymentId)
    ''');

    await db.execute('''
      CREATE TABLE configuration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        configId TEXT NOT NULL,
        emailAddress TEXT,
        emailPassword TEXT,
        emailImapServer TEXT,
        emailImapPort INTEGER,
        emailImapSecure INTEGER,
        emailEarliestDate TEXT,
        emailSyncDelayDuration INTEGER,
        emailSyncInterval INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE app_configuration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        configId TEXT,
        baseWebAPI TEXT
      )
    ''');
  }

  /// Applies incremental migrations for every schema version between
  /// [oldVersion] and [newVersion].  Each guard (`if (oldVersion < N)`) is
  /// idempotent so that interrupted upgrades can be safely replayed.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE bills ADD COLUMN type TEXT NOT NULL');

      await db.execute('ALTER TABLE rentors DROP COLUMN percentage');
      await db.execute(
        'ALTER TABLE rentors ADD COLUMN defaultPercentage REAL NOT NULL',
      );
      await db.execute('ALTER TABLE rentors ADD COLUMN billPercentages TEXT');
      await db.execute('ALTER TABLE rentors ADD COLUMN amountPaid REAL');
      await db.execute('ALTER TABLE rentors ADD COLUMN lastPaymentDate TEXT');
    }

    if (oldVersion < 3) {
      // Create a temporary table with the new schema
      await _migrateTable(
        db,
        oldTableName: 'email_data',
        newTableName: 'email_data_new',
        createTableSql: '''
          CREATE TABLE email_data_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            emailSubject TEXT NOT NULL,
            emailBody TEXT NOT NULL,
            emailId INTEGER,
            billId INTEGER,
            processed INTEGER NOT NULL,
            FOREIGN KEY (billId) REFERENCES bills (id) ON DELETE CASCADE
          )
        ''',
        insertSelectSql: '''
          INSERT INTO email_data_new (id, emailSubject, emailBody, emailId, billId, processed)
          SELECT id, emailSubject, emailBody, emailId, 
                 CASE WHEN billId IS NULL THEN NULL ELSE CAST(billId AS INTEGER) END,
                 processed
          FROM email_data
        ''',
      );
    }

    if (oldVersion < 4) {
      // Clean up leftovers from interrupted upgrades.
      await _dropTablesIfExist(db, [
        'email_data_new',
        'email_data_stage',
        'payments_new',
      ]);

      // Step 1: detach legacy/broken FK from email_data before touching bills.
      await _migrateTable(
        db,
        oldTableName: 'email_data',
        newTableName: 'email_data_stage',
        createTableSql: '''
          CREATE TABLE email_data_stage (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            emailSubject TEXT NOT NULL,
            emailBody TEXT NOT NULL,
            emailId INTEGER,
            billId TEXT,
            processed INTEGER NOT NULL
          )
        ''',
        insertSelectSql: '''
          INSERT INTO email_data_stage (id, emailSubject, emailBody, emailId, billId, processed)
          SELECT
            e.id,
            e.emailSubject,
            e.emailBody,
            e.emailId,
            CASE
              WHEN e.billId IS NULL THEN NULL
              WHEN EXISTS (
                SELECT 1 FROM bills b WHERE b.billId = CAST(e.billId AS TEXT)
              ) THEN CAST(e.billId AS TEXT)
              WHEN EXISTS (
                SELECT 1 FROM bills b WHERE b.id = CAST(e.billId AS INTEGER)
              ) THEN (
                SELECT b.billId FROM bills b WHERE b.id = CAST(e.billId AS INTEGER)
              )
              ELSE NULL
            END,
            e.processed
          FROM email_data e
        ''',
      );

      // Step 2: normalize bills.billId and enforce uniqueness for FK parent key.
      await _backfillAndDeduplicateId(
        db,
        table: 'bills',
        column: 'billId',
        fillExpression: "'legacy-' || id",
      );

      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_bills_billId_unique ON bills (billId)
      ''');

      // Step 3: recreate email_data with final FK constraint.
      await _migrateTable(
        db,
        oldTableName: 'email_data',
        newTableName: 'email_data_new',
        createTableSql: '''
          CREATE TABLE email_data_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            emailSubject TEXT NOT NULL,
            emailBody TEXT NOT NULL,
            emailId INTEGER,
            billId TEXT,
            processed INTEGER NOT NULL,
            FOREIGN KEY (billId) REFERENCES bills (billId) ON DELETE CASCADE
          )
        ''',
        insertSelectSql: '''
          INSERT INTO email_data_new (id, emailSubject, emailBody, emailId, billId, processed)
          SELECT
            e.id,
            e.emailSubject,
            e.emailBody,
            e.emailId,
            CASE
              WHEN e.billId IS NULL THEN NULL
              WHEN EXISTS (
                SELECT 1 FROM bills b WHERE b.billId = e.billId
              ) THEN e.billId
              ELSE NULL
            END,
            e.processed
          FROM email_data e
        ''',
      );

      // Step 4: move payments to logical billId FK with ON DELETE SET NULL.
      await _rebuildPaymentsTable(
        db,
        paymentIdSelectExpression: 'NULL',
        billIdSelectExpression: '''
          CASE
            WHEN p.billId IS NULL THEN NULL
            WHEN EXISTS (
              SELECT 1 FROM bills b WHERE b.billId = CAST(p.billId AS TEXT)
            ) THEN CAST(p.billId AS TEXT)
            WHEN EXISTS (
              SELECT 1 FROM bills b WHERE b.id = CAST(p.billId AS INTEGER)
            ) THEN (
              SELECT b.billId FROM bills b WHERE b.id = CAST(p.billId AS INTEGER)
            )
            ELSE NULL
          END
        ''',
        rentorIdType: 'INTEGER',
        rentorForeignKey: 'rentors (id)',
        rentorIdSelectExpression: 'p.rentorId',
      );
    }

    if (oldVersion < 5) {
      await db.execute('ALTER TABLE rentors ADD COLUMN email TEXT');
      await db.execute('ALTER TABLE rentors ADD COLUMN phone TEXT');
    }

    if (oldVersion < 6) {
      await db.execute('ALTER TABLE rentors ADD COLUMN rentorId TEXT');
      await _backfillAndDeduplicateId(
        db,
        table: 'rentors',
        column: 'rentorId',
        fillExpression: "'legacy-' || id",
      );
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_rentors_rentorId_unique ON rentors (rentorId)
      ''');

      await _rebuildPaymentsTable(
        db,
        paymentIdSelectExpression: 'p.paymentId',
        billIdSelectExpression: 'p.billId',
        rentorIdType: 'TEXT',
        rentorForeignKey: 'rentors (rentorId)',
        rentorIdSelectExpression: '''
          CASE
            WHEN EXISTS (
              SELECT 1 FROM rentors r WHERE r.rentorId = CAST(p.rentorId AS TEXT)
            ) THEN CAST(p.rentorId AS TEXT)
            ELSE (
              SELECT r.rentorId FROM rentors r WHERE r.id = CAST(p.rentorId AS INTEGER)
            )
          END
        ''',
      );
    }

    if (oldVersion < 7) {
      await _ensureColumn(db, 'payments', 'paymentId', 'TEXT');
      await _backfillAndDeduplicateId(
        db,
        table: 'payments',
        column: 'paymentId',
        fillExpression: "'legacy-' || id",
      );

      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_paymentId_unique ON payments (paymentId)
      ''');

      await _ensureColumn(db, 'email_data', 'emailDataId', 'TEXT');
      await _backfillAndDeduplicateId(
        db,
        table: 'email_data',
        column: 'emailDataId',
        fillExpression:
            "CASE WHEN emailId IS NOT NULL THEN CAST(emailId AS TEXT) ELSE 'legacy-' || id END",
      );

      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_email_data_emailDataId_unique ON email_data (emailDataId)
      ''');
      await _rebuildEmailDataWithPaymentForeignKey(db);
    }

    if (oldVersion < 8) {
      await _rebuildPaymentsTable(
        db,
        paymentIdSelectExpression: '''
          CASE
            WHEN p.paymentId IS NULL OR TRIM(p.paymentId) = '' THEN 'legacy-' || p.id
            ELSE p.paymentId
          END
        ''',
        billIdSelectExpression: 'p.billId',
        rentorIdType: 'TEXT',
        rentorForeignKey: 'rentors (rentorId)',
        rentorIdSelectExpression: '''
          CASE
            WHEN p.rentorId IS NULL OR TRIM(p.rentorId) = '' THEN NULL
            WHEN EXISTS (
              SELECT 1 FROM rentors r WHERE r.rentorId = p.rentorId
            ) THEN p.rentorId
            ELSE NULL
          END
        ''',
        rentorIdNullable: true,
      );

      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_paymentId_unique ON payments (paymentId)
      ''');
    }

    if (oldVersion < 9) {
      // Create the payment_bills junction table for supporting multiple bills per payment
      await _dropTablesIfExist(db, ['payment_bills']);

      await db.execute('''
        CREATE TABLE payment_bills (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          paymentId TEXT NOT NULL,
          billId TEXT NOT NULL,
          applied INTEGER NOT NULL DEFAULT 0,
          appliedAmount REAL,
          FOREIGN KEY (paymentId) REFERENCES payments (paymentId) ON DELETE CASCADE,
          FOREIGN KEY (billId) REFERENCES bills (billId) ON DELETE CASCADE,
          UNIQUE (paymentId, billId)
        )
      ''');

      await db.execute('''
        CREATE INDEX idx_payment_bills_paymentId ON payment_bills (paymentId)
      ''');

      await db.execute('''
        CREATE INDEX idx_payment_bills_billId ON payment_bills (billId)
      ''');

      // Migrate existing billId values from payments into the junction table
      await db.execute('''
        INSERT INTO payment_bills (paymentId, billId)
        SELECT p.paymentId, p.billId
        FROM payments p
        WHERE p.billId IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM payment_bills pb
            WHERE pb.paymentId = p.paymentId AND pb.billId = p.billId
          )
      ''');

      // Drop the now-redundant billId column from payments by rebuilding the table
      await _dropTablesIfExist(db, ['payments_new']);

      await _migrateTableWithIndex(
        db,
        oldTableName: 'payments',
        newTableName: 'payments_new',
        createTableSql: '''
          CREATE TABLE payments_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            paymentId TEXT NOT NULL,
            rentorId TEXT,
            amountPaid REAL NOT NULL,
            paymentDate TEXT NOT NULL,
            FOREIGN KEY (rentorId) REFERENCES rentors (rentorId)
          )
        ''',
        insertSelectSql: '''
          INSERT INTO payments_new (id, paymentId, rentorId, amountPaid, paymentDate)
          SELECT id, paymentId, rentorId, amountPaid, paymentDate
          FROM payments
        ''',
        indexSql: '''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_paymentId_unique ON payments (paymentId)
        ''',
      );
    }

    if (oldVersion < 10) {
      // Remove derived columns from rentors table: amountPaid and lastPaymentDate
      // These columns can be calculated on-the-fly from the payments table
      await _dropTablesIfExist(db, ['rentors_new']);

      await _migrateTableWithIndex(
        db,
        oldTableName: 'rentors',
        newTableName: 'rentors_new',
        createTableSql: '''
          CREATE TABLE rentors_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rentorId TEXT NOT NULL,
            name TEXT NOT NULL,
            email TEXT,
            phone TEXT,
            defaultPercentage REAL NOT NULL,
            billPercentages TEXT
          )
        ''',
        insertSelectSql: '''
          INSERT INTO rentors_new (id, rentorId, name, email, phone, defaultPercentage, billPercentages)
          SELECT id, rentorId, name, email, phone, defaultPercentage, billPercentages
          FROM rentors
        ''',
        indexSql: '''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_rentors_rentorId_unique ON rentors (rentorId)
        ''',
      );
    }

    if (oldVersion < 11) {
      await _ensureColumn(db, 'rentors', 'lastPaymentDate', 'TEXT');
    }

    if (oldVersion < 12) {
      await _ensureColumn(db, 'bills', 'amountPaid', 'REAL');
    }

    if (oldVersion < 13) {
      await _ensureColumn(db, 'payment_bills', 'applied', 'INTEGER NOT NULL DEFAULT 0');
      await _ensureColumn(db, 'payment_bills', 'appliedAmount', 'REAL');
    }

    if (oldVersion < 14) {
      await _ensureColumn(db, 'rentors', 'excludedBillTypes', 'TEXT');
    }

    if (oldVersion < 15) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS configuration (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          configId TEXT NOT NULL,
          emailAddress TEXT,
          emailPassword TEXT,
          emailImapServer TEXT,
          emailImapPort INTEGER,
          emailImapSecure INTEGER,
          emailEarliestDate TEXT,
          emailSyncDelayDuration INTEGER,
          emailSyncInterval INTEGER
        )
      ''');
    }

    if (oldVersion < 16) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_configuration (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          configId TEXT,
          baseWebAPI TEXT
        )
      ''');
    }
  }
  //endregion

  //region Migration Helpers
  /// Returns `true` if [column] already exists in [table] (checked via
  /// `PRAGMA table_info`).  Used by [_ensureColumn] to avoid duplicate-column
  /// errors on re-run.
  Future<bool> _hasColumn(Database db, String table, String column) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.any((entry) => entry['name'] == column);
  }

  /// Adds [column] to [table] only if it does not already exist, preventing
  /// `ALTER TABLE … ADD COLUMN` failures on repeated upgrade runs.
  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    if (!await _hasColumn(db, table, column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  /// Fills NULL / blank [column] values using [fillExpression], then
  /// disambiguate any remaining duplicates by appending `-<rowid>` to all
  /// non-minimum duplicate rows.  This makes UUID columns safe to index as
  /// `UNIQUE` after the fact.
  Future<void> _backfillAndDeduplicateId(
    Database db, {
    required String table,
    required String column,
    required String fillExpression,
  }) async {
    await db.execute('''
      UPDATE $table
      SET $column = $fillExpression
      WHERE $column IS NULL OR TRIM($column) = ''
    ''');

    await db.execute('''
      UPDATE $table
      SET $column = $column || '-' || id
      WHERE $column IN (
        SELECT $column
        FROM $table
        GROUP BY $column
        HAVING COUNT(*) > 1
      )
        AND id NOT IN (
          SELECT MIN(id)
          FROM $table
          GROUP BY $column
        )
    ''');
  }

  Future<void> _dropTablesIfExist(Database db, List<String> tableNames) async {
    for (final table in tableNames) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  /// Migrates a table by creating a new schema, copying data, and renaming
  /// Pattern: CREATE new_table -> INSERT from old_table -> DROP old_table -> RENAME new_table to old_table
  Future<void> _migrateTable(
    Database db, {
    required String oldTableName,
    required String newTableName,
    required String createTableSql,
    required String insertSelectSql,
  }) async {
    await db.execute(createTableSql);
    await db.execute(insertSelectSql);
    await db.execute('DROP TABLE $oldTableName');
    await db.execute('ALTER TABLE $newTableName RENAME TO $oldTableName');
  }

  /// Migrates a table and recreates an index
  Future<void> _migrateTableWithIndex(
    Database db, {
    required String oldTableName,
    required String newTableName,
    required String createTableSql,
    required String insertSelectSql,
    required String indexSql,
  }) async {
    await _migrateTable(
      db,
      oldTableName: oldTableName,
      newTableName: newTableName,
      createTableSql: createTableSql,
      insertSelectSql: insertSelectSql,
    );
    await db.execute(indexSql);
  }

  // /// Migrates a table and recreates multiple indexes
  // Future<void> _migrateTableWithIndexes(
  //   Database db, {
  //   required String oldTableName,
  //   required String newTableName,
  //   required String createTableSql,
  //   required String insertSelectSql,
  //   required List<String> indexSqls,
  // }) async {
  //   await _migrateTable(
  //     db,
  //     oldTableName: oldTableName,
  //     newTableName: newTableName,
  //     createTableSql: createTableSql,
  //     insertSelectSql: insertSelectSql,
  //   );
  //   for (final indexSql in indexSqls) {
  //     await db.execute(indexSql);
  //   }
  // }

  /// Reconstructs the `payments` table with a new schema by creating a
  /// `payments_new` table, copying data with the provided SQL expression
  /// fragments, and then renaming it back.  Used across several migration
  /// versions where `ALTER TABLE` is insufficient (e.g. changing FK targets or
  /// column nullability).
  Future<void> _rebuildPaymentsTable(
    Database db, {
    required String paymentIdSelectExpression,
    required String billIdSelectExpression,
    required String rentorIdType,
    required String rentorForeignKey,
    required String rentorIdSelectExpression,
    bool rentorIdNullable = false,
  }) async {
    await _dropTablesIfExist(db, ['payments_new']);

    final rentorNotNullConstraint = rentorIdNullable ? '' : ' NOT NULL';

    await db.execute('''
      CREATE TABLE payments_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        paymentId TEXT,
        rentorId $rentorIdType$rentorNotNullConstraint,
        amountPaid REAL NOT NULL,
        paymentDate TEXT NOT NULL,
        FOREIGN KEY (rentorId) REFERENCES $rentorForeignKey
      )
    ''');

    await db.execute('''
      INSERT INTO payments_new (id, paymentId, rentorId, amountPaid, paymentDate)
      SELECT
        p.id,
        $paymentIdSelectExpression,
        $rentorIdSelectExpression,
        p.amountPaid,
        p.paymentDate
      FROM payments p
    ''');

    await db.execute('DROP TABLE payments');
    await db.execute('ALTER TABLE payments_new RENAME TO payments');
  }

  /// Rebuilds the `email_data` table to add a `paymentId` FK column while
  /// preserving all existing data and silently nullifying any references that
  /// no longer resolve to a valid `payments` row.
  Future<void> _rebuildEmailDataWithPaymentForeignKey(Database db) async {
    await db.execute('DROP TABLE IF EXISTS email_data_new');
    await _ensureColumn(db, 'email_data', 'paymentId', 'TEXT');

    await db.execute('''
      CREATE TABLE email_data_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        emailDataId TEXT NOT NULL,
        emailSubject TEXT NOT NULL,
        emailBody TEXT NOT NULL,
        emailId INTEGER,
        billId TEXT,
        paymentId TEXT,
        processed INTEGER NOT NULL,
        FOREIGN KEY (billId) REFERENCES bills (billId) ON DELETE CASCADE,
        FOREIGN KEY (paymentId) REFERENCES payments (paymentId) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      INSERT INTO email_data_new (
        id,
        emailDataId,
        emailSubject,
        emailBody,
        emailId,
        billId,
        paymentId,
        processed
      )
      SELECT
        e.id,
        e.emailDataId,
        e.emailSubject,
        e.emailBody,
        e.emailId,
        CASE
          WHEN e.billId IS NULL THEN NULL
          WHEN EXISTS (
            SELECT 1 FROM bills b WHERE b.billId = e.billId
          ) THEN e.billId
          ELSE NULL
        END,
        CASE
          WHEN e.paymentId IS NULL OR TRIM(e.paymentId) = '' THEN NULL
          WHEN EXISTS (
            SELECT 1 FROM payments p WHERE p.paymentId = e.paymentId
          ) THEN e.paymentId
          ELSE NULL
        END,
        e.processed
      FROM email_data e
    ''');

    await db.execute('DROP TABLE email_data');
    await db.execute('ALTER TABLE email_data_new RENAME TO email_data');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_email_data_emailDataId_unique ON email_data (emailDataId)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_email_data_paymentId ON email_data (paymentId)
    ''');
  }

  /// Converts the read-only [QueryRow] maps returned by sqflite into plain,
  /// mutable [Map<String, Object?>] instances so that hydration methods can
  /// attach extra keys (e.g. `billIds`) without hitting an [UnsupportedError].
  List<Map<String, Object?>> _toMutableRows(List<Map<String, Object?>> rows) =>
      rows.map((r) => Map<String, Object?>.from(r)).toList();

  /// Builds a SQL query for payment with optional rentor include
  String _buildPaymentQuery({required bool includeRentor, List<String>? ids}) {
    if (!includeRentor) {
      return "SELECT p.* FROM payments p";
    }

    final selects = <String>[
      'p.id',
      'p.paymentId',
      'p.rentorId',
      'p.amountPaid',
      'p.paymentDate',
      'r.id AS r_id',
      'r.rentorId AS r_rentorId',
      'r.name AS r_name',
      'r.email AS r_email',
      'r.phone AS r_phone',
      'r.defaultPercentage AS r_defaultPercentage',
      'r.billPercentages AS r_billPercentages',
      'r.excludedBillTypes AS r_excludedBillTypes',
      'r.lastPaymentDate AS r_lastPaymentDate',
    ];

    return '''
      SELECT ${selects.join(', ')}
      FROM payments p
      LEFT JOIN rentors r ON r.rentorId = p.rentorId
      ${ids != null && ids.isNotEmpty ? 'WHERE p.paymentId IN (${ids.map((_) => '?').join(', ')})' : ''}
    ''';
  }

  /// Hydrates bill IDs into payment result from junction table
  Future<void> _hydrateBillIds(
    Database db, {
    required String paymentId,
    required Map<String, Object?> result,
    required bool includeBill,
    List<Map<String, dynamic>>? billRows,
  }) async {
    if (includeBill && billRows != null) {
      final billIds = billRows
          .map((row) => row['b_billId']?.toString())
          .whereType<String>()
          .toList();
      result['billIds'] = billIds;
    } else {
      final billIdResults = await db.query(
        'payment_bills',
        where: 'paymentId = ?',
        whereArgs: [paymentId],
      );

      if (billIdResults.isNotEmpty) {
        final billIds = billIdResults
            .map((row) => row['billId'] as String)
            .toList();
        result['billIds'] = billIds;
      }
    }
  }

  /// Hydrates bill IDs into multiple payment results
  Future<void> _hydrateMultipleBillIds(
    Database db, {
    required List<Map<String, Object?>> results,
    required bool includeBill,
    Map<String, List<Map<String, dynamic>>>? billsResult,
  }) async {
    if (results.isEmpty) return;

    final paymentIds = results
        .map((row) => row['paymentId']?.toString())
        .whereType<String>()
        .toList();

    if (paymentIds.isEmpty) return;

    if (includeBill && billsResult != null) {
      for (final result in results) {
        final pId = result['paymentId']?.toString();
        if (pId == null || pId.isEmpty) continue;
        final billIds = billsResult[pId]
                ?.map((row) => row['b_billId']?.toString())
                .whereType<String>()
                .toList() ??
            [];
        result['billIds'] = billIds;
      }
    } else {
      final placeholders = paymentIds.map((_) => '?').join(', ');
      final billIdsResults = await db.rawQuery(
        'SELECT paymentId, billId FROM payment_bills WHERE paymentId IN ($placeholders)',
        paymentIds,
      );

      if (billIdsResults.isNotEmpty) {
        for (final result in results) {
          final pId = result['paymentId']?.toString();
          if (pId == null || pId.isEmpty) continue;
          final billIds = billIdsResults
              .where((row) => row['paymentId'] != null && row['paymentId']!.toString() == pId)
              .map((row) => row['billId'] as String)
              .toList();
          result['billIds'] = billIds;
        }
      }
    }
  }

  /// Inserts bill IDs into the payment_bills junction table
  Future<void> _insertPaymentBillIds(
    Database db, {
    required String paymentId,
    required List<String>? billIds,
  }) async {
    if (billIds != null && billIds.isNotEmpty) {
      for (final billId in billIds) {
        await db.insert(
          'payment_bills',
          {'paymentId': paymentId, 'billId': billId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
  }

  /// Builds SQL query for email data with optional bill and payment includes
  String _buildEmailDataQuery({
    required bool includeBill,
    required bool includePayment,
    String whereClause = '',
  }) {
    final selects = <String>[
      'e.id',
      'e.emailDataId',
      'e.emailSubject',
      'e.emailBody',
      'e.emailId',
      'e.billId',
      'e.paymentId',
      'e.processed',
    ];
    final joins = <String>[];

    if (includeBill) {
      selects.addAll([
        'b.id AS b_id',
        'b.billId AS b_billId',
        'b.company AS b_company',
        'b.type AS b_type',
        'b.amount AS b_amount',
        'b.dueDate AS b_dueDate',
        'b.status AS b_status',
        'b.notes AS b_notes',
        'b.amountPaid AS b_amountPaid',
      ]);
      joins.add('LEFT JOIN bills b ON b.billId = e.billId');
    }

    if (includePayment) {
      selects.addAll([
        'p.id AS p_id',
        'p.paymentId AS p_paymentId',
        'p.rentorId AS p_rentorId',
        'p.amountPaid AS p_amountPaid',
        'p.paymentDate AS p_paymentDate',
      ]);
      joins.add('LEFT JOIN payments p ON p.paymentId = e.paymentId');
    }

    return '''
      SELECT ${selects.join(', ')}
      FROM email_data e
      ${joins.join(' ')}
      $whereClause
    '''.trim();
  }
  //endregion

  //region CRUD Operations
  //region Bill
  /// Inserts [bill] into the `bills` table and returns the new row id.
  Future<int> createBill(Bill bill) async {
    final db = await database;
    return await db.insert('bills', bill.toJson());
  }

  /// Returns the [Bill] identified by [billId], or `null` if not found.
  Future<Bill?> readBill(String billId) async {
    final db = await database;
    final result = await db.query(
      'bills',
      where: 'billId = ?',
      whereArgs: [billId],
    );

    if (result.isEmpty) {
      return null;
    }

    return Bill.fromJson(result.first);
  }

  /// Returns all bills in the `bills` table.
  Future<List<Bill>> readAllBills() async {
    final db = await database;
    final result = await db.query('bills');
    return result.map((map) => Bill.fromJson(map)).toList();
  }

  /// Returns bills matching [status] (case-insensitive).  Pass [ids] to further
  /// restrict results to a specific set of `billId` values.
  Future<List<Bill>> readBillsByStatus(String status, {List<String>? ids}) async {
    final db = await database;
    String placeholders = ids != null && ids.isNotEmpty ? ids.map((_) => '?').join(', ') : '';
    final result = await db.query(
      'bills',
      where: placeholders.isEmpty ? 'status = ?' : 'status = ? AND billId IN ($placeholders)',
      whereArgs: [status.toLowerCase(), ...(ids != null && ids.isNotEmpty ? ids : [])],
    );

    return result.map((map) => Bill.fromJson(map)).toList();
  }

  /// Updates the row matching `bill.billId` and returns the number of affected rows.
  Future<int> updateBill(Bill bill) async {
    final db = await database;
    return await db.update(
      'bills',
      bill.toJson(),
      where: 'billId = ?',
      whereArgs: [bill.billId],
    );
  }

  /// Deletes the bill identified by [id] and returns the number of deleted rows.
  Future<int> deleteBill(String id) async {
    final db = await database;
    return await db.delete('bills', where: 'billId = ?', whereArgs: [id]);
  }

  Future<int> deleteAllBills() async {
    final db = await database;
    return await db.delete('bills');
  }
  //endregion

  //region Rentor
  /// Inserts [rentor] into the `rentors` table and returns the new row id.
  Future<int> createRentor(Rentor rentor) async {
    final db = await database;
    return await db.insert('rentors', rentor.toDbJson());
  }

  /// Returns the [Rentor] identified by [id] (`rentorId`), or `null` if not found.
  Future<Rentor?> readRentor(String id) async {
    final db = await database;
    final result = await db.query(
      'rentors',
      where: 'rentorId = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) {
      return null;
    }

    return Rentor.fromJson(result.first);
  }

  /// Returns all rentors in the `rentors` table.
  Future<List<Rentor>> readAllRentors() async {
    final db = await database;
    final result = await db.query('rentors');
    return result.map((map) => Rentor.fromJson(map)).toList();
  }

  /// Updates the rentor matching `rentor.rentorId` and returns affected row count.
  Future<int> updateRentor(Rentor rentor) async {
    final db = await database;
    return await db.update(
      'rentors',
      rentor.toDbJson(),
      where: 'rentorId = ?',
      whereArgs: [rentor.rentorId],
    );
  }

  /// Deletes the rentor identified by [id] (`rentorId`) and returns deleted row count.
  Future<int> deleteRentor(String id) async {
    final db = await database;
    return await db.delete('rentors', where: 'rentorId = ?', whereArgs: [id]);
  }

  Future<int> deleteAllRentors() async {
    final db = await database;
    return await db.delete('rentors');
  }
  //endregion

  //region Payment
  /// Inserts [payment] into the `payments` table and writes all associated
  /// bill links into `payment_bills`.  Returns the new payment row id.
  Future<int> createPayment(Payment payment) async {
    final db = await database;
    final paymentData = payment.toJson();
    final result = await db.insert('payments', paymentData);
    await _insertPaymentBillIds(db, paymentId: payment.paymentId!, billIds: payment.billIds);
    return result;
  }

  /// Retrieves the payment identified by [paymentId].
  ///
  /// Pass `include: {'bill': true}` and/or `include: {'rentor': true}` to
  /// eagerly join associated records.  Returns `null` if not found.
  Future<Payment?> readPayment(String paymentId, {Map<String, bool>? include}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includeRentor = include?['rentor'] == true;

    List<Map<String, Object?>> result;
    List<Map<String, dynamic>> billsResult = [];

    if (!includeRentor) {
      result = _toMutableRows(await db.query(
        'payments',
        where: 'paymentId = ?',
        whereArgs: [paymentId],
      ));
    } else {
      final query = _buildPaymentQuery(includeRentor: true);
      result = _toMutableRows(await db.rawQuery('$query WHERE p.paymentId = ?', [paymentId]));
    }

    if (result.isEmpty) {
      return null;
    }

    if (includeBill) {
      billsResult = await db.rawQuery('''
        SELECT b.id AS b_id,
               b.billId AS b_billId,
               b.company AS b_company,
               b.type AS b_type,
               b.amount AS b_amount,
               b.dueDate AS b_dueDate,
               b.status AS b_status,
               b.notes AS b_notes,
               b.amountPaid AS b_amountPaid
        FROM payment_bills pb
        JOIN bills b ON b.billId = pb.billId
        WHERE pb.paymentId = ?
      ''', [paymentId]);
    }

    await _hydrateBillIds(
      db,
      paymentId: paymentId,
      result: result.first,
      includeBill: includeBill,
      billRows: includeBill ? billsResult : null,
    );

    return Payment.fromJson(Map<String, dynamic>.from(result.first), billRows: billsResult);
  }

  /// Returns all payments, optionally filtered to [ids] and with related
  /// bills/rentors eagerly loaded based on the [include] flags.
  Future<List<Payment>> readAllPayments({Map<String, bool>? include, List<String>? ids}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includeRentor = include?['rentor'] == true;

    List<Map<String, Object?>> result;
    Map<String, List<Map<String, dynamic>>> billsResult = {};

    if (!includeRentor) {
      String placeholders = ids != null && ids.isNotEmpty ? ids.map((_) => '?').join(', ') : '';
      result = _toMutableRows(placeholders.isEmpty ? await db.query('payments') : await db.query('payments', where: 'paymentId IN ($placeholders)', whereArgs: ids));
    } else {
      final query = _buildPaymentQuery(includeRentor: true, ids: ids);
      result = _toMutableRows(await db.rawQuery(query));
    }

    if (result.isEmpty) {
      return [];
    }

    if (includeBill) {
      final paymentIds = result
          .map((row) => row['paymentId']?.toString())
          .whereType<String>()
          .toList();

      if (paymentIds.isNotEmpty) {
        final placeholders = paymentIds.map((_) => '?').join(', ');
        final rawBillRows = await db.rawQuery('''
          SELECT pb.paymentId AS pb_paymentId,
                 b.id AS b_id,
                 b.billId AS b_billId,
                 b.company AS b_company,
                 b.type AS b_type,
                 b.amount AS b_amount,
                 b.dueDate AS b_dueDate,
                 b.status AS b_status,
                 b.notes AS b_notes,
                 b.amountPaid AS b_amountPaid
          FROM payment_bills pb
          JOIN bills b ON b.billId = pb.billId
          WHERE pb.paymentId IN ($placeholders)
        ''', paymentIds);

        for (String paymentId in paymentIds) {
          billsResult[paymentId] = rawBillRows
              .where((row) => row['pb_paymentId'] != null && row['pb_paymentId']!.toString() == paymentId)
              .toList();
        }
      }
    }

    await _hydrateMultipleBillIds(
      db,
      results: result,
      includeBill: includeBill,
      billsResult: includeBill ? billsResult : null,
    );

    return result
        .where((map) => map['paymentId'] != null && map['paymentId']!.toString().isNotEmpty)
        .map((map) => Payment.fromJson(map, billRows: billsResult[map['paymentId']!.toString()]))
        .toList();
  }

  /// Updates the `payments` row matching `payment.paymentId` and performs an
  /// incremental diff on `payment_bills`: rows for removed bills are deleted,
  /// rows for newly added bills are inserted (preserving `applied` state for
  /// unchanged links).  Returns the number of updated `payments` rows.
  Future<int> updatePayment(Payment payment) async {
    final db = await database;
    final paymentData = payment.toJson();

    final result = await db.update(
      'payments',
      paymentData,
      where: 'paymentId = ?',
      whereArgs: [payment.paymentId!],
    );

    // Incremental diff on payment_bills: preserve existing rows (and their applied state),
    // remove only bills that were unassigned, add only newly assigned bills.
    final existingRows = await db.query(
      'payment_bills',
      columns: ['billId'],
      where: 'paymentId = ?',
      whereArgs: [payment.paymentId],
    );
    final existingBillIds = existingRows.map((r) => r['billId'] as String).toSet();
    final newBillIds = (payment.billIds ?? []).toSet();

    final toRemove = existingBillIds.difference(newBillIds);
    for (final billId in toRemove) {
      await db.delete(
        'payment_bills',
        where: 'paymentId = ? AND billId = ?',
        whereArgs: [payment.paymentId, billId],
      );
    }

    final toAdd = newBillIds.difference(existingBillIds);
    for (final billId in toAdd) {
      await db.insert(
        'payment_bills',
        {'paymentId': payment.paymentId, 'billId': billId, 'applied': 0},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    return result;
  }

  /// Deletes the payment identified by [id] (`paymentId`).  Cascades to
  /// `payment_bills` via the DB-level ON DELETE CASCADE constraint.
  Future<int> deletePayment(String id) async {
    final db = await database;
    return await db.delete('payments', where: 'paymentId = ?', whereArgs: [id]);
  }

  Future<int> deleteAllPayments() async {
    final db = await database;
    return await db.delete('payments');
  }

  /// Marks the `payment_bills` junction row as applied and records the exact
  /// [appliedAmount] credited toward [billId] from [paymentId].
  Future<void> markPaymentBillApplied(String paymentId, String billId, double appliedAmount) async {
    final db = await database;
    await db.update(
      'payment_bills',
      {'applied': 1, 'appliedAmount': appliedAmount},
      where: 'paymentId = ? AND billId = ?',
      whereArgs: [paymentId, billId],
    );
  }

  /// Returns the previously recorded `appliedAmount` for the ([paymentId],
  /// [billId]) pair if the junction row is marked `applied = 1`, otherwise
  /// returns `null`.
  Future<double?> getPaymentBillAppliedAmount(String paymentId, String billId) async {
    final db = await database;
    final result = await db.query(
      'payment_bills',
      columns: ['appliedAmount'],
      where: 'paymentId = ? AND billId = ? AND applied = 1',
      whereArgs: [paymentId, billId],
    );
    if (result.isEmpty) return null;
    return (result.first['appliedAmount'] as num?)?.toDouble();
  }
  //endregionZ

  //region Email
  /// Inserts [emailData] into the `email_data` table and returns the new row id.
  Future<int> createEmailData(EmailData emailData) async {
    final db = await database;
    return await db.insert('email_data', emailData.toJson());
  }

  /// Returns the [EmailData] record whose `emailId` matches [emailId], or
  /// `null` if not found.  Pass [include] flags to join `bill` and/or
  /// `payment`.
  Future<EmailData?> readEmail(String emailId, {Map<String, bool>? include, bool queryByEmailId = false}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includePayment = include?['payment'] == true;

    List<Map<String, Object?>> result;
    if (!includeBill && !includePayment) {
      result = await db.query(
        'email_data',
        where: queryByEmailId ? 'emailId = ?' : 'emailDataId = ?',
        whereArgs: [emailId],
      );
    } else {
      final query = _buildEmailDataQuery(
        includeBill: includeBill,
        includePayment: includePayment,
        whereClause: 'WHERE ${(queryByEmailId ? 'e.emailId = ?' : 'e.emailDataId = ?')}',
      );
      result = await db.rawQuery(query, [emailId]);
    }

    if (result.isEmpty) {
      return null;
    }

    return EmailData.fromJson(result.first);
  }

  /// Returns all email records, optionally with related bill/payment data joined.
  Future<List<EmailData>> readEmails({Map<String, bool>? include}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includePayment = include?['payment'] == true;

    if (!includeBill && !includePayment) {
      final result = await db.query('email_data');
      return result.map((map) => EmailData.fromJson(map)).toList();
    }

    final query = _buildEmailDataQuery(
      includeBill: includeBill,
      includePayment: includePayment,
    );

    final result = await db.rawQuery(query);
    return result.map((map) => EmailData.fromJson(map)).toList();
  }

  /// Returns only email records where `processed = 0`.
  Future<List<EmailData>> readUnprocessedEmails({Map<String, bool>? include}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includePayment = include?['payment'] == true;

    if (!includeBill && !includePayment) {
      final result = await db.query(
        'email_data',
        where: 'processed = ?',
        whereArgs: [0],
      );
      return result.map((map) => EmailData.fromJson(map)).toList();
    }

    final query = _buildEmailDataQuery(
      includeBill: includeBill,
      includePayment: includePayment,
      whereClause: 'WHERE e.processed = 0',
    );

    final result = await db.rawQuery(query);
    return result.map((map) => EmailData.fromJson(map)).toList();
  }

  /// Returns only email records where `processed = 1`.
  Future<List<EmailData>> readProcessedEmails({Map<String, bool>? include}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includePayment = include?['payment'] == true;

    if (!includeBill && !includePayment) {
      final result = await db.query(
        'email_data',
        where: 'processed = ?',
        whereArgs: [1],
      );
      return result.map((map) => EmailData.fromJson(map)).toList();
    }

    final query = _buildEmailDataQuery(
      includeBill: includeBill,
      includePayment: includePayment,
      whereClause: 'WHERE e.processed = 1',
    );

    final result = await db.rawQuery(query);
    return result.map((map) => EmailData.fromJson(map)).toList();
  }

  /// Updates the `email_data` row matching `emaildata.emailDataId`.
  ///
  /// The `id` field is stripped before the update to avoid overwriting the
  /// auto-increment primary key.
  Future<int> updateEmailData(EmailData emaildata) async {
    final db = await database;

    // Make a copy of the data and remove the 'id' field
    final data = Map<String, dynamic>.from(emaildata.toJson());
    data.remove('id');

    return await db.update(
      'email_data',
      data,
      where: 'emailDataId = ?',
      whereArgs: [emaildata.emailDataId!],
    );
  }

  /// Deletes the email record identified by [id] (`emailDataId`).
  Future<int> deleteEmailData(String id) async {
    final db = await database;
    return await db.delete('email_data', where: 'emailDataId = ?', whereArgs: [id]);
  }

  Future<int> deleteAllEmailData() async {
    final db = await database;
    return await db.delete('email_data');
  }
  //endregion
  //endregion

  //region App Configuration
  /// Clears the `app_configuration` table and inserts [config] as the single
  /// row. Returns the new row id.
  Future<int> saveAppConfiguration(AppConfiguration config) async {
    final db = await database;
    await db.delete('app_configuration');
    return await db.insert('app_configuration', config.toJson());
  }

  /// Returns the stored [AppConfiguration], or `null` if none exists.
  Future<AppConfiguration?> readAppConfiguration() async {
    final db = await database;
    final result = await db.query('app_configuration', limit: 1);
    if (result.isEmpty) return null;
    return AppConfiguration.fromJson(result.first);
  }

  /// Deletes all rows from `app_configuration`. Returns deleted row count.
  Future<int> deleteAppConfiguration() async {
    final db = await database;
    return await db.delete('app_configuration');
  }
  //endregion

  //region Configuration
  /// Inserts [config] into the `configuration` table, replacing any existing
  /// row first (the table holds at most one configuration at a time).
  /// Returns the new row id.
  Future<int> createConfiguration(ServerConfig config) async {
    final db = await database;
    await db.delete('configuration');
    return await db.insert('configuration', config.toJson());
  }

  /// Returns the stored [ServerConfig], or `null` if none exists.
  Future<ServerConfig?> readConfiguration() async {
    final db = await database;
    final result = await db.query('configuration', limit: 1);
    if (result.isEmpty) return null;
    return ServerConfig.fromJson(result.first);
  }

  /// Updates the `configuration` row matching `config.configId`.
  /// Returns the number of affected rows.
  Future<int> updateConfiguration(ServerConfig config) async {
    final db = await database;
    return await db.update(
      'configuration',
      config.toJson(),
      where: 'configId = ?',
      whereArgs: [config.configId],
    );
  }

  /// Deletes all rows from the `configuration` table.
  /// Returns the number of deleted rows.
  Future<int> deleteConfiguration() async {
    final db = await database;
    return await db.delete('configuration');
  }
  //endregion

  //region Database Lifecycle
  /// Closes the underlying SQLite connection.  The cached [_database] reference
  /// is **not** cleared, so a subsequent access to [database] will re-open it.
  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
  }
  //endregion
}

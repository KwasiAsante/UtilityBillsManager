import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/email_data.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';

class DatabaseHelper {
  //region Initialization
  static const _databaseName = 'utility_manager.db';

  static const _databaseVersion = 9;

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  static Database? _database;

  DatabaseHelper._internal();

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

  Future<void> _onCreate(Database db, int version) async {
    if (version < 2) {
      await db.execute('''
        CREATE TABLE bills (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          company TEXT NOT NULL,
          amount REAL NOT NULL,
          dueDate TEXT NOT NULL,
          status TEXT NOT NULL,
          notes TEXT
        )
      ''');

      await db.execute('''
        CREATE TABLE rentors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          percentage REAL NOT NULL
        )
      ''');
    } else {
      await db.execute('''
        CREATE TABLE bills (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          billId TEXT NOT NULL,
          company TEXT NOT NULL,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          dueDate TEXT NOT NULL,
          status TEXT NOT NULL,
          notes TEXT
        )
      ''');

      await db.execute('''
        CREATE UNIQUE INDEX idx_bills_billId_unique ON bills (billId)
      ''');

      ///TODO: amountPaid and lastPaymentDate should not be stored in the database as it is derived data that can be calculated from the payments table. We should remove these columns and calculate them on the fly when needed to avoid data inconsistency and simplify the schema.
      await db.execute('''
        CREATE TABLE rentors (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          rentorId TEXT NOT NULL,
          name TEXT NOT NULL,
          email TEXT,
          phone TEXT,
          defaultPercentage REAL NOT NULL,
          billPercentages TEXT,
          amountPaid REAL,
          lastPaymentDate TEXT
        )
      ''');

      await db.execute('''
        CREATE UNIQUE INDEX idx_rentors_rentorId_unique ON rentors (rentorId)
      ''');
    }

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
  }

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
      await db.execute('''
        CREATE TABLE email_data_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          emailSubject TEXT NOT NULL,
          emailBody TEXT NOT NULL,
          emailId INTEGER,
          billId INTEGER,
          processed INTEGER NOT NULL,
          FOREIGN KEY (billId) REFERENCES bills (id) ON DELETE CASCADE
        )
      ''');

      // Copy data from old table to new table
      await db.execute('''
        INSERT INTO email_data_new (id, emailSubject, emailBody, emailId, billId, processed)
        SELECT id, emailSubject, emailBody, emailId, 
               CASE WHEN billId IS NULL THEN NULL ELSE CAST(billId AS INTEGER) END,
               processed
        FROM email_data
      ''');

      // Drop the old table
      await db.execute('DROP TABLE email_data');

      // Rename the new table
      await db.execute('ALTER TABLE email_data_new RENAME TO email_data');
    }

    if (oldVersion < 4) {
      // Clean up leftovers from interrupted upgrades.
      await _dropTablesIfExist(db, [
        'email_data_new',
        'email_data_stage',
        'payments_new',
      ]);

      // Step 1: detach legacy/broken FK from email_data before touching bills.
      await db.execute('''
        CREATE TABLE email_data_stage (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          emailSubject TEXT NOT NULL,
          emailBody TEXT NOT NULL,
          emailId INTEGER,
          billId TEXT,
          processed INTEGER NOT NULL
        )
      ''');

      await db.execute('''
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
      ''');

      await db.execute('DROP TABLE email_data');
      await db.execute('ALTER TABLE email_data_stage RENAME TO email_data');

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
      await db.execute('''
        CREATE TABLE email_data_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          emailSubject TEXT NOT NULL,
          emailBody TEXT NOT NULL,
          emailId INTEGER,
          billId TEXT,
          processed INTEGER NOT NULL,
          FOREIGN KEY (billId) REFERENCES bills (billId) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
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
      ''');

      await db.execute('DROP TABLE email_data');
      await db.execute('ALTER TABLE email_data_new RENAME TO email_data');

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

      await db.execute('''
        CREATE TABLE payments_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          paymentId TEXT NOT NULL,
          rentorId TEXT,
          amountPaid REAL NOT NULL,
          paymentDate TEXT NOT NULL,
          FOREIGN KEY (rentorId) REFERENCES rentors (rentorId)
        )
      ''');

      await db.execute('''
        INSERT INTO payments_new (id, paymentId, rentorId, amountPaid, paymentDate)
        SELECT id, paymentId, rentorId, amountPaid, paymentDate
        FROM payments
      ''');

      await db.execute('DROP TABLE payments');
      await db.execute('ALTER TABLE payments_new RENAME TO payments');

      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_paymentId_unique ON payments (paymentId)
      ''');
    }
  }
  //endregion

  //region Migration Helpers
  Future<bool> _hasColumn(Database db, String table, String column) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    return columns.any((entry) => entry['name'] == column);
  }

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
  //endregion

  //region CRUD Operations
  //region Bill
  // Insert a Bill
  Future<int> createBill(Bill bill) async {
    final db = await database;
    return await db.insert('bills', bill.toJson());
  }

  // Retrieve Bills
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

  // Retrieve all Bills
  Future<List<Bill>> readAllBills() async {
    final db = await database;
    final result = await db.query('bills');
    return result.map((map) => Bill.fromJson(map)).toList();
  }

  // Retrieve all Bills
  Future<List<Bill>> readBillsByStatus(String status) async {
    final db = await database;
    final result = await db.query(
      'bills',
      where: 'status = ?',
      whereArgs: [status.toLowerCase()],
    );
    return result.map((map) => Bill.fromJson(map)).toList();
  }

  // Update a Bill
  Future<int> updateBill(Bill bill) async {
    final db = await database;
    return await db.update(
      'bills',
      bill.toJson(),
      where: 'billId = ?',
      whereArgs: [bill.billId],
    );
  }

  // Delete a Bill
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
  // Insert a Rentor
  Future<int> createRentor(Rentor rentor) async {
    final db = await database;
    return await db.insert('rentors', rentor.toDbJson());
  }

  // Retrieve a Rentor by id
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

  // Retrieve all Rentors
  Future<List<Rentor>> readAllRentors() async {
    final db = await database;
    final result = await db.query('rentors');
    return result.map((map) => Rentor.fromJson(map)).toList();
  }

  // Update a Rentor
  Future<int> updateRentor(Rentor rentor) async {
    final db = await database;
    return await db.update(
      'rentors',
      rentor.toDbJson(),
      where: 'rentorId = ?',
      whereArgs: [rentor.rentorId],
    );
  }

  // Delete a Rentor
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
  // Insert a Payment
  Future<int> createPayment(Payment payment) async {
    final db = await database;

    // Prepare payment data without billIds for insert
    final paymentData = payment.toJson();

    final result = await db.insert('payments', paymentData);

    // Insert billIds into the junction table
    if (payment.billIds != null && payment.billIds!.isNotEmpty) {
      for (final billId in payment.billIds!) {
        await db.insert(
          'payment_bills',
          {'paymentId': payment.paymentId, 'billId': billId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    return result;
  }

  // Retrieve a Payment by paymentId
  Future<Payment?> readPayment(String paymentId, {Map<String, bool>? include}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includeRentor = include?['rentor'] == true;

    List<Map<String, Object?>> result;
    List<Map<String, dynamic>> billsResult = [];

    if (!includeRentor) {
      result = await db.query(
        'payments',
        where: 'paymentId = ?',
        whereArgs: [paymentId],
      );
    }
    else {
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
        'r.amountPaid AS r_amountPaid',
        'r.lastPaymentDate AS r_lastPaymentDate',
      ];

      final query = '''
        SELECT ${selects.join(', ')}
        FROM payments p
        LEFT JOIN rentors r ON r.rentorId = p.rentorId
        WHERE p.paymentId = ?
      ''';

      result = await db.rawQuery(query, [paymentId]);
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
               b.notes AS b_notes
        FROM payment_bills pb
        JOIN bills b ON b.billId = pb.billId
        WHERE pb.paymentId = ?
      ''', [paymentId]);

      final billIds = billsResult
          .map((row) => row['b_billId']?.toString())
          .whereType<String>()
          .toList();

      result.first['billIds'] = billIds;
    }
    else {
      // Keep lightweight billId hydration when bill include is false.
      final billIdResults = await db.query(
        'payment_bills',
        where: 'paymentId = ?',
        whereArgs: [paymentId],
      );

      if (billIdResults.isNotEmpty) {
        final billIds = billIdResults
            .map((row) => row['billId'] as String)
            .toList();

        result.first['billIds'] = billIds;
      }
    }

    return Payment.fromJson(Map<String, dynamic>.from(result.first), billRows: billsResult);
  }

  // Retrieve all Payments
  Future<List<Payment>> readAllPayments({Map<String, bool>? include}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includeRentor = include?['rentor'] == true;

    List<Map<String, Object?>> result;
    Map<String, List<Map<String, dynamic>>> billsResult = {};

    if (!includeRentor) {
      result = await db.query('payments');
    }
    else {
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
        'r.amountPaid AS r_amountPaid',
        'r.lastPaymentDate AS r_lastPaymentDate',
      ];

      result = await db.rawQuery('''
        SELECT ${selects.join(', ')}
        FROM payments p
        LEFT JOIN rentors r ON r.rentorId = p.rentorId
      ''');
    }

    if (result.isEmpty) {
      return [];
    }

    final paymentIds = result
        .map((row) => row['paymentId']?.toString())
        .whereType<String>()
        .toList();


    if (paymentIds.isNotEmpty) {
      final placeholders = paymentIds.map((_) => '?').join(', ');

      if (includeBill) {
        final rawBillRows = await db.rawQuery('''
        SELECT pb.paymentId AS pb_paymentId,
               b.id AS b_id,
               b.billId AS b_billId,
               b.company AS b_company,
               b.type AS b_type,
               b.amount AS b_amount,
               b.dueDate AS b_dueDate,
               b.status AS b_status,
               b.notes AS b_notes
        FROM payment_bills pb
        JOIN bills b ON b.billId = pb.billId
        WHERE pb.paymentId IN ($placeholders)
      ''', paymentIds);

        for(String paymentId in paymentIds) {
          billsResult[paymentId] = rawBillRows
              .where((row) => row['pb_paymentId'] != null && row['pb_paymentId']!.toString() == paymentId)
              .toList();
        }
      }
      else {
        final billIdsResults = await db.rawQuery('SELECT paymentId, billId FROM payment_bills WHERE paymentId IN ($placeholders)', paymentIds);
        if (billIdsResults.isNotEmpty) {
          for (final row in result) {
            final pId = row['paymentId']?.toString();
            if (pId == null || pId.isEmpty) continue;
            var billIds = billIdsResults
                .where((row) => row['paymentId'] != null && row['paymentId']!.toString() == pId)
                .map((row) => row['billId'] as String)
                .toList();
            row['billIds'] = billIds;
          }
        }
      }
    }

    return result
        .where((map) => map['paymentId'] != null && map['paymentId']!.toString().isNotEmpty)
        .map((map) => Payment.fromJson(map, billRows: billsResult[map['paymentId']!.toString()])).toList();
  }

  // Update a Payment
  Future<int> updatePayment(Payment payment) async {
    final db = await database;

    // Prepare payment data without billIds for update
    final paymentData = payment.toJson();

    final result = await db.update(
      'payments',
      paymentData,
      where: 'paymentId = ?',
      whereArgs: [payment.paymentId!],
    );

    // Update junction table: remove old entries and add new ones
    await db.delete(
      'payment_bills',
      where: 'paymentId = ?',
      whereArgs: [payment.paymentId],
    );

    if (payment.billIds != null && payment.billIds!.isNotEmpty) {
      for (final billId in payment.billIds!) {
        await db.insert(
          'payment_bills',
          {'paymentId': payment.paymentId, 'billId': billId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    return result;
  }

  // Delete a Payment
  Future<int> deletePayment(String id) async {
    final db = await database;
    return await db.delete('payments', where: 'paymentId = ?', whereArgs: [id]);
  }

  Future<int> deleteAllPayments() async {
    final db = await database;
    return await db.delete('payments');
  }
  //endregionZ

  //region Email
  // Insert Email Data
  Future<int> createEmailData(EmailData emailData) async {
    final db = await database;
    return await db.insert('email_data', emailData.toJson());
  }

  // Retrieve Email Data by emailId
  Future<EmailData?> readEmail(String emailId, {Map<String, bool>? include}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includePayment = include?['payment'] == true;

    List<Map<String, Object?>> result;
    if (!includeBill && !includePayment) {
      result = await db.query(
        'email_data',
        where: 'emailId = ?',
        whereArgs: [emailId],
      );
    } else {
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

      final query = '''
        SELECT ${selects.join(', ')}
        FROM email_data e
        ${joins.join(' ')}
        WHERE e.emailId = ?
      ''';

      result = await db.rawQuery(query, [emailId]);
    }

    if (result.isEmpty) {
      return null;
    }

    return EmailData.fromJson(result.first);
  }

  // Retrieve all Email Data
  Future<List<EmailData>> readEmails({Map<String, bool>? include}) async {
    final db = await database;
    final includeBill = include?['bill'] == true;
    final includePayment = include?['payment'] == true;

    if (!includeBill && !includePayment) {
      final result = await db.query('email_data');
      return result.map((map) => EmailData.fromJson(map)).toList();
    }

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

    final query = '''
      SELECT ${selects.join(', ')}
      FROM email_data e
      ${joins.join(' ')}
    ''';

    final result = await db.rawQuery(query);
    return result.map((map) => EmailData.fromJson(map)).toList();
  }

  // Retrieve unprocessed Email Data
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

    final query = '''
      SELECT ${selects.join(', ')}
      FROM email_data e
      ${joins.join(' ')}
      WHERE e.processed = 0
    ''';

    final result = await db.rawQuery(query);
    return result.map((map) => EmailData.fromJson(map)).toList();
  }

  // Retrieve processed Email Data
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

    final query = '''
      SELECT ${selects.join(', ')}
      FROM email_data e
      ${joins.join(' ')}
      WHERE e.processed = 1
    ''';

    final result = await db.rawQuery(query);
    return result.map((map) => EmailData.fromJson(map)).toList();
  }

  // Update a Email Data
  Future<int> updateEmailData(EmailData emaildata) async {
    final db = await database;

    // Make a copy of the data and remove the 'id' field
    final data = Map<String, dynamic>.from(emaildata.toJson());
    data.remove('id');

    return await db.update(
      'email_data',
      data,
      where: 'emailId = ?',
      whereArgs: [emaildata.emailId!],
    );
  }

  // Delete a Email Data
  Future<int> deleteEmailData(String id) async {
    final db = await database;
    return await db.delete('email_data', where: 'emailId = ?', whereArgs: [id]);
  }

  Future<int> deleteAllEmailData() async {
    final db = await database;
    return await db.delete('email_data');
  }
  //endregion
  //endregion

  //region Database Lifecycle
  // Close the database
  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
  }
  //endregion
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/email_data.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';

class DatabaseHelper {
  static const _databaseName = 'utility_manager.db';

  static const _databaseVersion = 3;

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

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
          billId TEXT,
          company TEXT NOT NULL,
          type TEXT NOT NULL,
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
          defaultPercentage REAL NOT NULL,
          billPercentages TEXT,
          amountPaid REAL,
          lastPaymentDate TEXT
        )
      ''');
    }

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        billId INTEGER NOT NULL,
        rentorId INTEGER NOT NULL,
        amountPaid REAL NOT NULL,
        paymentDate TEXT NOT NULL,
        FOREIGN KEY (billId) REFERENCES bills (id),
        FOREIGN KEY (rentorId) REFERENCES rentors (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE email_data (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        emailSubject TEXT NOT NULL,
        emailBody TEXT NOT NULL,
        emailId INTEGER,
        billId TEXT,
        processed INTEGER NOT NULL,
        FOREIGN KEY (billId) REFERENCES bills (billId) ON DELETE CASCADE
      )
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
  }

  // #region CRUD Operations
  // #region Bill
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
      where: 'id = ?',
      whereArgs: [bill.id!],
    );
  }

  // Delete a Bill
  Future<int> deleteBill(int id) async {
    final db = await database;
    return await db.delete('bills', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllBills() async {
    final db = await database;
    return await db.delete('bills');
  }
  // #endregion

  // #region Rentor
  // Insert a Rentor
  Future<int> createRentor(Rentor rentor) async {
    final db = await database;
    return await db.insert('rentors', rentor.toJson());
  }

  // Retrieve a Rentor by id
  Future<Rentor?> readRentor(int id) async {
    final db = await database;
    final result = await db.query(
      'rentors',
      where: 'id = ?',
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
      rentor.toJson(),
      where: 'id = ?',
      whereArgs: [rentor.id!],
    );
  }

  // Delete a Rentor
  Future<int> deleteRentor(int id) async {
    final db = await database;
    return await db.delete('rentors', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllRentors() async {
    final db = await database;
    return await db.delete('rentors');
  }
  // #endregion

  // #region Payment
  // Insert a Payment
  Future<int> createPayment(Payment payment) async {
    final db = await database;
    return await db.insert('payments', payment.toJson());
  }

  // Retrieve a Payment by id
  Future<Payment?> readPayment(int id) async {
    final db = await database;
    final result = await db.query(
      'payments',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result.isEmpty) {
      return null;
    }

    return Payment.fromJson(result.first);
  }

  // Retrieve all Payments
  Future<List<Payment>> readAllPayments() async {
    final db = await database;
    final result = await db.query('payments');
    return result.map((map) => Payment.fromJson(map)).toList();
  }

  // Update a Payment
  Future<int> updatePayment(Payment payment) async {
    final db = await database;
    return await db.update(
      'payments',
      payment.toJson(),
      where: 'id = ?',
      whereArgs: [payment.id!],
    );
  }

  // Delete a Payment
  Future<int> deletePayment(int id) async {
    final db = await database;
    return await db.delete('payments', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllPayments() async {
    final db = await database;
    return await db.delete('payments');
  }
  // #endregion

  // #region Email
  // Insert Email Data
  Future<int> createEmailData(EmailData emailData) async {
    final db = await database;
    return await db.insert('email_data', emailData.toJson());
  }

  // Retrieve unprocessed Email Data
  Future<EmailData?> readEmail(int emailId) async {
    final db = await database;
    final result = await db.query(
      'email_data',
      where: 'emailId = ?',
      whereArgs: [emailId],
    );

    if (result.isEmpty) {
      return null;
    }

    return EmailData.fromJson(result.first);
  }

  // Retrieve unprocessed Email Data
  Future<List<EmailData>> readEmails() async {
    final db = await database;
    final result = await db.query('email_data');
    return result.map((map) => EmailData.fromJson(map)).toList();
  }

  // Retrieve unprocessed Email Data
  Future<List<EmailData>> readUnprocessedEmails() async {
    final db = await database;
    final result = await db.query(
      'email_data',
      where: 'processed = ?',
      whereArgs: [0],
    );
    return result.map((map) => EmailData.fromJson(map)).toList();
  }

  // Retrieve unprocessed Email Data
  Future<List<EmailData>> readProcessedEmails() async {
    final db = await database;
    final result = await db.query(
      'email_data',
      where: 'processed = ?',
      whereArgs: [1],
    );
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
  Future<int> deleteEmailData(int id) async {
    final db = await database;
    return await db.delete('email_data', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllEmailData() async {
    final db = await database;
    return await db.delete('email_data');
  }
  // #endregion
  // #endregion

  // Close the database
  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
  }
}

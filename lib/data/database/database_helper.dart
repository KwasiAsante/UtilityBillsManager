import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/bill.dart';
import '../models/rentor.dart';
import '../models/payment.dart';
import '../models/email_data.dart';

class DatabaseHelper {
  static const _databaseName = 'utility_manager.db';

  static const _databaseVersion = 1;

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() => _instance;

  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
        billId INTEGER,
        processed INTEGER NOT NULL,
        FOREIGN KEY (billId) REFERENCES bills (id)
      )
    ''');
  }

  // #region CRUD Operations
  // #region Bill
  // Insert a Bill
  Future<int> insertBill(Bill bill) async {
    final db = await database;
    return await db.insert('bills', bill.toMap());
  }

  // Retrieve all Bills
  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final result = await db.query('bills');
    return result.map((map) => Bill.fromMap(map)).toList();
  }

  // Retrieve all Bills
  Future<List<Bill>> getBillsByStatus(String status) async {
    final db = await database;
    final result = await db.query('bills', where: 'status = ?', whereArgs: [status]);
    return result.map((map) => Bill.fromMap(map)).toList();
  }

  // Update a Bill
  Future<int> updateBill(Bill bill) async {
    final db = await database;
    return await db.update('bills', bill.toMap(), where: 'id = ?', whereArgs: [bill.id!]);
  }

  // Delete a Bill
  Future<int> deleteBill(int id) async {
    final db = await database;
    return await db.delete('bills', where:'id = ?', whereArgs: [id]);
  }
  // #endregion

  // #region Rentor
  // Insert a Rentor
  Future<int> insertRentor(Rentor rentor) async {
    final db = await database;
    return await db.insert('rentors', rentor.toMap());
  }

  // Retrieve all Rentors
  Future<List<Rentor>> getAllRentors() async {
    final db = await database;
    final result = await db.query('rentors');
    return result.map((map) => Rentor.fromMap(map)).toList();
  }
  // #endregion

  // #region Payment
  // Insert a Payment
  Future<int> insertPayment(Payment payment) async {
    final db = await database;
    return await db.insert('payments', payment.toMap());
  }

  // Retrieve all Payments
  Future<List<Payment>> getAllPayments() async {
    final db = await database;
    final result = await db.query('payments');
    return result.map((map) => Payment.fromMap(map)).toList();
  }
  // #endregion

  // #region Email
  // Insert Email Data
  Future<int> insertEmailData(EmailData emailData) async {
    final db = await database;
    return await db.insert('email_data', emailData.toMap());
  }

  // Retrieve unprocessed Email Data
  Future<List<EmailData>> getUnprocessedEmails() async {
    final db = await database;
    final result = await db.query(
      'email_data',
      where: 'processed = ?',
      whereArgs: [0],
    );
    return result.map((map) => EmailData.fromMap(map)).toList();
  }
  // #endregion
  // #endregion

  // Close the database
  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
  }
}

import 'package:flutter/material.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/data/models/summary_item.dart';

class ExportUtils {
  static Future<void> exportToCSV(
    BuildContext context,
    List<SummaryItem> data,
    String filename,
  ) async {
    // Convert summary data into CSV string
    // Save file locally
    // Share or notify user
  }

  static Future<void> exportToPDF(
    BuildContext context,
    List<SummaryItem> data,
    String filename,
  ) async {
    // Use pdf and printing package
    // Layout data into a PDF
    // Save or open PDF
  }

  static void exportBillsToCSV(List<Bill> filteredBills, List<Rentor> rentors) {}

  static void exportBillsToPDF(List<Bill> filteredBills, List<Rentor> rentors) {}
}

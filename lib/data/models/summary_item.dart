/// Immutable value object holding aggregated financial figures for a summary row
/// (e.g. one bill type or one calendar month).
///
/// Used by the export utilities to build CSV / PDF reports.
class SummaryItem {
  final String title;
  final double totalAmount;
  final double paidAmount;
  final double unpaidAmount;

  SummaryItem({
    required this.title,
    required this.totalAmount,
    required this.paidAmount,
    required this.unpaidAmount,
  });
}
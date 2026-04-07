/// Utility class providing null-safe comparison helpers for [Comparable] types.
///
/// Use [compareNullable] wherever a sort comparator needs to handle `null`
/// values consistently across the app (e.g. rentor lists sorted by
/// `lastPaymentDate`).

class ComparableUtils {
  /// Compares two nullable [Comparable] values, treating `null` as greater than
  /// any non-null value so nulls sort last in ascending order.
  ///
  /// Returns a negative integer, zero, or a positive integer as [a] is less
  /// than, equal to, or greater than [b].
  ///
  /// Set [descending] to `true` to reverse the sort direction; nulls will then
  /// appear first (at the top of a descending list).
  static int compareNullable<T extends Comparable<T>>(
      T? a,
      T? b, {
        bool descending = false,
      }) {
    if (a == null && b == null) return 0; // Both null — treat as equal.
    if (a == null) return 1;              // Null sorts after non-null (ascending).
    if (b == null) return -1;

    final comparison = a.compareTo(b);
    // Flip the sign when the caller wants descending order.
    return descending ? -comparison : comparison;
  }
}
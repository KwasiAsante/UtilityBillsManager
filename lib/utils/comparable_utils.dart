class ComparableUtils {
  static int compareNullable<T extends Comparable<T>>(
      T? a,
      T? b, {
        bool descending = false,
      }) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;

    final comparison = a.compareTo(b);
    return descending ? -comparison : comparison;
  }
}
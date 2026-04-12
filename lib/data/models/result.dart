/// A generic wrapper that represents the outcome of an async operation.
///
/// Every CRUD call in the helper / repository layer returns a [Result<T>] so
/// that callers can inspect success or failure without catching exceptions:
///
/// ```dart
/// final result = await billsHelper.readAllBills();
/// if (result.isSuccess) {
///   final bills = result.data!;
/// } else {
///   print(result.errorMessage);
/// }
/// ```
class Result<T> {
  final ResultStatus status;
  final T? data;
  final String? message;
  final String? errorMessage;

  Result({
    required this.status,
    this.data,
    this.message,
    this.errorMessage,
  });

  /// Creates a successful result, optionally carrying [data] and an
  /// informational [message].
  factory Result.success({T? data, String? message}) {
    return Result(
      status: ResultStatus.success,
      data: data,
      message: message,
    );
  }

  /// Creates a failed result with a human-readable [errorMessage].
  factory Result.error({String? errorMessage}) {
    return Result(
      status: ResultStatus.error,
      errorMessage: errorMessage,
    );
  }

  /// Creates a failed result from a caught [Exception], converting it to a
  /// string error message via [exception.toString()].
  factory Result.exception({Exception? exception}) {
    return Result(
      status: ResultStatus.error,
      errorMessage: exception.toString(),
    );
  }

  /// `true` when [status] is [ResultStatus.success].
  bool get isSuccess => status == ResultStatus.success;

  /// `true` when [status] is [ResultStatus.error].
  bool get isError => status == ResultStatus.error;
}

/// Possible outcomes of a [Result]-returning operation.
enum ResultStatus {
  success,
  error
}
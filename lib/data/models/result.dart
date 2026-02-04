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

  // Convenience constructor for success responses
  factory Result.success({T? data, String? message}) {
    return Result(
      status: ResultStatus.success,
      data: data,
      message: message,
    );
  }

  // Convenience constructor for error responses
  factory Result.error({String? errorMessage}) {
    return Result(
      status: ResultStatus.error,
      errorMessage: errorMessage,
    );
  }

  // Convenience constructor for error responses
  factory Result.exception({Exception? exception}) {
    return Result(
      status: ResultStatus.error,
      errorMessage: exception.toString(),
    );
  }

  // Check if the result is successful
  bool get isSuccess => status == ResultStatus.success;

  // Check if the result has an error
  bool get isError => status == ResultStatus.error;
}

// Enum to represent the status of the operation
enum ResultStatus {
  success,
  error
}
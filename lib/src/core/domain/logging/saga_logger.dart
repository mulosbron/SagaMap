/// Logger abstraction used by domain services.
abstract interface class SagaLogger {
  /// Emits low-severity diagnostics.
  void debug(String message);

  /// Emits failure diagnostics.
  void error(String message, [Object? error, StackTrace? stackTrace]);
}

/// No-op logger for consumers that do not need log output.
class NoopSagaLogger implements SagaLogger {
  const NoopSagaLogger();

  @override
  void debug(String message) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
}

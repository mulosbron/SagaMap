/// Base exception type for recoverable saga-domain failures.
class SagaDomainException implements Exception {
  final String message;

  const SagaDomainException(this.message);

  @override
  String toString() => 'SagaDomainException: $message';
}

class InvalidTerrainConfigException extends SagaDomainException {
  const InvalidTerrainConfigException(super.message);
}

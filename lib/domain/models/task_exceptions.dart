/// Base exception for tasks that should fail immediately instead of retrying.
abstract class NonRetryableTaskException implements Exception {
  String get message;
}

/// The processing budget is durable, so a restart cannot restart its clock.
class JournalProcessingTimeoutException implements NonRetryableTaskException {
  @override
  final String message = '整理已超时，原始记录已保留。请检查网络或模型配置后重新整理。';

  @override
  String toString() => message;
}

/// Exception thrown when LLM configuration is invalid or missing required fields.
class InvalidModelConfigException implements NonRetryableTaskException {
  @override
  final String message;

  InvalidModelConfigException([
    this.message = 'The LLM configuration is invalid.',
  ]);

  @override
  String toString() => "InvalidModelConfigException: $message";
}

/// Exception thrown when an LLM API call fails with a non-retryable HTTP error
/// (e.g. 401, 403, 400). Task executor will skip retries and invoke the failure handler.
class NonRetryableLlmException implements NonRetryableTaskException {
  @override
  final String message;

  final int? statusCode;
  final Object? originalError;

  NonRetryableLlmException(this.message, {this.statusCode, this.originalError});

  @override
  String toString() {
    final buf = StringBuffer('NonRetryableLlmException: $message');
    if (statusCode != null) buf.write(' (HTTP $statusCode)');
    if (originalError != null) buf.write('\nOriginal error: $originalError');
    return buf.toString();
  }
}

/// Exception thrown when an agent reached its max-turn/loop guard.
class NonRetryableAgentLoopException implements NonRetryableTaskException {
  @override
  final String message;

  final Object? originalError;

  NonRetryableAgentLoopException(this.message, {this.originalError});

  @override
  String toString() {
    final buf = StringBuffer('NonRetryableAgentLoopException: $message');
    if (originalError != null) buf.write('\nOriginal error: $originalError');
    return buf.toString();
  }
}

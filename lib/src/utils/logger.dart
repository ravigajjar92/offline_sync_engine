// ignore_for_file: avoid_print

/// Pluggable logger.
///
/// The engine never calls `print` directly. Implement [SyncLogger] to forward
/// logs to your own observability stack (e.g. Sentry, Datadog, Logger package).
abstract class SyncLogger {
  void info(String message, {Object? error, StackTrace? stackTrace});
  void warning(String message, {Object? error, StackTrace? stackTrace});
  void error(String message, {Object? error, StackTrace? stackTrace});
}

/// Default logger — writes to stdout when enabled, no-op otherwise.
class ConsoleLogger implements SyncLogger {
  final bool enabled;
  final String tag;

  const ConsoleLogger({this.enabled = true, this.tag = 'OfflineSync'});

  void _log(String level, String message, Object? error, StackTrace? st) {
    if (!enabled) return;
    final ts = DateTime.now().toIso8601String();
    final buf = StringBuffer('[$ts] [$tag] [$level] $message');
    if (error != null) buf.write(' | error: $error');
    if (st != null) buf.write('\n$st');
    print(buf);
  }

  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) =>
      _log('INFO', message, error, stackTrace);

  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) =>
      _log('WARN', message, error, stackTrace);

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _log('ERROR', message, error, stackTrace);
}

/// Discards every log line. Used when `loggingEnabled = false`.
class NoopLogger implements SyncLogger {
  const NoopLogger();
  @override
  void info(String message, {Object? error, StackTrace? stackTrace}) {}
  @override
  void warning(String message, {Object? error, StackTrace? stackTrace}) {}
  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {}
}

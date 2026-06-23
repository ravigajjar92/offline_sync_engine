import 'dart:math' as math;

/// Computes per-attempt retry delays using exponential backoff.
///
/// `delay = baseDelay * 2^retryCount`
///
/// Example (baseDelay = 2s):
/// ```
/// attempt 0 → 2s
/// attempt 1 → 4s
/// attempt 2 → 8s
/// attempt 3 → 16s
/// attempt 4 → 32s
/// ```
class RetryPolicy {
  final Duration baseDelay;
  final int maxRetries;
  final Duration maxDelay;

  const RetryPolicy({
    required this.baseDelay,
    required this.maxRetries,
    this.maxDelay = const Duration(minutes: 5),
  });

  /// Whether a job with [currentRetryCount] failed attempts is still eligible
  /// for another attempt.
  bool shouldRetry(int currentRetryCount) => currentRetryCount < maxRetries;

  /// Delay before attempt #[retryCount] (zero-indexed).
  ///
  /// Saturates at [maxDelay] to keep wait times bounded for high retry counts.
  Duration nextDelay(int retryCount) {
    if (retryCount < 0) return Duration.zero;
    // 2^30 microseconds ≈ 18 minutes — plenty of headroom and avoids overflow.
    final shift = math.min(retryCount, 30);
    final micros = baseDelay.inMicroseconds * (1 << shift);
    if (micros >= maxDelay.inMicroseconds) return maxDelay;
    return Duration(microseconds: micros);
  }
}

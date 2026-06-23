import 'package:flutter_test/flutter_test.dart';
import 'package:offline_sync_engine/offline_sync_engine.dart';

void main() {
  group('RetryPolicy', () {
    const policy = RetryPolicy(
      baseDelay: Duration(seconds: 2),
      maxRetries: 5,
    );

    test('nextDelay follows base * 2^retryCount (spec example)', () {
      expect(policy.nextDelay(0), const Duration(seconds: 2));
      expect(policy.nextDelay(1), const Duration(seconds: 4));
      expect(policy.nextDelay(2), const Duration(seconds: 8));
      expect(policy.nextDelay(3), const Duration(seconds: 16));
      expect(policy.nextDelay(4), const Duration(seconds: 32));
    });

    test('negative retryCount returns zero (defensive)', () {
      expect(policy.nextDelay(-1), Duration.zero);
    });

    test('saturates at maxDelay', () {
      const bounded = RetryPolicy(
        baseDelay: Duration(seconds: 1),
        maxRetries: 5,
        maxDelay: Duration(seconds: 10),
      );
      expect(bounded.nextDelay(20), const Duration(seconds: 10));
    });

    test('shouldRetry honors maxRetries', () {
      expect(policy.shouldRetry(0), isTrue);
      expect(policy.shouldRetry(4), isTrue);
      expect(policy.shouldRetry(5), isFalse);
      expect(policy.shouldRetry(99), isFalse);
    });
  });
}

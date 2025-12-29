// ========================================
// 4. lib/core/sync/retry_strategy.dart
// ========================================

import 'dart:math';

class RetryStrategy {
  final int maxAttempts;
  final Duration initialDelay;
  final double backoffMultiplier;
  final Duration maxDelay;

  const RetryStrategy({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 5),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(minutes: 30),
  });

  Duration getDelay(int attemptNumber) {
    if (attemptNumber >= maxAttempts) {
      return maxDelay;
    }

    final delayMs = initialDelay.inMilliseconds *
        pow(backoffMultiplier, attemptNumber);

    return Duration(
      milliseconds: min(delayMs.toInt(), maxDelay.inMilliseconds),
    );
  }

  bool shouldRetry(int attemptNumber) {
    return attemptNumber < maxAttempts;
  }

  static const RetryStrategy aggressive = RetryStrategy(
    maxAttempts: 10,
    initialDelay: Duration(seconds: 2),
    backoffMultiplier: 1.5,
  );

  static const RetryStrategy conservative = RetryStrategy(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 30),
    backoffMultiplier: 3.0,
  );
}

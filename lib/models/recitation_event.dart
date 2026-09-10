/// Recitation detection sensitivity / speed mode.
enum RecitationSensitivity {
  /// Low precision / Hadr (حدر):
  /// Forgiving matching for rapid review, whispered recitation, or murmur recaps.
  quickRecap,

  /// Medium precision / Tadweer (تدوير):
  /// Balanced smart adaptive tracking for everyday practice (default).
  balanced,

  /// High precision / Tahqeeq (تحقيق):
  /// Strict exam mode requiring clear articulation and complete verse endings.
  strict,
}

enum RecitationStatus {
  idle,
  listening,
  processing,
  matched,
  skipped,
  error,
}

class RecitationMatchResult {
  final int surah;
  final int expectedAyah;
  final int detectedAyah;
  final double confidence;
  final bool isSkip;
  final List<int> matchedTokens;
  final String? decodedText;
  final int tokensConsumed;
  final int wordsConsumed;

  const RecitationMatchResult({
    required this.surah,
    required this.expectedAyah,
    required this.detectedAyah,
    required this.confidence,
    required this.isSkip,
    this.matchedTokens = const [],
    this.decodedText,
    this.tokensConsumed = 0,
    this.wordsConsumed = 0,
  });

  @override
  String toString() =>
      'RecitationMatchResult(surah: $surah, expected: $expectedAyah, detected: $detectedAyah, conf: ${confidence.toStringAsFixed(2)}, isSkip: $isSkip)';
}

abstract class RecitationEvent {
  const RecitationEvent();
}

class RecitationStatusEvent extends RecitationEvent {
  final RecitationStatus status;
  final double audioLevel; // 0.0 to 1.0 for mic visualizer
  final int currentExpectedAyah;

  const RecitationStatusEvent({
    required this.status,
    this.audioLevel = 0.0,
    required this.currentExpectedAyah,
  });
}

class RecitationMatchedEvent extends RecitationEvent {
  final int surah;
  final int ayah;
  final double confidence;
  final String? text;

  const RecitationMatchedEvent({
    required this.surah,
    required this.ayah,
    required this.confidence,
    this.text,
  });
}

class RecitationSkippedEvent extends RecitationEvent {
  final int surah;
  final int expectedAyah;
  final int jumpedToAyah;
  final double confidence;

  const RecitationSkippedEvent({
    required this.surah,
    required this.expectedAyah,
    required this.jumpedToAyah,
    required this.confidence,
  });
}

class RecitationErrorEvent extends RecitationEvent {
  final String message;

  const RecitationErrorEvent(this.message);
}

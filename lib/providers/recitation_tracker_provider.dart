import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/recitation_event.dart';
import '../services/recitation_engine.dart';

class RecitationTrackerProvider extends ChangeNotifier with WidgetsBindingObserver {
  final RecitationEngine _engine = RecitationEngine();

  RecitationTrackerProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  RecitationStatus _status = RecitationStatus.idle;
  double _audioLevel = 0.0;
  int _currentExpectedAyah = 1;
  int? _lastMatchedAyah;
  int? _skippedFromAyah;
  int? _skippedToAyah;
  String? _lastRecognizedText;
  String? _errorMessage;
  bool _isInitializing = false;
  bool _isVoiceTrackingEnabled = true;
  RecitationSensitivity _sensitivity = RecitationSensitivity.balanced;
  bool _adaptiveNoise = true;

  Timer? _inactivityTimer;
  static const Duration _inactivityDuration = Duration(minutes: 1);

  // External UI callbacks
  void Function(int ayah)? _onVerseMatchedCallback;
  void Function(int expectedAyah, int jumpedToAyah)? _onVerseSkippedCallback;

  RecitationStatus get status => _status;
  double get audioLevel => _audioLevel;
  int get currentExpectedAyah => _currentExpectedAyah;
  int? get lastMatchedAyah => _lastMatchedAyah;
  int? get skippedFromAyah => _skippedFromAyah;
  int? get skippedToAyah => _skippedToAyah;
  String? get lastRecognizedText => _lastRecognizedText;
  String? get errorMessage => _errorMessage;
  bool get isEngineReady => _engine.isInitialized;
  bool get isListening => _engine.isListening;
  bool get isInitializing => _isInitializing;
  bool get isVoiceTrackingEnabled => _isVoiceTrackingEnabled;
  RecitationSensitivity get sensitivity => _sensitivity;
  bool get adaptiveNoise => _adaptiveNoise;

  void setSensitivity(RecitationSensitivity sensitivity) {
    if (_sensitivity == sensitivity) return;
    _sensitivity = sensitivity;
    _engine.setSensitivity(sensitivity);
    notifyListeners();
  }

  void setAdaptiveNoise(bool enabled) {
    if (_adaptiveNoise == enabled) return;
    _adaptiveNoise = enabled;
    _engine.setAdaptiveNoise(enabled);
    notifyListeners();
  }

  void toggleVoiceTracking(bool enabled) {
    _isVoiceTrackingEnabled = enabled;
    if (!enabled && isListening) {
      stopTracking();
    }
    notifyListeners();
  }

  /// Initializes ONNX model and token dictionary in the background.
  Future<void> initializeEngine() async {
    if (_engine.isInitialized || _isInitializing) return;
    _isInitializing = true;
    notifyListeners();

    try {
      await _engine.initialize();
    } catch (e) {
      _errorMessage = 'Failed to initialize recitation model: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  /// Starts real-time recitation tracking for a session.
  Future<void> startTracking({
    required int surah,
    required int startAyah,
    required int endAyah,
    RecitationSensitivity? sensitivity,
    bool? adaptiveNoise,
    void Function(int ayah)? onVerseMatched,
    void Function(int expectedAyah, int jumpedToAyah)? onVerseSkipped,
  }) async {
    if (sensitivity != null) {
      _sensitivity = sensitivity;
      _engine.setSensitivity(sensitivity);
    }
    if (adaptiveNoise != null) {
      _adaptiveNoise = adaptiveNoise;
      _engine.setAdaptiveNoise(adaptiveNoise);
    }
    _onVerseMatchedCallback = onVerseMatched;
    _onVerseSkippedCallback = onVerseSkipped;
    _currentExpectedAyah = startAyah;
    _skippedFromAyah = null;
    _skippedToAyah = null;
    _errorMessage = null;

    try {
      if (!_engine.isInitialized) {
        _isInitializing = true;
        notifyListeners();
      }

      await _engine.startListening(
        surah: surah,
        startAyah: startAyah,
        endAyah: endAyah,
        adaptiveNoise: _adaptiveNoise,
        onEvent: _handleEngineEvent,
      );
      _startInactivityTimer();
    } catch (e) {
      _errorMessage = 'Failed to start tracking: $e';
      rethrow;
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityDuration, _handleInactivityTimeout);
  }

  void _cancelInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
  }

  void _handleInactivityTimeout() {
    if (isListening) {
      stopTracking();
      _errorMessage = 'Voice tracking paused (1 minute inactivity)';
      notifyListeners();
    }
  }

  /// Stops tracking.
  Future<void> stopTracking() async {
    _cancelInactivityTimer();
    await _engine.stopListening();
    _status = RecitationStatus.idle;
    _audioLevel = 0.0;
    notifyListeners();
  }

  /// Synchronizes expected Ayah when user navigates manually.
  void setExpectedAyah(int ayah) {
    _currentExpectedAyah = ayah;
    _engine.setExpectedAyah(ayah);
    if (isListening) _startInactivityTimer();
    notifyListeners();
  }

  /// Updates active range for progressive tracking.
  void updateActiveRange({int? surah, required int startAyah, required int endAyah}) {
    _currentExpectedAyah = startAyah;
    _engine.updateRange(surah: surah, startAyah: startAyah, endAyah: endAyah);
    if (isListening) _startInactivityTimer();
    notifyListeners();
  }

  /// Dismisses an active skip or error alert banner in UI, ensuring the engine stays on the expected verse.
  void dismissSkipAlert() {
    if (_skippedFromAyah != null) {
      _currentExpectedAyah = _skippedFromAyah!;
      _engine.setExpectedAyah(_skippedFromAyah!);
    }
    _skippedFromAyah = null;
    _skippedToAyah = null;
    _errorMessage = null;
    if (isListening) _startInactivityTimer();
    notifyListeners();
  }

  /// Explicitly retries / stays on a specific verse.
  void retryVerse(int ayah) {
    _currentExpectedAyah = ayah;
    _engine.setExpectedAyah(ayah);
    _skippedFromAyah = null;
    _skippedToAyah = null;
    _errorMessage = null;
    if (isListening) _startInactivityTimer();
    notifyListeners();
  }

  /// Accepts a detected skip, revealing the jumped verse and advancing expected ayah past it.
  void acceptSkip() {
    if (_skippedToAyah != null) {
      final jumpedAyah = _skippedToAyah!;
      _lastMatchedAyah = jumpedAyah;
      _currentExpectedAyah = jumpedAyah + 1;
      _engine.setExpectedAyah(jumpedAyah + 1);
      final callback = _onVerseMatchedCallback;
      _skippedFromAyah = null;
      _skippedToAyah = null;
      _errorMessage = null;
      if (isListening) _startInactivityTimer();
      notifyListeners();
      callback?.call(jumpedAyah);
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _handleEngineEvent(RecitationEvent event) {
    if (event is RecitationStatusEvent) {
      _status = event.status;
      _audioLevel = event.audioLevel;
      _currentExpectedAyah = event.currentExpectedAyah;
      notifyListeners();
    } else if (event is RecitationMatchedEvent) {
      _lastMatchedAyah = event.ayah;
      _lastRecognizedText = event.text;
      _skippedFromAyah = null;
      _skippedToAyah = null;
      _status = RecitationStatus.matched;
      _startInactivityTimer(); // Activity detected: verse matched!
      notifyListeners();

      _onVerseMatchedCallback?.call(event.ayah);
    } else if (event is RecitationSkippedEvent) {
      _skippedFromAyah = event.expectedAyah;
      _skippedToAyah = event.jumpedToAyah;
      _status = RecitationStatus.skipped;
      notifyListeners();

      _onVerseSkippedCallback?.call(event.expectedAyah, event.jumpedToAyah);
    } else if (event is RecitationErrorEvent) {
      _errorMessage = event.message;
      _status = RecitationStatus.error;
      notifyListeners();
    }
  }

  bool _wasListeningBeforeBackground = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Device screen locked or app backgrounded:
      // IMMEDIATELY pause native AudioRecord to prevent JNI deadlock and black screen upon unlocking.
      if (isListening) {
        _wasListeningBeforeBackground = true;
        pauseForBackground();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasListeningBeforeBackground) {
        _wasListeningBeforeBackground = false;
        // On unlock, ensure status is clean and notify so UI redraws fresh without black screen.
        _status = RecitationStatus.idle;
        _audioLevel = 0.0;
        notifyListeners();
      }
    }
  }

  /// Cleanly pauses listening when app goes into background or device is locked.
  Future<void> pauseForBackground() async {
    _cancelInactivityTimer();
    try {
      await _engine.stopListening().timeout(
        const Duration(milliseconds: 600),
        onTimeout: () {
          debugPrint('[RecitationTracker] Background stopListening timed out');
        },
      );
    } catch (e) {
      debugPrint('[RecitationTracker] Error in pauseForBackground: $e');
    }
    _status = RecitationStatus.idle;
    _audioLevel = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelInactivityTimer();
    _engine.dispose();
    super.dispose();
  }
}

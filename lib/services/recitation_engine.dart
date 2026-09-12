import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../models/recitation_event.dart';
import 'ctc_matcher.dart';

class RecitationEngine {
  static final RecitationEngine _instance = RecitationEngine._internal();
  factory RecitationEngine() => _instance;
  RecitationEngine._internal();

  AudioRecorder? _audioRecorder;
  StreamSubscription<Uint8List>? _audioSubscription;
  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  CtcMatcher? _matcher;

  bool _isInitialized = false;
  bool _isListening = false;
  bool _isInferring = false;
  bool _isSearchMode = false;
  void Function(double audioLevel)? _onSearchAudioLevel;
  void Function(List<VerseSearchResult> results, String recognizedText)? _onSearchResults;

  int _currentSurah = 1;
  int _startAyah = 1;
  int _expectedAyah = 1;
  int _endAyah = 7;
  RecitationSensitivity _sensitivity = RecitationSensitivity.balanced;

  void Function(RecitationEvent)? _onEvent;

  RecitationSensitivity get sensitivity => _sensitivity;

  void setSensitivity(RecitationSensitivity sensitivity) {
    _sensitivity = sensitivity;
  }

  // Adaptive noise floor tracking
  bool _adaptiveNoise = true;
  double _ambientNoiseFloor = 0.008;
  int _calibrationFramesRemaining = 8;

  bool get adaptiveNoise => _adaptiveNoise;

  void setAdaptiveNoise(bool enabled) {
    _adaptiveNoise = enabled;
    if (!enabled) {
      _ambientNoiseFloor = _silenceThreshold;
    }
  }

  // Audio buffer & VAD parameters
  static const int _sampleRate = 16000;
  static const double _silenceThreshold = 0.012; // RMS threshold for speech detection
  static const int _minSpeechSamples = 12000; // 0.75s minimum to run inference
  static const int _maxSpeechSamples = 56000; // 3.5s maximum before forcing inference
  static const int _silenceFramesNeeded = 3; // ~180-220ms silence to catch quick natural pauses/breaths

  final List<double> _speechBuffer = [];
  final List<int> _accumulatedTokens = [];
  int _trailingSilenceCount = 0;
  bool _speechActive = false;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  int get currentExpectedAyah => _expectedAyah;

  Future<File> _ensureModelFile(String assetPath) async {
    final directFile = File(assetPath);
    if (await directFile.exists()) {
      return directFile;
    }

    final dir = await getApplicationSupportDirectory();
    final fileName = assetPath.split('/').last;
    final cachedFile = File('${dir.path}/$fileName');

    final byteData = await rootBundle.load(assetPath);
    final assetLen = byteData.lengthInBytes;

    if (await cachedFile.exists()) {
      final len = await cachedFile.length();
      if (len == assetLen) {
        return cachedFile;
      }
    }

    debugPrint('[RecitationEngine] Extracting $assetPath to ${cachedFile.path}...');
    final buffer = byteData.buffer;
    await cachedFile.writeAsBytes(
      buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
      flush: true,
    );
    debugPrint('[RecitationEngine] Model extracted (${await cachedFile.length()} bytes)');
    return cachedFile;
  }

  /// Initializes ONNX Runtime, CtcMatcher, and loads the model.
  Future<void> initialize({
    String modelPath = 'assets/models/fastconformer_full_mixed.onnx',
    String tokensPath = 'assets/models/quran_ctc_tokens.json',
    String vocabPath = 'assets/models/vocab.json',
  }) async {
    if (_isInitialized) return;

    try {
      // 1. Initialize ONNX environment
      OrtEnv.instance.init();

      // 2. Load CtcMatcher token dictionary and vocab in background
      _matcher = await CtcMatcher.load(
        tokensPath: tokensPath,
        vocabPath: vocabPath,
      );

      // 3. Ensure model file exists on disk for efficient memory-mapped reading
      final modelFile = await _ensureModelFile(modelPath);

      // 4. Configure Session Options with optimal threads and platform providers
      _sessionOptions = OrtSessionOptions();
      _sessionOptions!.setIntraOpNumThreads(4);
      _sessionOptions!.setInterOpNumThreads(1);
      _sessionOptions!.setSessionGraphOptimizationLevel(
        GraphOptimizationLevel.ortEnableAll,
      );

      if (Platform.isWindows) {
        try {
          _sessionOptions!.appendDirectMLProvider();
        } catch (_) {}
      } else if (Platform.isIOS || Platform.isMacOS) {
        try {
          _sessionOptions!.appendCoreMLProvider(CoreMLFlags.useNone);
        } catch (_) {}
      }
      _sessionOptions!.appendCPUProvider(CPUFlags.useArena);

      // 5. Create Session from file (memory-mapped)
      try {
        _session = OrtSession.fromFile(modelFile, _sessionOptions!);
        debugPrint('[RecitationEngine] Initialized session with providers from file');
      } catch (e, st) {
        debugPrint('[RecitationEngine] fromFile accelerator error: $e\n$st. Retrying pure CPU...');
        _sessionOptions?.release();
        _sessionOptions = OrtSessionOptions();
        _sessionOptions!.setIntraOpNumThreads(4);
        _sessionOptions!.setInterOpNumThreads(1);
        _sessionOptions!.appendCPUProvider(CPUFlags.useArena);
        _session = OrtSession.fromFile(modelFile, _sessionOptions!);
      }

      _audioRecorder = AudioRecorder();
      _isInitialized = true;
      debugPrint('[RecitationEngine] Initialized successfully');
    } catch (e, st) {
      debugPrint('[RecitationEngine] Init error: $e\n$st');
      rethrow;
    }
  }

  /// Checks if microphone permission is granted.
  Future<bool> hasPermission() async {
    _audioRecorder ??= AudioRecorder();
    return await _audioRecorder!.hasPermission();
  }

  /// Starts listening and tracking recitation for a given surah range.
  Future<void> startListening({
    required int surah,
    required int startAyah,
    required int endAyah,
    int? initialExpectedAyah,
    bool? adaptiveNoise,
    required void Function(RecitationEvent) onEvent,
  }) async {
    if (_isListening) {
      await stopListening();
    }

    if (!_isInitialized) {
      await initialize();
    }

    final permitted = await hasPermission();
    if (!permitted) {
      const err = 'Microphone permission not granted';
      onEvent(const RecitationErrorEvent(err));
      throw Exception(err);
    }

    if (adaptiveNoise != null) {
      _adaptiveNoise = adaptiveNoise;
    }
    _ambientNoiseFloor = 0.008;
    _calibrationFramesRemaining = 8;

    _currentSurah = surah;
    _startAyah = startAyah;
    _expectedAyah = initialExpectedAyah ?? startAyah;
    _endAyah = endAyah;
    _onEvent = onEvent;

    _speechBuffer.clear();
    _accumulatedTokens.clear();
    _trailingSilenceCount = 0;
    _speechActive = false;

    _audioRecorder ??= AudioRecorder();

    try {
      final audioStream = await _audioRecorder!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

      _isListening = true;
      _onEvent?.call(RecitationStatusEvent(
        status: RecitationStatus.listening,
        audioLevel: 0.0,
        currentExpectedAyah: _expectedAyah,
      ));

      _audioSubscription = audioStream.listen(
        _processAudioChunk,
        onError: (err) {
          debugPrint('[RecitationEngine] Audio stream error: $err');
          _onEvent?.call(RecitationErrorEvent(err.toString()));
        },
      );
    } catch (e) {
      debugPrint('[RecitationEngine] startStream error: $e');
      _onEvent?.call(RecitationErrorEvent('Failed to start audio stream: $e'));
      rethrow;
    }
  }

  /// Updates current expected Ayah (e.g. when user scrolls or manually reveals).
  void setExpectedAyah(int ayah) {
    _expectedAyah = ayah;
    _accumulatedTokens.clear();
    _speechBuffer.clear();
    _onEvent?.call(RecitationStatusEvent(
      status: _isListening ? RecitationStatus.listening : RecitationStatus.idle,
      audioLevel: 0.0,
      currentExpectedAyah: _expectedAyah,
    ));
  }

  /// Updates active range for progressive tracking.
  void updateRange({int? surah, required int startAyah, required int endAyah, int? initialExpectedAyah}) {
    if (surah != null) _currentSurah = surah;
    _startAyah = startAyah;
    _expectedAyah = initialExpectedAyah ?? startAyah;
    _endAyah = endAyah;
    _accumulatedTokens.clear();
    _speechBuffer.clear();
    _onEvent?.call(RecitationStatusEvent(
      status: _isListening ? RecitationStatus.listening : RecitationStatus.idle,
      audioLevel: 0.0,
      currentExpectedAyah: _expectedAyah,
    ));
  }

  /// Searches for matching verses across the entire Quran using the loaded token database.
  List<VerseSearchResult> searchVerses(List<int> candidateTokens, {int limit = 5, double minScore = 0.35}) {
    if (_matcher == null) return const [];
    return _matcher!.searchVerses(candidateTokens, limit: limit, minScore: minScore);
  }

  /// Starts listening for recitation search across the entire Quran.
  Future<void> startVoiceSearch({
    required void Function(double audioLevel) onAudioLevel,
    required void Function(List<VerseSearchResult> results, String recognizedText) onResults,
    required void Function(String error) onError,
    bool? adaptiveNoise,
  }) async {
    if (_isListening) {
      await stopListening();
    }

    if (!_isInitialized) {
      await initialize();
    }

    final permitted = await hasPermission();
    if (!permitted) {
      const err = 'Microphone permission not granted';
      onError(err);
      throw Exception(err);
    }

    if (adaptiveNoise != null) {
      _adaptiveNoise = adaptiveNoise;
    }
    _ambientNoiseFloor = 0.008;
    _calibrationFramesRemaining = 8;
    _isSearchMode = true;
    _onSearchAudioLevel = onAudioLevel;
    _onSearchResults = onResults;

    _speechBuffer.clear();
    _accumulatedTokens.clear();
    _trailingSilenceCount = 0;
    _speechActive = false;

    _audioRecorder ??= AudioRecorder();

    try {
      final audioStream = await _audioRecorder!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

      _isListening = true;

      _audioSubscription = audioStream.listen(
        _processAudioChunk,
        onError: (err) {
          debugPrint('[RecitationEngine] Audio stream error: $err');
          onError(err.toString());
        },
      );
    } catch (e) {
      debugPrint('[RecitationEngine] startVoiceSearch error: $e');
      onError('Failed to start audio stream: $e');
      rethrow;
    }
  }

  /// Stops listening and releases active audio stream.
  Future<void> stopListening() async {
    _isListening = false;
    _speechActive = false;
    _isSearchMode = false;
    _onSearchAudioLevel = null;
    _onSearchResults = null;
    _trailingSilenceCount = 0;

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (_audioRecorder != null) {
      final rec = _audioRecorder;
      _audioRecorder = null;
      try {
        await rec?.stop().timeout(const Duration(milliseconds: 500), onTimeout: () => null);
      } catch (_) {}
      try {
        await rec?.dispose().timeout(const Duration(milliseconds: 500), onTimeout: () => null);
      } catch (_) {}
    }

    _speechBuffer.clear();
    _accumulatedTokens.clear();

    _onEvent?.call(RecitationStatusEvent(
      status: RecitationStatus.idle,
      audioLevel: 0.0,
      currentExpectedAyah: _expectedAyah,
    ));
  }

  /// Processes incoming PCM 16-bit chunks from microphone.
  void _processAudioChunk(Uint8List pcmChunk) {
    if (!_isListening || pcmChunk.isEmpty) return;

    final numSamples = pcmChunk.length ~/ 2;
    if (numSamples == 0) return;

    final byteData = ByteData.sublistView(pcmChunk);
    final samples = Float32List(numSamples);
    double sumSquares = 0.0;

    for (int i = 0; i < numSamples; i++) {
      final sampleInt = byteData.getInt16(i * 2, Endian.little);
      final s = sampleInt / 32768.0;
      samples[i] = s;
      sumSquares += s * s;
    }

    final rms = math.sqrt(sumSquares / numSamples);

    if (_adaptiveNoise && _calibrationFramesRemaining > 0) {
      _calibrationFramesRemaining--;
      if (rms > 0.002 && rms < 0.050) {
        _ambientNoiseFloor = (_ambientNoiseFloor * 0.7) + (rms * 0.3);
      }
    }

    final double effectiveThreshold;
    if (_adaptiveNoise) {
      effectiveThreshold = (_ambientNoiseFloor * 1.75).clamp(0.010, 0.045);
      // Slow continuous background adaptation during silence
      if (!_speechActive && rms < _ambientNoiseFloor * 1.5 && rms > 0.002) {
        _ambientNoiseFloor = (_ambientNoiseFloor * 0.95) + (rms * 0.05);
        _ambientNoiseFloor = _ambientNoiseFloor.clamp(0.005, 0.035);
      }
    } else {
      effectiveThreshold = _silenceThreshold;
    }

    final isVoice = rms > effectiveThreshold;
    final level = _adaptiveNoise
        ? math.min(1.0, math.max(0.0, rms - _ambientNoiseFloor) * 15.0)
        : math.min(1.0, rms * 15.0);

    if (isVoice) {
      _speechActive = true;
      _trailingSilenceCount = 0;
      _speechBuffer.addAll(samples);

      if (_isSearchMode) {
        _onSearchAudioLevel?.call(level);
      } else {
        _onEvent?.call(RecitationStatusEvent(
          status: RecitationStatus.listening,
          audioLevel: level,
          currentExpectedAyah: _expectedAyah,
        ));
      }

      // If speech buffer exceeds max threshold, trigger inference immediately
      if (_speechBuffer.length >= _maxSpeechSamples && !_isInferring) {
        _triggerInference();
      }
    } else {
      if (_speechActive) {
        _trailingSilenceCount++;
        // Include short trailing silence to capture final consonants
        if (_speechBuffer.length < _maxSpeechSamples) {
          _speechBuffer.addAll(samples);
        }

        // Trigger inference when silence after speech is detected
        if (_trailingSilenceCount >= _silenceFramesNeeded &&
            _speechBuffer.length >= _minSpeechSamples &&
            !_isInferring) {
          _speechActive = false;
          _triggerInference();
        }
      }
    }
  }

  /// Runs ONNX inference on accumulated speech samples asynchronously.
  Future<void> _triggerInference() async {
    if (_speechBuffer.isEmpty || _isInferring || _session == null || _matcher == null) {
      return;
    }

    _isInferring = true;
    _onEvent?.call(RecitationStatusEvent(
      status: RecitationStatus.processing,
      audioLevel: 0.0,
      currentExpectedAyah: _expectedAyah,
    ));

    final samples = Float32List.fromList(_speechBuffer);
    _speechBuffer.clear();

    try {
      final numSamples = samples.length;
      final audioTensor = OrtValueTensor.createTensorWithDataList(
        samples,
        [1, numSamples],
      );
      final lengthTensor = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList([numSamples]),
        [1],
      );

      final runOptions = OrtRunOptions();
      final inputs = {
        _session!.inputNames[0]: audioTensor,
        _session!.inputNames[1]: lengthTensor,
      };

      // Dispatches inference to native background isolate
      final outputs = await _session!.runAsync(runOptions, inputs);

      audioTensor.release();
      lengthTensor.release();
      runOptions.release();

      if (!_isListening) {
        outputs?.forEach((o) => o?.release());
        return;
      }

      if (outputs != null && outputs.isNotEmpty) {
        final val = outputs[0]?.value;
        if (val is List && val.isNotEmpty && val[0] is List) {
          final outer = val[0] as List;
          // Outer has shape [time_frames, 1025]
          final logProbs = <List<double>>[];
          for (final frame in outer) {
            if (frame is List) {
              logProbs.add(frame.map((e) => (e as num).toDouble()).toList(growable: false));
            }
          }

          if (logProbs.isNotEmpty) {
            final decoded = _matcher!.greedyDecode(logProbs);
            if (decoded.isNotEmpty) {
              final decodedText = _matcher!.tokensToText(decoded);
              debugPrint('[RecitationEngine] Decoded chunk: $decoded ($decodedText)');

              // Combine accumulated buffer from previous chunks with incoming decoded tokens
              var activeTokens = List<int>.from(_accumulatedTokens)..addAll(decoded);
              var activeText = _matcher!.tokensToText(activeTokens);
              _accumulatedTokens.clear();

              debugPrint('[RecitationEngine] Active tokens: ${activeTokens.length}, text: "$activeText"');

              if (_isSearchMode) {
                final results = _matcher!.searchVerses(activeTokens, limit: 5);
                _onSearchResults?.call(results, activeText);
                return;
              }

              // Cascading match loop: continuously match consecutive verses in the active window (Wasl / continuous recitation)
              while (_expectedAyah <= _endAyah && activeTokens.isNotEmpty) {
                final match = _matcher!.matchSlidingWindow(
                  surah: _currentSurah,
                  expectedAyah: _expectedAyah,
                  candidateTokens: activeTokens,
                  candidateText: activeText,
                  windowAhead: 2,
                  windowBehind: 1,
                  minAyah: _startAyah,
                  maxAyah: _endAyah,
                  sensitivity: _sensitivity,
                );

                if (match == null) {
                  // No match on expected or skip in current candidate.
                  // Retain active tokens for subsequent chunk accumulation.
                  _accumulatedTokens.addAll(activeTokens);
                  break;
                }

                if (match.isSkip) {
                  // Skip detected!
                  debugPrint('[RecitationEngine] SKIP DETECTED from ${match.expectedAyah} to ${match.detectedAyah}');
                  _onEvent?.call(RecitationSkippedEvent(
                    surah: match.surah,
                    expectedAyah: match.expectedAyah,
                    jumpedToAyah: match.detectedAyah,
                    confidence: match.confidence,
                  ));

                  // Retain expected Ayah! Do NOT advance automatically on skip detection.
                  // Clear accumulated tokens so the alert does not fire repeatedly on same audio.
                  _accumulatedTokens.clear();
                  break;
                }

                // Matched expected verse or previous verse!
                debugPrint('[RecitationEngine] REVEAL Matched Ayah ${match.detectedAyah} (conf: ${match.confidence.toStringAsFixed(2)})');
                _expectedAyah = math.max(_expectedAyah, match.detectedAyah + 1);

                _onEvent?.call(RecitationMatchedEvent(
                  surah: match.surah,
                  ayah: match.detectedAyah,
                  confidence: match.confidence,
                  text: match.decodedText,
                ));

                // Slicing: consume the matched verse from active tokens/words to test next verse
                final candWords = activeText.split(' ').where((w) => w.isNotEmpty).toList();
                if (match.wordsConsumed > 0 && match.wordsConsumed < candWords.length) {
                  // Slice consumed words from activeText
                  final remainingWords = candWords.sublist(match.wordsConsumed);
                  activeText = remainingWords.join(' ');

                  // Proportionally drop consumed tokens
                  final dropRatio = match.wordsConsumed / candWords.length;
                  final tokensToDrop = (activeTokens.length * dropRatio).round().clamp(1, activeTokens.length - 1);
                  activeTokens = activeTokens.sublist(tokensToDrop);
                } else if (match.tokensConsumed > 0 && match.tokensConsumed < activeTokens.length) {
                  activeTokens = activeTokens.sublist(match.tokensConsumed);
                  activeText = _matcher!.tokensToText(activeTokens);
                } else {
                  // Whole buffer consumed by this match
                  activeTokens.clear();
                  activeText = '';
                  break;
                }
              }

              // Keep accumulated tokens within reasonable size based on expected ayah length
              final expectedTokensLen =
                  _matcher?.getTargetTokens(_currentSurah, _expectedAyah)?.length ?? 40;
              final maxBuffer = math.max(100, (expectedTokensLen * 1.8).round());
              if (_accumulatedTokens.length > maxBuffer) {
                _accumulatedTokens.removeRange(
                    0, _accumulatedTokens.length - expectedTokensLen);
              }
            }
          }
        }
      }

      outputs?.forEach((o) => o?.release());
    } catch (e, st) {
      debugPrint('[RecitationEngine] Inference exception: $e\n$st');
    } finally {
      _isInferring = false;
      if (_isListening) {
        _onEvent?.call(RecitationStatusEvent(
          status: RecitationStatus.listening,
          audioLevel: 0.0,
          currentExpectedAyah: _expectedAyah,
        ));
      }
    }
  }

  /// Disposes resources.
  void dispose() {
    stopListening();
    _session?.release();
    _sessionOptions?.release();
    OrtEnv.instance.release();
    _audioRecorder?.dispose();
    _isInitialized = false;
  }
}

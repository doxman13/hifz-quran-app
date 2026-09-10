import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FootnoteItem {
  final int id;
  final int origId;
  final String text;

  FootnoteItem({
    required this.id,
    required this.origId,
    required this.text,
  });

  factory FootnoteItem.fromJson(Map<String, dynamic> json) {
    return FootnoteItem(
      id: json['id'] as int? ?? 0,
      origId: json['origId'] as int? ?? 0,
      text: json['text'] as String? ?? '',
    );
  }
}

class FootnoteEntry {
  final String annotated;
  final List<FootnoteItem> footnotes;

  FootnoteEntry({
    required this.annotated,
    required this.footnotes,
  });
}

/// Top-level parser for isolate execution via [compute].
Map<String, FootnoteEntry> parseFootnotesJson(String jsonStr) {
  final Map<String, dynamic> rawMap = jsonDecode(jsonStr);
  return rawMap.map((key, value) {
    final rawFns = (value['footnotes'] as List<dynamic>?) ?? [];
    return MapEntry(
      key,
      FootnoteEntry(
        annotated: value['annotated'] as String? ?? '',
        footnotes: rawFns.map((f) => FootnoteItem.fromJson(f as Map<String, dynamic>)).toList(),
      ),
    );
  });
}

class FootnoteService extends ChangeNotifier {
  static final FootnoteService _instance = FootnoteService._internal();
  factory FootnoteService() => _instance;
  FootnoteService._internal();

  Map<String, FootnoteEntry>? _thaiFootnotes;
  Map<String, FootnoteEntry>? _saheehFootnotes;
  Map<String, FootnoteEntry>? _hilaliKhanFootnotes;
  Map<String, FootnoteEntry>? _bridgesFootnotes;
  bool _isLoading = false;
  Future<void>? _initFuture;

  bool get isThaiLoaded => _thaiFootnotes != null;
  bool get isSaheehLoaded => _saheehFootnotes != null;
  bool get isHilaliKhanLoaded => _hilaliKhanFootnotes != null;
  bool get isBridgesLoaded => _bridgesFootnotes != null;
  bool get isFullyLoaded =>
      _thaiFootnotes != null &&
      _saheehFootnotes != null &&
      _hilaliKhanFootnotes != null &&
      _bridgesFootnotes != null;

  Future<void> init() {
    if (isFullyLoaded) {
      return Future.value();
    }
    if (_initFuture != null) {
      return _initFuture!;
    }
    _initFuture = _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    _isLoading = true;

    try {
      // 1. Prioritize Thai footnotes (primary translation of the app)
      if (_thaiFootnotes == null) {
        final thStr = await rootBundle.loadString('assets/footnotes/thai_footnotes.json');
        _thaiFootnotes = await compute(parseFootnotesJson, thStr);
        notifyListeners();
      }

      // 2. Load other translation footnotes concurrently without blocking UI
      await Future.wait([
        if (_saheehFootnotes == null)
          rootBundle.loadString('assets/footnotes/en_saheeh_footnotes.json')
              .then((s) => compute(parseFootnotesJson, s))
              .then((map) {
                _saheehFootnotes = map;
                notifyListeners();
              }),
        if (_hilaliKhanFootnotes == null)
          rootBundle.loadString('assets/footnotes/en_hilali_khan_footnotes.json')
              .then((s) => compute(parseFootnotesJson, s))
              .then((map) {
                _hilaliKhanFootnotes = map;
                notifyListeners();
              }),
        if (_bridgesFootnotes == null)
          rootBundle.loadString('assets/footnotes/en_bridges_footnotes.json')
              .then((s) => compute(parseFootnotesJson, s))
              .then((map) {
                _bridgesFootnotes = map;
                notifyListeners();
              }),
      ]);
    } catch (e, stack) {
      debugPrint('FootnoteService init error: $e\n$stack');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  FootnoteEntry? getEntry(String verseKey, String translationId) {
    final lower = translationId.toLowerCase();
    if (lower == 'en_saheeh' || lower == 'english' || lower == '20') {
      if (_saheehFootnotes == null && !_isLoading) unawaited(init());
      return _saheehFootnotes?[verseKey];
    }
    if (lower == 'en_hilali_khan' || lower == '203' || lower.contains('hilali')) {
      if (_hilaliKhanFootnotes == null && !_isLoading) unawaited(init());
      return _hilaliKhanFootnotes?[verseKey];
    }
    if (lower == 'en_bridges' || lower == '149' || lower.contains('bridges')) {
      if (_bridgesFootnotes == null && !_isLoading) unawaited(init());
      return _bridgesFootnotes?[verseKey];
    }
    if (lower == 'thai_v3' || lower == 'thai_v2' || lower == 'thai_orig' || lower.startsWith('th')) {
      if (_thaiFootnotes == null && !_isLoading) unawaited(init());
      return _thaiFootnotes?[verseKey];
    }
    return null;
  }
}

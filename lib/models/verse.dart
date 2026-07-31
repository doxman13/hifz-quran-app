// lib/models/verse.dart
import '../shared/quran_contract.dart';

class Verse {
  final String id;
  final String surahId;
  String arabic;
  final String thaiV3;
  final String thaiV2;
  final String english;
  final String? shortTafsir;
  final String? shortTafsirSource;
  final String? shortTafsirEn;
  final String? shortTafsirSourceEn;
  bool isArabicLoading;
  bool isArabicVisible;

  String get verseKey => createVerseKey(surahId, id);

  Verse({
    required this.id,
    required this.surahId,
    required this.arabic,
    required this.thaiV3,
    required this.thaiV2,
    required this.english,
    this.shortTafsir,
    this.shortTafsirSource,
    this.shortTafsirEn,
    this.shortTafsirSourceEn,
    this.isArabicLoading = false,
    this.isArabicVisible = false,
  });
}

import "package:flutter_test/flutter_test.dart";
import "package:hifz_space/shared/translation_hierarchy.dart";

void main() {
  group("TranslationHierarchy Tests", () {
    test("Static groups contain Thai, English, and Malay", () {
      final groups = TranslationHierarchy.getAllLanguageGroups();
      expect(groups.map((g) => g.id).toList(), containsAll(["thai", "english", "malay"]));
    });

    test("Thai group has exactly one standard edition: thai_v3", () {
      final groups = TranslationHierarchy.getAllLanguageGroups(
        downloadedTranslations: [
          {"id": "230", "language_name": "thai", "name": "Thai Old"},
          {"id": "51", "language_name": "thai", "name": "Thai 51"},
        ],
      );
      final thaiGroup = groups.firstWhere((g) => g.id == "thai");
      expect(thaiGroup.editions.length, 1);
      expect(thaiGroup.editions.first.id, "thai_v3");
      expect(thaiGroup.editions.first.isRecommended, isTrue);
      expect(thaiGroup.editions.first.isBundled, isTrue);
    });

    test("English group has 5 ordered editions matching web", () {
      final groups = TranslationHierarchy.getAllLanguageGroups();
      final enGroup = groups.firstWhere((g) => g.id == "english");
      expect(enGroup.editions.length, 5);
      expect(enGroup.editions[0].id, "20"); // Saheeh
      expect(enGroup.editions[1].id, "203"); // Hilali-Khan
      expect(enGroup.editions[2].id, "149"); // Bridges
      expect(enGroup.editions[3].id, "85"); // Abdel Haleem
      expect(enGroup.editions[4].id, "en_usmani"); // Usmani
    });

    test("Malay group contains Basmeih edition", () {
      final groups = TranslationHierarchy.getAllLanguageGroups();
      final msGroup = groups.firstWhere((g) => g.id == "malay");
      expect(msGroup.editions.length, 1);
      expect(msGroup.editions.first.id, "ms_basmeih");
      expect(msGroup.editions.first.apiId, 39);
    });

    test("getLanguageForTranslationId maps legacy & aliases accurately", () {
      expect(TranslationHierarchy.getLanguageForTranslationId("thai_v3"), "thai");
      expect(TranslationHierarchy.getLanguageForTranslationId("thai_orig"), "thai");
      expect(TranslationHierarchy.getLanguageForTranslationId("230"), "thai");
      expect(TranslationHierarchy.getLanguageForTranslationId("51"), "thai");
      expect(TranslationHierarchy.getLanguageForTranslationId("en_saheeh"), "english");
      expect(TranslationHierarchy.getLanguageForTranslationId("20"), "english");
      expect(TranslationHierarchy.getLanguageForTranslationId("203"), "english");
      expect(TranslationHierarchy.getLanguageForTranslationId("149"), "english");
      expect(TranslationHierarchy.getLanguageForTranslationId("en_usmani"), "english");
      expect(TranslationHierarchy.getLanguageForTranslationId("ms_basmeih"), "malay");
      expect(TranslationHierarchy.getLanguageForTranslationId("39"), "malay");
    });

    test("Dynamic downloaded languages other than Thai appear in groups", () {
      final groups = TranslationHierarchy.getAllLanguageGroups(
        downloadedTranslations: [
          {"id": "31", "language_name": "french", "name": "French Translation", "author_name": "Hamidullah"},
        ],
      );
      final frenchGroup = groups.where((g) => g.id == "other" || g.id == "french");
      expect(frenchGroup.isNotEmpty, isTrue);
    });
  });
}

const fs = require('fs');
const content = fs.readFileSync('assets/surahNames.ts', 'utf8');
const enMatch = content.match(/STATIC_SURAH_NAMES: Record<string, string> = {([^}]*)}/s);
const thMatch = content.match(/STATIC_SURAH_NAMES_THAI: Record<string, string> = {([^}]*)}/s);

if (enMatch && thMatch) {
  const en = enMatch[1].trim();
  const th = thMatch[1].trim();
  let dartCode = `// Auto-generated Surah Names

const Map<String, String> offlineSurahNamesEn = {
  ${en}
};

const Map<String, String> offlineSurahNamesTh = {
  ${th}
};
`;
  fs.writeFileSync('lib/data/offline_surah_names.dart', dartCode);
  console.log('Generated offline_surah_names.dart');
} else {
  console.log('Failed to match');
}

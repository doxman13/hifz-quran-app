import json
import re

def strip_tajweed_meems(text):
    # Remove U+06E2 (small high meem) and U+06ED (small low meem)
    return text.replace('\u06e2', '').replace('\u06ed', '')

with open('assets/quran_tajweed.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for key in data:
    data[key] = strip_tajweed_meems(data[key])

with open('assets/quran_tajweed.json', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))

print("Done stripping small meems!")

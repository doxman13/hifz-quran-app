import json
import urllib.request
import re
import difflib
import concurrent.futures
import time

def parse_tajweed(html_str):
    pattern = re.compile(r'(<rule[^>]*>)(.*?)(</rule>)')
    plain_text = ""
    tags = []
    last_idx = 0
    for match in pattern.finditer(html_str):
        before_text = html_str[last_idx:match.start()]
        plain_text += before_text
        start_tag = match.group(1)
        inner_text = match.group(2)
        end_tag = match.group(3)
        start_idx = len(plain_text)
        plain_text += inner_text
        end_idx = len(plain_text)
        tags.append((start_idx, end_idx, start_tag, end_tag))
        last_idx = match.end()
    plain_text += html_str[last_idx:]
    return plain_text, tags

def align_and_map(uthmani_text, tajweed_html):
    plain_tajweed, tags = parse_tajweed(tajweed_html)
    if uthmani_text == tajweed_html:
        return uthmani_text
    matcher = difflib.SequenceMatcher(None, plain_tajweed, uthmani_text)
    def map_index(idx):
        for tag_i, tag_j, tag_n in matcher.get_matching_blocks():
            if tag_i <= idx < tag_i + tag_n:
                return tag_j + (idx - tag_i)
            elif idx < tag_i:
                return tag_j
        return len(uthmani_text)
    mapped_tags = []
    for start_idx, end_idx, start_tag, end_tag in tags:
        mapped_start = map_index(start_idx)
        mapped_end = map_index(end_idx)
        mapped_tags.append((mapped_start, mapped_end, start_tag, end_tag))
    result = uthmani_text
    for mapped_start, mapped_end, start_tag, end_tag in reversed(mapped_tags):
        result = result[:mapped_end] + end_tag + result[mapped_end:]
        result = result[:mapped_start] + start_tag + result[mapped_start:]
    return result

def fetch_page(page):
    url = f"https://api.quran.com/api/v4/verses/by_page/{page}?words=true&word_fields=text_qpc_hafs,text_uthmani_tajweed"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=15) as response:
                return page, json.loads(response.read().decode('utf-8'))
        except Exception as e:
            if attempt == 2:
                print(f"Failed page {page}: {e}")
                return page, None
            time.sleep(1)

def main():
    print("Starting generation for 604 pages...")
    result_dict = {}
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        futures = {executor.submit(fetch_page, p): p for p in range(1, 605)}
        for count, future in enumerate(concurrent.futures.as_completed(futures), 1):
            page, data = future.result()
            if data is None: continue
            
            for verse in data.get('verses', []):
                verse_key = verse['verse_key']
                for w in verse.get('words', []):
                    if w['char_type_name'] != 'word':
                        continue
                    uthmani = w.get('text_qpc_hafs', '')
                    tajweed_html = w.get('text_uthmani_tajweed', '')
                    if tajweed_html:
                        mapped = align_and_map(uthmani, tajweed_html)
                        pos = w['position']
                        key = f"{verse_key}:{pos}"
                        result_dict[key] = mapped
            
            if count % 50 == 0:
                print(f"Processed {count}/604 pages")
                
    out_path = 'assets/quran_tajweed.json'
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(result_dict, f, ensure_ascii=False, separators=(',', ':'))
    print(f"\nSaved {len(result_dict)} words to {out_path}")

if __name__ == '__main__':
    main()

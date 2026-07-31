import json
import urllib.request
import re
import difflib
import os

def fetch_verse(verse_key):
    url = f"https://api.quran.com/api/v4/verses/by_key/{verse_key}?words=true&word_fields=text_qpc_hafs,text_uthmani,text_uthmani_tajweed"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode('utf-8'))

def parse_tajweed(html_str):
    """
    Returns a tuple (plain_text, tags)
    tags is a list of tuples: (start_idx_in_plain, end_idx_in_plain, start_tag, end_tag)
    """
    pattern = re.compile(r'(<rule[^>]*>)(.*?)(</rule>)')
    
    plain_text = ""
    tags = []
    
    last_idx = 0
    for match in pattern.finditer(html_str):
        # Text before the tag
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
    
    # If there are no tags or they are identical, just return as is (with tags)
    if uthmani_text == tajweed_html:
        return uthmani_text
        
    # Sequence matcher to find matching blocks between plain_tajweed and uthmani_text
    matcher = difflib.SequenceMatcher(None, plain_tajweed, uthmani_text)
    
    def map_index(idx):
        """Map an index from plain_tajweed to uthmani_text"""
        for tag_i, tag_j, tag_n in matcher.get_matching_blocks():
            if tag_i <= idx < tag_i + tag_n:
                return tag_j + (idx - tag_i)
            # If the index falls in an unmapped gap, we map it to the closest match
            elif idx < tag_i:
                return tag_j
        return len(uthmani_text)
        
    mapped_tags = []
    for start_idx, end_idx, start_tag, end_tag in tags:
        mapped_start = map_index(start_idx)
        mapped_end = map_index(end_idx)
        mapped_tags.append((mapped_start, mapped_end, start_tag, end_tag))
        
    # Reconstruct the string with tags inserted in uthmani_text
    # We must insert from the end to not mess up previous indices
    result = uthmani_text
    for mapped_start, mapped_end, start_tag, end_tag in reversed(mapped_tags):
        result = result[:mapped_end] + end_tag + result[mapped_end:]
        result = result[:mapped_start] + start_tag + result[mapped_start:]
        
    return result

def main():
    print("Fetching verse 2:4...")
    data = fetch_verse("2:4")
    words = data['verse']['words']
    
    results = []
    for w in words:
        if w['char_type_name'] != 'word':
            continue
            
        uthmani = w['text_uthmani']
        tajweed_html = w['text_uthmani_tajweed']
        
        mapped = align_and_map(uthmani, tajweed_html)
        results.append({
            'id': w['id'],
            'text_uthmani': uthmani,
            'original_tajweed': tajweed_html,
            'mapped_tajweed': mapped
        })
        
    # Save to file
    out_path = 'test_2_4_mapped.json'
    with open(out_path, 'w', encoding='utf-8') as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f"\nSaved results to {out_path}")

if __name__ == '__main__':
    main()

# Chinese Text Encoding Corruption Recovery

## Problem Pattern

Chinese company names and text arrive garbled when GBK-encoded bytes are misinterpreted as Unicode code points. Common in:
- Excel/CSV exports from legacy Windows systems
- Copy-paste from older ERP/CRM systems
- JSON payloads with encoding mismatches
- Web form submissions with charset issues

## Typical Corruption Signature

Original text: `深圳市XX通信科技有限公司`
Garbled output: Characters like `ͨ`, `ſ`, `Ƽ`, `ι`, `˾` (Greek, Latin Extended, IPA characters mixed)
Region garbled: `ʡ` instead of `广东省`

### Technical Root Cause

1. Original text encoded in GBK (2 bytes per Chinese character)
2. Each GBK byte pair interpreted as a single Unicode code point
3. Result: characters in U+0100–U+0500 range (Latin Extended, Greek, Cyrillic)
4. Sometimes every other byte is dropped, causing irreversible data loss

### Recovery Approach

**Step 1: Quick test (30 seconds)**
```python
garbled = "ͨſƼι˾"  # The garbled text
try:
    b = garbled.encode('utf-8')
    recovered = b.decode('gbk', errors='replace')
    # Check if result contains coherent Chinese characters
    chinese_chars = sum(1 for c in recovered if '\u4e00' <= c <= '\u9fff')
    if chinese_chars >= len(garbled) * 0.5:
        print(f"Recovered: {recovered}")
except:
    pass
```

**Step 2: Validate partial recovery**
- If you get partial Chinese like `通趴萍喂司` (should be `通信科技有限公司`), the encoding IS GBK but bytes were dropped
- Common suffixes to pattern-match: `科技有限公司`, `有限公司`, `股份公司`, `集团`
- Common province endings: `省` (from `ʡ`)

**Step 3: Time-box decision (IMPORTANT)**

⚠️ **DO NOT spend more than 2-3 tool calls on encoding recovery.** If Step 1 produces garbage or only partial results, immediately ask the user to re-provide the company name.

Exhaustive decoding attempts (trying all encoding pairs, triple-decode chains, byte manipulation) rarely succeed when bytes were dropped and waste valuable session time.

## When to Ask vs. When to Persist

**Ask the user immediately if:**
- UTF-8 → GBK produces < 50% recognizable Chinese characters
- You can identify the suffix (`科技有限公司`, `省`) but not the prefix/brand name
- First two encoding attempts fail
- The garbled text contains many characters outside U+0100–U+0500 range

**Try one more approach if:**
- UTF-8 → GBK produces mostly coherent Chinese with 1-2 wrong characters
- You can identify both prefix and suffix patterns
- The corruption looks systematic (same pattern across all characters)

## Common Encoding Pairs to Try (in order)

1. `text.encode('utf-8').decode('gbk')` — most common for Chinese
2. `text.encode('gbk').decode('utf-8')` — reverse corruption
3. `text.encode('cp1252').decode('gbk')` — Windows legacy systems
4. `text.encode('iso-8859-1').decode('gbk')` — Latin-1 misinterpretation

## Example Session Flow

**Bad (what NOT to do):**
```
Turn 1: Try UTF-8 → GBK (partial success)
Turn 2: Try GBK → UTF-8 (fails)
Turn 3: Try all encoding pairs in a loop
Turn 4: Analyze byte patterns in detail
Turn 5: Check if characters match common company suffixes
Turn 6: Finally ask user to re-provide name
```
Result: 6 turns wasted, user frustrated

**Good (efficient approach):**
```
Turn 1: Try UTF-8 → GBK, recognize partial recovery
Turn 2: Identify that prefix is unrecoverable, ask user immediately
```
Result: 2 turns, clear communication

## Prevention Tips for Users

When users report encoding issues, suggest:
- Export data as UTF-8 CSV (not GBK/ANSI)
- Use modern Excel (2016+) which defaults to UTF-8
- Set system locale to UTF-8 in Windows settings
- Use API integrations instead of manual copy-paste

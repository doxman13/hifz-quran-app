# Thai Quran Shared Upgrade Contract

This contract is shared by the web and Flutter apps. Keep both repos aligned to
these names before adding database sync, auth, or public community features.

## Product Scope

- Keep reading usable without login.
- Use login only for sync, backup, public Tadabbur notes, and report ownership.
- Use one backend identity across web and app.
- Keep translation corrections separate from user reflections.

## Current Web Implementation Snapshot

This is the state implemented in `thai-quran-web` as of commit `6ca5a9d`.
Flutter should mirror these contracts before adding real cloud sync.

- Mock local login exists for web testing:
  - username: `admin`
  - password: `admin`
- Reading works without login.
- Settings live in a modal opened from the header/settings button.
- Dashboard shows one recent reading item and links to a separate bookmarks page.
- Reader header shows active reading profile name and current surah name.
- `Free Read` is the default profile. It has no target, no progress bar, and no archive option.
- User-created reading profiles support plan modes:
  - `by_juz`
  - `by_surah`
  - `by_ayat`
  - `custom`
- User-created profile creation uses dropdowns for start/end surah and ayah.
- Bookmarks are saved as verse rows, not one bookmark slot per profile.
- Recent readings replace legacy Last Read.
- Verse tools are kept in the same fixed action row:
  - Tadabbur note
  - Bookmark
  - Share
  - Short tafsir
  - Report translation error
  - Arabic show/hide
- Bismillah is rendered before every surah except At-Tawbah, including Al-Fatihah.
- Thai Mokhtasar short tafsir is bundled locally for all 6,236 ayat.
- Surah summary is currently only a local draft for Surah 114.

Important local files on web:

```text
src/lib/shared/quranContract.ts
src/lib/shared/localReadingStore.ts
src/lib/shared/shareFormatter.ts
src/data/tafsirThaiMokhtasar.ts
```

## Auth

Recommended providers:

- Google
- Apple, especially for iOS release
- Email magic link
- Guest mode with local-only data

The backend `user_id` must be the same identity used by every synced table.
Guest users can keep local data and migrate it after login.

## Canonical IDs

Use these names everywhere:

```text
surah_id: string
verse_id: string
verse_key: "{surah_id}:{verse_id}"
```

Examples:

```text
1:1
2:255
114:6
```

Do not sync progress by list index. Use `verse_id`.

## Translation Data

Canonical translation row:

```text
translations
- id
- surah_id
- verse_id
- verse_key
- version          // thai_v3, thai_v2, english
- language         // th, en
- text
- source
- updated_at
```

Both apps may keep bundled translations as offline fallback, but the runtime
loader should prefer the cloud source when available.

## Short Tafsir Data

Short tafsir is separate from translation text. The web app currently bundles
Thai Mokhtasar tafsir from QuranEnc for every ayah.

Source:

```text
https://quranenc.com/api/v1/translation/sura/thai_mokhtasar/{surah_id}
```

Local web shape:

```text
SHORT_TAFSIR_TH[surah_id][verse_id]
- text
- source
```

Canonical backend row:

```text
verse_tafsir
- id
- surah_id
- verse_id
- verse_key
- tafsir_key       // thai_mokhtasar
- language         // th
- text
- source           // QuranEnc Thai Mokhtasar
- source_url
- updated_at
```

Use `verse_key` for joins in both apps. The tafsir icon should only appear when
a tafsir row exists for that verse. The tafsir panel is read-only.

Surah summaries/objectives are a separate feature:

```text
surah_summaries
- id
- surah_id
- language
- title nullable
- summary_text
- source
- source_url nullable
- updated_at
```

Do not infer surah summaries from ayah tafsir. Only show summaries when a real
summary row exists. Web currently has one local draft summary for Surah 114.

## Reading Profiles

Reading profiles are user-created reading plans/bookmark lanes. They must not
overwrite each other. Examples:

```text
Free Read
Ramadan 2026
Memorization Review
Family Reading
```

Free Read is the default targetless profile. It cannot be archived and should
not show a progress bar. Other profiles can choose where to start and where
they aim to end. Current progress is stored per profile.

Users should have up to 5 active reading profiles. Archived profiles do not
count toward this limit and can be restored later if there is an active slot.

Plan modes supported by the current web UI:

```text
by_juz
by_surah
by_ayat
custom
```

For `by_juz`, store `start_juz` and `target_juz` when backend support is added.
For `by_surah`, store `start_surah_id` and `target_surah_id`; ayah defaults can
be resolved by the app. For `by_ayat` and `custom`, store explicit start and
target verse refs.

`audit_check` should not be a reading profile. Replace that flow with
`report_error`.

```text
reading_profiles
- id
- user_id
- name
- slug
- plan_mode nullable
- start_juz nullable
- target_juz nullable
- start_surah_id
- start_verse_id
- start_verse_key
- target_surah_id nullable
- target_verse_id nullable
- target_verse_key nullable
- current_surah_id
- current_verse_id
- current_verse_key
- furthest_unread_index
- last_viewed_index
- sort_order
- is_archived
- created_at
- updated_at
```

Default profiles can be created for new users:

```text
free_read
```

Do not model "Last Read" as a reading profile. Use recent readings instead.

```text
mushaf_profiles
- current_page
- furthest_unread_page
- last_viewed_page
```

## Bookmarks

Bookmarks are saved verse references. Users can have multiple bookmarks per
category. Most categories should allow at least 5 items.

```text
bookmark_categories
- id
- user_id
- name
- slug
- max_items       // default 5
- sort_order
- created_at
- updated_at

bookmarks
- id
- user_id
- category_id
- surah_id
- verse_id
- verse_key
- label nullable
- note nullable
- sort_order
- created_at
- updated_at
```

## Recent Readings

Recent readings replace the single "Last Read" profile. Keep the latest 10-20
items per user/device.

Current web local limit:

```text
20
```

```text
recent_readings
- id
- user_id
- surah_id
- verse_id
- verse_key
- profile_id nullable
- read_at
```

## Reading History

Store unique verses per local calendar day:

```text
user_reading_history
- id
- user_id
- read_date        // YYYY-MM-DD
- verse_key
- surah_id
- verse_id
- created_at
```

Daily, weekly, monthly, and streak stats should be derived from this data.

## Completed Surahs

Use rows or arrays of surah IDs, not only counts.

```text
user_completed_surahs
- id
- user_id
- mode             // read, review
- surah_id
- completed_at
```

## Settings

Canonical setting names:

```text
theme_color
is_dark_mode
always_show_arabic
arabic_font_family
arabic_font_size
thai_font_family
thai_font_size
show_thai_v3
show_thai_v2
show_english
```

## Report Error

Reports are user feedback. They do not directly edit translations.

```text
translation_reports
- id
- user_id nullable
- surah_id
- verse_id
- verse_key
- translation_version  // thai_v3, thai_v2, english
- issue_type           // typo, meaning, missing_text, formatting, other
- comment
- suggested_text nullable
- status               // open, reviewing, accepted, rejected, fixed
- reviewer_note nullable
- source               // web, flutter
- created_at
- updated_at
```

Only admins/reviewers should update the canonical `translations` table.

Current web still posts reports to the legacy endpoint:

```text
https://quran.salamthailand.com/save_audit.php
```

When the real backend is added, both web and Flutter should switch to
`translation_reports` using the schema below.

## Tadabbur Notes

Use the Islamic term in the feature name.

Preferred Thai label:

```text
บันทึกตะดับบุร
```

Helpful Thai descriptor:

```text
ข้อคิด / การใคร่ครวญจากอายะฮฺนี้
```

```text
tadabbur_notes
- id
- user_id
- surah_id
- verse_id
- verse_key
- note_text
- visibility       // private, public
- language         // th, en
- status           // active, hidden, reported, removed
- created_at
- updated_at
```

Optional later:

```text
tadabbur_reactions
- id
- note_id
- user_id
- reaction_type    // helpful, heart
- created_at

tadabbur_reports
- id
- note_id
- reporter_user_id
- reason
- created_at
```

## Sharing

Sharing is separate from publishing Tadabbur notes. A quick share note may be
temporary unless the user chooses to save it.

Share options:

```text
translation_only
arabic_and_translation
translation_with_quick_note
arabic_translation_with_quick_note
```

Canonical share payload:

```text
SharePayload
- surah_id
- verse_id
- verse_key
- surah_name
- arabic nullable
- translation
- translation_version
- quick_note nullable
- url
```

Thai text format:

```text
{surah_name} {surah_id}:{verse_id}

{translation}

บันทึกของฉัน:
{quick_note}

อ่านต่อ:
{url}
```

English text format:

```text
{surah_name} {surah_id}:{verse_id}

{translation}

My note:
{quick_note}

Read:
{url}
```

Web should use `navigator.share()` when available and copy-to-clipboard as a
fallback. Flutter should use the `share_plus` package.

## Migration Rules

- Keep old local keys readable until cloud migration is complete.
- Map old profile names to canonical profile names.
- Convert flat and nested translation JSON into canonical verse rows.
- Upload local notes as private Tadabbur notes after login, only with consent.
- Upload local progress/history/settings after login, only with consent.
- Convert legacy single-profile bookmarks into reading profiles or bookmark
  rows, depending on user intent.
- Convert legacy Last Read into recent readings.

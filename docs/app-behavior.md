# Thai Quran App Behavior Spec

Last updated: 2026-06-28

This document is the living contract for the Flutter app. It describes what the app is, what it can do today, and which behavior should eventually be brought over to `thai-quran-web`.

The goal is to keep polishing the app against one clear model before copying the flow into the web repo.

## Product Shape

Thai Quran is a mobile-first Quran reading app focused on Thai readers, with optional English support. The app should feel like a calm reading workspace, not a social feed or a heavy study dashboard.

The app currently supports:

- Reading Quran by surah and juz.
- Reading Mushaf page-by-page through Quran Foundation page layout APIs.
- Continuing from the current reading position.
- Free Read for open-ended browsing and reading.
- Created reading profiles for bounded verse goals.
- Separate Mushaf profiles for bounded page goals.
- Bookmarks / saved verses and Mushaf page / verse bookmarks.
- Private tadabbur notes and community tadabbur entry points.
- Reading display settings.
- Local guest use without sign-in.
- Supabase sign-in and sync for logged-in users.
- Local-first persistence through `SharedPreferences`.

## Main Navigation

The home screen has three primary areas:

- `Read Space`: the main workspace for continuing reading, profile actions, bookmarks, notes, and tadabbur.
- `Surah / Juz`: browse mode for opening a specific surah or juz.
- `Mushaf Read`: traditional page-by-page Mushaf reading, with Mushaf layout selection, Mushaf Free Read, and Mushaf profiles.

The profile button opens the reader profile/account area. The theme button toggles dark mode quickly.

## Reading Model

The app has two different reading ideas:

- **Free Read**: open-ended reading. It can point anywhere in the Quran.
- **Created profiles**: named reading plans with a start point and optional target point.

The standard reader is verse-based. The Mushaf reader is page-based and has its own separate state model.

The reader decides which profile is used through `LocalReadingProvider`.

When the reading screen opens without a specific surah, it loads the active profile's current verse. If no usable local profile is available, it falls back to the older `ProgressProvider` state.

When a specific surah / verse is opened:

- If the read was opened from the browse flow, `saveToFreeReadOnly` is true and progress is attached to Free Read.
- Otherwise, the app checks whether the requested verse is inside the active profile.
- If the requested verse is outside the active bounded profile, the app switches to Free Read and saves that verse there.
- If the requested verse is inside the active bounded profile, the active profile remains active.

For bounded profiles, the reading screen only shows verses inside the profile range. Free Read and unbounded profiles show the whole surah.

## Mushaf Reading Model

Mushaf reading is a separate read track from the standard translation reader.

Current rules:

- Mushaf state is owned by `MushafReadingProvider`, not `LocalReadingProvider`.
- Mushaf progress is page-based, not verse-based.
- Mushaf Free Read is independent from standard Free Read.
- Each Mushaf profile is tied to a specific `mushafId`.
- The app currently lists all supported Quran Foundation Mushaf layouts:
  - `1` QCF V2, 604 pages
  - `2` QCF V1, 604 pages
  - `3` IndoPak, 604 pages
  - `4` Uthmani Hafs, 604 pages
  - `5` KFGQPC Hafs, 604 pages
  - `6` IndoPak 15-line, 610 pages
  - `7` IndoPak 16-line, 548 pages
  - `11` Tajweed, 604 pages
  - `19` QCF Tajweed V4, 604 pages
- The default Mushaf for first use is `1` / QCF V2.
- Mushaf pages are fetched from Quran Foundation and cached locally.
- The reader renders Arabic only in a page-like layout.
- Words are grouped by API `line_number` and rendered right-to-left.
- Previous / next page are the primary navigation controls.
- Long-pressing a Mushaf word shows that verse's Thai translation.
- Longer translations use a bottom sheet; shorter translations use a snackbar.

Mushaf Free Read behavior:

- Free Read can open any page in the selected Mushaf.
- Free Read shows page, Surah, and Juz jump controls.
- Opening a Mushaf type from the Mushaf list opens that Mushaf's Free Read profile.

Mushaf created profile behavior:

- The app allows up to 3 active custom Mushaf profiles.
- Profiles can be created by page range, Surah, or Juz.
- Surah and Juz profiles are converted to the containing page range for that `mushafId`.
- A custom Mushaf profile can only navigate inside its page range.
- Page / Surah / Juz selectors are hidden while reading a custom Mushaf profile.
- Completion is reached on the profile's final page and shown in the reader.

Quran Foundation config:

- `.env` is ignored and can hold local developer credentials.
- `.env.example` documents the expected variables.
- `QURAN_FOUNDATION_CONTENT_BASE_URL` defaults to `https://apis.quran.foundation/content/api/v4`.
- `QURAN_FOUNDATION_AUTH_BASE_URL` defaults to `https://prelive-oauth2.quran.foundation`.
- `QURAN_FOUNDATION_CLIENT_ID` and `QURAN_FOUNDATION_AUTH_TOKEN` are required for API calls.
- Release builds should pass these values through dart defines.

## Free Read Rules

Free Read is the default open reading state.

Current rules:

- Each user context should have one Free Read profile.
- Guest users use the `local` user context.
- Logged-in users use their Supabase user id.
- Legacy `main_read` / `Main Read` values are normalized to Free Read.
- Duplicate Free Read profiles are deduplicated on local load, keeping the oldest one.
- Free Read is not editable, archivable, or deletable from the profile UI.
- Free Read has no target range.
- Free Read can store current progress anywhere in the Quran.

Current UI behavior:

- If there are active custom profiles, the active profile list hides Free Read.
- If there are no active custom profiles, Free Read appears as the available reading profile.
- Browse mode opens readings as Free Read so casual navigation does not accidentally move a bounded plan.

Design intent:

- Free Read should feel like the user's general reading lane.
- It should not feel like a hidden custom profile.
- Created profiles should be for intentional goals.

## Created Profile Rules

Created profiles are user-defined reading goals.

Current rules:

- A profile has a name, slug, start verse, current verse, and optional target verse.
- A profile may also keep plan metadata such as `planMode`, `startJuz`, and `targetJuz`.
- The app allows up to 5 active reading profiles.
- Archived profiles do not count as active reading profiles.
- Free Read is excluded from archived profile lists.
- Editing a profile resets its current verse to its start verse.
- Deleting, editing, and archiving are blocked for Free Read.
- If an active profile is deleted or archived, the app selects the latest read remaining profile when possible.
- If a loaded bounded profile has current progress outside its range, progress is reset to the profile start.

Plan modes currently recognized by the shared contract:

- `by_juz`
- `by_surah`
- `by_ayat`
- `custom`

Design intent:

- Profiles should be few, intentional, and easy to reason about.
- A profile should never silently track reading outside its target range.
- The active profile should represent the user's current goal, while Free Read handles exploration.

## Local Storage Rules

The app stores the local reading system under:

`thai_quran_local_reading_store_v1`

The local store contains:

- active profile id
- profiles
- bookmark categories
- bookmarks
- recent readings

Progress updates are disk-first:

- The app prepares the updated profile state.
- It writes the new reading timestamp and serialized local store to `SharedPreferences`.
- Only after the write succeeds does it update in-memory state and notify listeners.
- If local persistence fails, the app shows a storage failure message and avoids mutating in-memory progress.

This is important because reading progress should not appear saved unless it actually survives app restart.

The app stores the local Mushaf reading system under:

`thai_quran_mushaf_store_v1`

The Mushaf local store contains:

- active Mushaf profile id
- Mushaf Free Read profiles
- custom Mushaf profiles
- Mushaf page bookmarks
- Mushaf verse bookmarks
- recent Mushaf readings

Mushaf API page and lookup responses are cached separately under Quran Foundation cache keys.

## Supabase Rules

The app can be used without sign-in. Supabase adds account sync, not basic app access.

On sign-in:

- Supabase auth state is observed by providers.
- User defaults are bootstrapped.
- Local bookmarks and guest profiles are pushed to the signed-in account.
- Remote bookmarks, recent readings, profiles, settings, and reading state are fetched.
- Local and remote profile progress are reconciled using timestamps.
- Reading state sync chooses the remote state only if it is newer than local state.

On sign-out:

- Guest/local profiles are preserved.
- A guest default Free Read profile is ensured.
- The active profile is reset to a local guest profile.

Profile sync currently uses the legacy `user_reading_profiles` table shape:

- `profile_name`
- `current_surah`
- `current_ayah`
- `last_read_at`

The newer shared contract also defines richer `reading_profiles` rows with names, slugs, ranges, plan metadata, archived state, and sort order. The app is moving toward that cleaner model, but still carries compatibility behavior.

Mushaf sync schema is defined as an optional local-first extension:

- `mushaf_profiles`
- `mushaf_page_bookmarks`
- `mushaf_verse_bookmarks`
- `mushaf_recent_readings`

The current app behavior must still work without login. Mushaf sync should follow the same quiet local-first principle as standard reading sync.

## Settings Rules

Settings are local-first and sync to Supabase when a user is signed in.

Current settings include:

- dark mode
- reading display mode
- Arabic font size
- translation font size
- theme color, currently normalized to blue
- web host URL for development
- primary translation slot
- optional secondary translation slot

Reading display modes:

- `quran_only`
- `translation_only`
- `quran_translation`

Translation slots:

- primary translation is required
- secondary translation is optional
- valid IDs are `thai_v3`, `thai_v2`, and `english`
- if the primary changes to match the secondary, the secondary is cleared
- if the secondary is set to the current primary, the change is rejected

Settings sync compares `updated_at` values. If local settings are newer than remote, local settings are pushed to Supabase. Otherwise, remote settings are applied locally.

## Bookmarks And Recent Readings

Bookmarks are stored locally and synced for signed-in users.

Current behavior:

- A default `Saved Verses` category is ensured.
- Legacy `manual_bookmarks` are migrated into the local store.
- Guest bookmarks are pushed to Supabase on sign-in.
- Remote bookmarks replace the signed-in user's bookmark list locally.

Mushaf bookmarks are separate from standard verse bookmarks:

- Page bookmarks use `mushafId + pageNumber`.
- Verse bookmarks use `mushafId + verseKey + pageNumber`.
- Page bookmarks are toggled from the Mushaf reader app bar.
- Verse bookmarks are toggled from the long-press translation UI.

Recent readings:

- The app keeps recent readings locally.
- The default limit is 20.
- A recent reading may be tagged with a profile id only if the verse is inside that profile.
- Recent reading sync is debounced before writing to Supabase.

## Notes And Tadabbur

The app includes private and community tadabbur entry points.

Current contract-level behavior:

- Personal notes can be migrated from legacy verse-keyed local notes.
- Tadabbur notes have visibility values of `private` or `public`.
- Private and community tadabbur screens can open a verse in the reader.

This area still needs product polish, especially around how notes, reflections, favorites, and community behavior should be named and grouped.

## Design Principles

The current app direction should stay:

- Calm and reader-first.
- Profile behavior should be understandable from the UI.
- Free Read should be obvious enough to trust, but not noisy.
- Settings should expose useful reading controls, not old compatibility details.
- Local use should feel complete, not like a broken logged-out mode.
- Sync should be helpful and quiet.
- Web should copy the simplified mental model, not every mobile UI detail.

## Current Polish Targets

Before migrating the flow to web, the Flutter app should be polished in these areas:

- Make the Free Read and custom profile relationship visually clearer.
- Finish the profile creation/editing experience.
- Decide final labels for Read Space, Free Read, profiles, notes, favorites, and tadabbur.
- Confirm whether `reading_profiles` should replace the older `user_reading_profiles` path.
- Tighten account/profile sync behavior after sign-in and sign-out.
- Simplify settings UI around reading mode and translation slots.
- Visually evaluate Quran Foundation Mushaf layouts and decide which remain user-facing.
- Polish Mushaf fonts/glyph mapping for layouts that need more than the bundled Uthmanic Hafs font.
- Complete Mushaf Supabase sync if account-level Mushaf continuity is needed.
- Review Thai/English copy and encoding issues in older screens.

## Web Migration Contract

When `thai-quran-web` is ready for the redesign, it should implement the app behavior in this order:

1. Shared Quran contract constants and verse refs.
2. Free Read as the default open reading lane.
3. Created profile rules and 5 active profile limit.
4. Profile range filtering in the reader.
5. Browse flow saving to Free Read instead of changing a bounded active profile.
6. Local-first reading state and recent readings.
7. Supabase account sync and timestamp reconciliation.
8. Settings model, especially reading display mode and translation slots.
9. Bookmarks and notes behavior.
10. Mushaf read track with page-based Free Read, profiles, and bookmarks.
11. Visual design inspired by the polished app, adapted for web layout.

The web repo should not copy mobile-specific navigation blindly. It should copy the rules first, then design a web-native layout around them.

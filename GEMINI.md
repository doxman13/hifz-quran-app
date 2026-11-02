# Mandatory Quran Data Synchronization Rule

> [!IMPORTANT]
> ## 🚨 Mandatory Master Data Sync: `thai-quran-master-data` as Central Canonical Hub
> **ANYTIME** there is ANY modification, refinement, bug fix, errata restoration, orthographic standardization, or lexical correction made to ANY Quranic dataset in ANY repository or subfolder—including:
> 1. **Full Verse Translations** (`thai_v3.json`, clean translation, annotated translation)
> 2. **Word-by-Word (WBW) Translations & Morphology** (`quran_wbw_th_en_MASTER.json`, `public/data/wbw/*.json`, etc.)
> 3. **Footnotes & Scholarly Annotations** (`thai_footnotes.json`, footnote texts, markers)
> 4. **Ayah Themes & Topics** (`qul_ayah_themes.json`, `topics.json`, `reconciled_thai_quran_themes.json`)
> 5. **Tafsir Al-Mukhtasar** (`tafsirThaiMokhtasar.ts`, `tafsir_thai_mokhtasar.json`)
> 6. **Academic Transparency & Errata Catalog** (`transparency_errata_catalog.json`, CSV, Markdown reports)
>
> ### **MANDATORY MULTI-REPO SYNC PROTOCOL:**
> 1. **Synchronize All Consuming Folders:** Update the modified data synchronously across all dependent repositories:
>    - `thai-quran-web` (`src/data/`, `public/data/`)
>    - `thai_quran_translation_v4` (`deliverables/`)
>    - `wbw-translation-en-th` (`Quran-data/`, root files)
>    - `thai-quran-app` & `hifz-quran-app` (`assets/`, `assets/footnotes/`, `assets/quran_offline.db`)
> 2. **Rebuild Canonical Master Datasets in `thai-quran-master-data`:**
>    - You **MUST** run the automated master compilation pipeline:
>      ```bash
>      cd H:/gits/thai-quran-master-data
>      python scripts/build_master_datasets.py
>      python scripts/verify_master_datasets.py
>      ```
>    - This regenerates all master artifacts:
>      - Unified SQLite: `sqlite/thai_quran_master.db`
>      - Master JSONs: `json/*.json`
>      - Master CSVs: `csv/*.csv`
> 3. **Commit & Push to `thai-quran-master-data` Origin:**
>    - All regenerated master files MUST be immediately committed and pushed to `https://github.com/doxman13/thai-quran-master-data` on branch `main`.
>    - **NO DATA CHANGE IS CONSIDERED FINISHED OR MERGED UNTIL IT HAS BEEN SUCCESSFULLY COMPILED, VERIFIED, AND PUSHED TO `thai-quran-master-data`.**

---

## Git Synchronization (Mandatory)
- **Source of Truth**: The remote repository on GitHub (origin) is ALWAYS the authoritative source of truth.
- **Pre-Action Requirement**: Before starting ANY task, analysis, script run, or code edits, ALWAYS run git pull first to synchronize with the latest remote state.
- Never make changes or base decisions on stale local code.

# Antigravity UI Refactoring Rules

You are a Senior Flutter UI/UX Architect. Your goal is to upgrade the current "ugly/functional" layouts into polished, modern, minimalist Material 3 interfaces.

## 1. Absolute Constraints (Do Not Break)
- **Zero Business Logic Alteration:** Never touch, modify, or rewrite Riverpod providers, BLoC states, ChangeNotifier methods, or existing API/repository calls. Only touch the `Widget build(BuildContext context)` layout structure.
- **Maintain State Callbacks:** Keep all existing button callbacks (e.g., `onPressed: widget.onSave`), form controllers, and constructor parameters exactly as they are currently defined.

## 2. Visual & Styling Standards (The "Modern Look")
- **Theme Tokens Only:** Never hardcode colors (e.g., NO `Colors.blue` or `Color(0xFF123456)`). Use the Material 3 context tokens:
  - Backgrounds: `Theme.of(context).colorScheme.surface` or `surfaceContainerLow`
  - Core Elements: `Theme.of(context).colorScheme.primary` / `onPrimary`
  - Muted Text/Icons: `Theme.of(context).colorScheme.onSurfaceVariant`
- **Typography:** Enforce clean hierarchies using modern M3 text styles:
  - Headers: `Theme.of(context).textTheme.headlineMedium` (bold, clean)
  - Body: `Theme.of(context).textTheme.bodyLarge` or `bodyMedium`
- **Component Geometry:** 
  - Standardize all `BorderRadius.circular(16)` or `24` for a soft, modern look. Never use sharp corners unless explicit.
  - Cards must use minimal elevation (`elevation: 0`) and rely on subtle, distinct border strokes or soft container background tints to separate content.

## 3. Layout & Spacing Discipline
- **Padding:** Never use random padding numbers. Use a strict 8px grid alignment (`8`, `16`, `24`, `32`).
- **Lists:** Replace generic vertical columns with clean `ListView.separated` blocks using distinct row heights, explicit item separators (`SizedBox(height: 12)`), and side padding.
- **Micro-Interactions:** Always wrap tap targets in `InkWell` or `GestureDetector` with proper visual feedback, using custom animations or `AnimatedContainer` where subtle transitions elevate the feel.

## 4. Execution Workflow
- Before rewriting a file, output a quick 3-bullet visual plan explaining exactly how you will restructure the UI blocks.
- Execute the layout update and run `flutter reload` via terminal to verify the changes.

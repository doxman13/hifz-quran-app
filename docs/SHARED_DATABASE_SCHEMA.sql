-- Shared Postgres/Supabase starter schema for thai-quran-web and thai-quran-app.
-- Review before running in production.

create extension if not exists pgcrypto;

create table if not exists public.translations (
  id uuid primary key default gen_random_uuid(),
  surah_id text not null,
  verse_id text not null,
  verse_key text generated always as (surah_id || ':' || verse_id) stored,
  version text not null check (version in ('thai_v3', 'thai_v2', 'english')),
  language text not null check (language in ('th', 'en')),
  text text not null,
  source text,
  updated_at timestamptz not null default now(),
  unique (verse_key, version)
);

create table if not exists public.verse_tafsir (
  id uuid primary key default gen_random_uuid(),
  surah_id text not null,
  verse_id text not null,
  verse_key text generated always as (surah_id || ':' || verse_id) stored,
  tafsir_key text not null check (tafsir_key in ('thai_mokhtasar')),
  language text not null default 'th' check (language in ('th', 'en')),
  text text not null,
  source text not null,
  source_url text,
  updated_at timestamptz not null default now(),
  unique (verse_key, tafsir_key)
);

create table if not exists public.surah_summaries (
  id uuid primary key default gen_random_uuid(),
  surah_id text not null,
  language text not null default 'th' check (language in ('th', 'en')),
  title text,
  summary_text text not null,
  source text not null,
  source_url text,
  updated_at timestamptz not null default now(),
  unique (surah_id, language, source)
);

create table if not exists public.reading_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  slug text not null,
  plan_mode text check (plan_mode in ('by_juz', 'by_surah', 'by_ayat', 'custom')),
  start_juz integer check (start_juz between 1 and 30),
  target_juz integer check (target_juz between 1 and 30),
  start_surah_id text not null,
  start_verse_id text not null,
  start_verse_key text generated always as (start_surah_id || ':' || start_verse_id) stored,
  target_surah_id text,
  target_verse_id text,
  target_verse_key text generated always as (
    case
      when target_surah_id is null or target_verse_id is null then null
      else target_surah_id || ':' || target_verse_id
    end
  ) stored,
  current_surah_id text not null,
  current_verse_id text not null,
  current_verse_key text generated always as (current_surah_id || ':' || current_verse_id) stored,
  furthest_unread_index integer not null default 1 check (furthest_unread_index between 1 and 6236),
  last_viewed_index integer not null default 1 check (last_viewed_index between 1 and 6236),
  sort_order integer not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, slug)
);

create table if not exists public.bookmark_categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  slug text not null,
  max_items integer not null default 5 check (max_items > 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, slug)
);

create table if not exists public.bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid not null references public.bookmark_categories(id) on delete cascade,
  surah_id text not null,
  verse_id text not null,
  verse_key text generated always as (surah_id || ':' || verse_id) stored,
  label text,
  note text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.custom_quick_links (
  id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  surah_number integer not null check (surah_number between 1 and 114),
  label text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table if not exists public.recent_readings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  surah_id text not null,
  verse_id text not null,
  verse_key text generated always as (surah_id || ':' || verse_id) stored,
  profile_id uuid references public.reading_profiles(id) on delete set null,
  read_at timestamptz not null default now(),
  unique (user_id, surah_id)
);

create table if not exists public.user_reading_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  read_date date not null,
  surah_id text not null,
  verse_id text not null,
  verse_key text generated always as (surah_id || ':' || verse_id) stored,
  created_at timestamptz not null default now(),
  unique (user_id, read_date, verse_key)
);

create table if not exists public.user_completed_surahs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('read', 'review')),
  surah_id text not null,
  completed_at timestamptz not null default now(),
  unique (user_id, mode, surah_id)
);

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  theme_color text not null default 'teal',
  is_dark_mode boolean not null default false,
  always_show_arabic boolean not null default true,
  arabic_font_family text not null default 'UthmanicHafs',
  arabic_font_size numeric not null default 28,
  thai_font_family text not null default 'sans-serif',
  thai_font_size numeric not null default 16,
  show_thai_v3 boolean not null default true,
  show_thai_v2 boolean not null default false,
  show_english boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.thai_protected_terms (
  id uuid primary key default gen_random_uuid(),
  term text not null unique,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.thai_protected_terms (term, sort_order)
values
  ('ฟิรเอานฺ', 10),
  ('อัลลอฮฺ', 20),
  ('มุฮัมมัด', 30),
  ('อิบรอฮีม', 40),
  ('อิสมาอีล', 50),
  ('อิสฮาก', 60),
  ('ยะอฺกูบ', 70),
  ('ญิบรีล', 80),
  ('ตอรูต', 90),
  ('ญาลูต', 100),
  ('ฏอลูต', 110),
  ('ฮารูน', 120),
  ('อีซา', 130),
  ('มูซา', 140)
on conflict (term) do update set
  sort_order = excluded.sort_order,
  updated_at = now();

create table if not exists public.mushaf_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  slug text not null,
  mushaf_id integer not null,
  plan_mode text not null check (plan_mode in ('free_read', 'page_range', 'by_surah', 'by_juz')),
  start_page integer not null check (start_page > 0),
  target_page integer not null check (target_page >= start_page),
  current_page integer not null check (current_page >= start_page),
  furthest_unread_page integer not null default 1 check (furthest_unread_page > 0),
  last_viewed_page integer not null default 1 check (last_viewed_page > 0),
  sort_order integer not null default 0,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, slug, mushaf_id)
);

create table if not exists public.mushaf_page_bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mushaf_id integer not null,
  page_number integer not null check (page_number > 0),
  created_at timestamptz not null default now(),
  unique (user_id, mushaf_id, page_number)
);

create table if not exists public.mushaf_verse_bookmarks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mushaf_id integer not null,
  page_number integer not null check (page_number > 0),
  verse_key text not null,
  created_at timestamptz not null default now(),
  unique (user_id, mushaf_id, page_number, verse_key)
);

create table if not exists public.mushaf_recent_readings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  mushaf_id integer not null,
  page_number integer not null check (page_number > 0),
  profile_id uuid references public.mushaf_profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (user_id, mushaf_id, profile_id)
);

create table if not exists public.translation_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  surah_id text not null,
  verse_id text not null,
  verse_key text generated always as (surah_id || ':' || verse_id) stored,
  translation_version text not null check (translation_version in ('thai_v3', 'thai_v2', 'english')),
  issue_type text not null check (issue_type in ('typo', 'meaning', 'missing_text', 'formatting', 'other')),
  comment text not null,
  suggested_text text,
  status text not null default 'open' check (status in ('open', 'reviewing', 'accepted', 'rejected', 'fixed')),
  reviewer_note text,
  source text not null check (source in ('web', 'flutter')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tadabbur_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  surah_id text not null,
  verse_id text not null,
  verse_key text generated always as (surah_id || ':' || verse_id) stored,
  note_text text not null,
  visibility text not null default 'private' check (visibility in ('private', 'public')),
  language text not null default 'th' check (language in ('th', 'en')),
  status text not null default 'active' check (status in ('active', 'hidden', 'reported', 'removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tadabbur_reactions (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.tadabbur_notes(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction_type text not null check (reaction_type in ('helpful', 'heart')),
  created_at timestamptz not null default now(),
  unique (note_id, user_id, reaction_type)
);

create table if not exists public.tadabbur_reports (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.tadabbur_notes(id) on delete cascade,
  reporter_user_id uuid references auth.users(id) on delete set null,
  reason text not null,
  created_at timestamptz not null default now()
);

create index if not exists translations_verse_key_idx on public.translations (verse_key);
create index if not exists verse_tafsir_verse_key_idx on public.verse_tafsir (verse_key);
create index if not exists surah_summaries_surah_idx on public.surah_summaries (surah_id, language);
create index if not exists reading_profiles_user_idx on public.reading_profiles (user_id, is_archived, sort_order);
create index if not exists bookmarks_category_idx on public.bookmarks (category_id, sort_order);
create index if not exists custom_quick_links_user_idx
  on public.custom_quick_links (user_id, sort_order);
create index if not exists recent_readings_user_idx on public.recent_readings (user_id, read_at desc);
create index if not exists tadabbur_public_verse_idx on public.tadabbur_notes (verse_key)
  where visibility = 'public' and status = 'active';
create index if not exists translation_reports_status_idx on public.translation_reports (status, created_at);
create index if not exists thai_protected_terms_active_idx
  on public.thai_protected_terms (is_active, sort_order, term);
create index if not exists mushaf_profiles_user_idx
  on public.mushaf_profiles (user_id, mushaf_id, is_archived, sort_order);
create index if not exists mushaf_recent_readings_user_idx
  on public.mushaf_recent_readings (user_id, updated_at desc);

alter table public.reading_profiles enable row level security;
alter table public.verse_tafsir enable row level security;
alter table public.surah_summaries enable row level security;
alter table public.bookmark_categories enable row level security;
alter table public.bookmarks enable row level security;
alter table public.custom_quick_links enable row level security;
alter table public.recent_readings enable row level security;
alter table public.user_reading_history enable row level security;
alter table public.user_completed_surahs enable row level security;
alter table public.user_settings enable row level security;
alter table public.thai_protected_terms enable row level security;
alter table public.mushaf_profiles enable row level security;
alter table public.mushaf_page_bookmarks enable row level security;
alter table public.mushaf_verse_bookmarks enable row level security;
alter table public.mushaf_recent_readings enable row level security;
alter table public.translation_reports enable row level security;
alter table public.tadabbur_notes enable row level security;
alter table public.tadabbur_reactions enable row level security;
alter table public.tadabbur_reports enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'thai_protected_terms'
      and policyname = 'Thai protected terms are readable by everyone'
  ) then
    create policy "Thai protected terms are readable by everyone"
      on public.thai_protected_terms
      for select
      using (is_active = true);
  end if;
end $$;

-- RLS policy outline:
-- - translations: public read, admin-only write.
-- - verse_tafsir/surah_summaries: public read, admin-only write.
-- - thai_protected_terms: public read for active terms, admin-only write.
-- - reading_profiles/bookmarks/recent_readings/user_* tables:
--   users can read/write only rows where user_id = auth.uid().
-- - mushaf_profiles/mushaf_* tables:
--   users can read/write only rows where user_id = auth.uid().
-- - translation_reports: authenticated users can insert their own reports;
--   optional guest report insert should go through a protected server endpoint.
-- - tadabbur_notes: users can read public active notes and their own notes;
--   users can write only their own notes.
-- - reactions/reports: authenticated users can create their own rows.

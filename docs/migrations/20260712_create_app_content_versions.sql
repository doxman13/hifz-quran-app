create table if not exists public.app_content_versions (
  content_key text primary key,
  version text not null,
  storage_bucket text not null default 'app-content',
  storage_path text not null,
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.app_content_versions enable row level security;

drop policy if exists "active app content versions are readable" on public.app_content_versions;
create policy "active app content versions are readable"
  on public.app_content_versions
  for select
  to anon, authenticated
  using (is_active = true);

insert into storage.buckets (id, name, public)
values ('app-content', 'app-content', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "app content files are publicly readable" on storage.objects;
create policy "app content files are publicly readable"
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'app-content');

insert into public.app_content_versions (
  content_key,
  version,
  storage_bucket,
  storage_path,
  is_active
)
values
  ('thai_v3', '0', 'app-content', 'thai_v3.json', false),
  (
    'quran_themes',
    '0',
    'app-content',
    'reconciled_thai_quran_themes.json',
    false
  ),
  (
    'mokhtasar_short_tafsir',
    '0',
    'app-content',
    'tafsir_thai_mokhtasar.json',
    false
  )
on conflict (content_key) do nothing;

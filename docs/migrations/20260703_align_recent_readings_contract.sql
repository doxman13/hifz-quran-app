-- Align verse-by-verse recent readings with the shared app contract.
-- Target shape: verse_id + verse_key + read_at.
-- Safe for databases where verse_key is already a generated column.

alter table if exists public.recent_readings
  add column if not exists verse_id text,
  add column if not exists read_at timestamptz;

do $$
declare
  verse_key_is_generated boolean;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'recent_readings'
      and column_name = 'verse_key'
  ) then
    alter table public.recent_readings
      add column verse_key text generated always as (surah_id || ':' || verse_id) stored;
  end if;

  select c.is_generated <> 'NEVER'
  into verse_key_is_generated
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'recent_readings'
    and c.column_name = 'verse_key';

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'recent_readings'
      and column_name = 'last_read_verse'
  ) then
    execute '
      update public.recent_readings
      set verse_id = coalesce(verse_id, last_read_verse)
      where verse_id is null
    ';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'recent_readings'
      and column_name = 'updated_at'
  ) then
    execute '
      update public.recent_readings
      set read_at = coalesce(read_at, updated_at, now())
      where read_at is null
    ';
  end if;

  update public.recent_readings
  set
    verse_id = coalesce(verse_id, '1'),
    read_at = coalesce(read_at, now())
  where verse_id is null
     or read_at is null;

  if not coalesce(verse_key_is_generated, false) then
    update public.recent_readings
    set verse_key = coalesce(verse_key, surah_id || ':' || verse_id)
    where verse_key is null;
  end if;
end $$;

alter table if exists public.recent_readings
  alter column verse_id set not null,
  alter column read_at set not null;

do $$
declare
  verse_key_is_generated boolean;
begin
  select c.is_generated <> 'NEVER'
  into verse_key_is_generated
  from information_schema.columns c
  where c.table_schema = 'public'
    and c.table_name = 'recent_readings'
    and c.column_name = 'verse_key';

  if not coalesce(verse_key_is_generated, false) then
    alter table public.recent_readings
      alter column verse_key set not null;
  end if;
end $$;

create index if not exists recent_readings_user_read_at_idx
  on public.recent_readings (user_id, read_at desc);

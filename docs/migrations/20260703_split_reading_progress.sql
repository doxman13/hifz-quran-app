-- Split reading progress into forward progress and review position.
-- `furthest_unread_index` is monotonic forward progress.
-- `last_viewed_index` is the latest verse the user touched, even when reviewing.

alter table if exists public.reading_profiles
  add column if not exists furthest_unread_index integer not null default 1
    check (furthest_unread_index between 1 and 6236),
  add column if not exists last_viewed_index integer not null default 1
    check (last_viewed_index between 1 and 6236);

alter table if exists public.user_reading_profiles
  add column if not exists furthest_unread_index integer not null default 1
    check (furthest_unread_index between 1 and 6236),
  add column if not exists last_viewed_index integer not null default 1
    check (last_viewed_index between 1 and 6236);

alter table if exists public.user_reading_state
  add column if not exists furthest_unread_index integer not null default 1
    check (furthest_unread_index between 1 and 6236),
  add column if not exists last_viewed_index integer not null default 1
    check (last_viewed_index between 1 and 6236);

-- Backfill legacy rows that only had current surah/ayah columns.
-- This helper uses the standard Quran verse counts to convert a surah/ayah pair
-- into a 1-based absolute verse index.
create or replace function public.quran_absolute_verse_index(
  surah_number integer,
  ayah_number integer
)
returns integer
language plpgsql
immutable
as $$
declare
  counts integer[] := array[
    7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,
    135,112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,
    54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,
    11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,
    22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,
    5,4,5,6
  ];
  result integer := greatest(1, least(coalesce(ayah_number, 1), counts[greatest(1, least(coalesce(surah_number, 1), 114))]));
begin
  for i in 1..(greatest(1, least(coalesce(surah_number, 1), 114)) - 1) loop
    result := result + counts[i];
  end loop;
  return result;
end;
$$;

update public.reading_profiles
set
  furthest_unread_index = public.quran_absolute_verse_index(
    current_surah_id::integer,
    current_verse_id::integer
  ),
  last_viewed_index = public.quran_absolute_verse_index(
    current_surah_id::integer,
    current_verse_id::integer
  )
where furthest_unread_index = 1
  and last_viewed_index = 1
  and not (current_surah_id = '1' and current_verse_id = '1');

update public.user_reading_profiles
set
  furthest_unread_index = public.quran_absolute_verse_index(current_surah, current_ayah),
  last_viewed_index = public.quran_absolute_verse_index(current_surah, current_ayah)
where furthest_unread_index = 1
  and last_viewed_index = 1
  and not (current_surah = 1 and current_ayah = 1);

update public.user_reading_state
set
  furthest_unread_index = public.quran_absolute_verse_index(surah_id, verse_id),
  last_viewed_index = public.quran_absolute_verse_index(surah_id, verse_id)
where furthest_unread_index = 1
  and last_viewed_index = 1
  and not (surah_id = 1 and verse_id = 1);


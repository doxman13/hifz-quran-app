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

alter table public.mushaf_page_bookmarks enable row level security;
alter table public.mushaf_verse_bookmarks enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'mushaf_page_bookmarks'
      and policyname = 'users manage own mushaf page bookmarks'
  ) then
    create policy "users manage own mushaf page bookmarks"
      on public.mushaf_page_bookmarks
      for all
      to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'mushaf_verse_bookmarks'
      and policyname = 'users manage own mushaf verse bookmarks'
  ) then
    create policy "users manage own mushaf verse bookmarks"
      on public.mushaf_verse_bookmarks
      for all
      to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;
end $$;

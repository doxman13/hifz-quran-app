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

create index if not exists custom_quick_links_user_idx
  on public.custom_quick_links (user_id, sort_order);

alter table public.custom_quick_links enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'custom_quick_links'
      and policyname = 'users manage own custom quick links'
  ) then
    create policy "users manage own custom quick links"
      on public.custom_quick_links
      for all
      to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;
end $$;

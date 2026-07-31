-- Split Mushaf reading progress into forward progress and review position.
-- `furthest_unread_page` is monotonic forward page progress.
-- `last_viewed_page` is the latest page the user touched, even when reviewing.

alter table if exists public.mushaf_profiles
  add column if not exists furthest_unread_page integer not null default 1
    check (furthest_unread_page > 0),
  add column if not exists last_viewed_page integer not null default 1
    check (last_viewed_page > 0);

update public.mushaf_profiles
set
  furthest_unread_page = current_page,
  last_viewed_page = current_page
where furthest_unread_page = 1
  and last_viewed_page = 1
  and current_page <> 1;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'mushaf_profiles'
      and policyname = 'users manage own mushaf profiles'
  ) then
    create policy "users manage own mushaf profiles"
      on public.mushaf_profiles
      for all
      to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;
end $$;

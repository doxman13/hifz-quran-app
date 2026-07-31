-- Create hifz_progress table
create table public.hifz_progress (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  surah_number integer not null,
  new_verses_completed boolean default false,
  review_count integer default 0,
  last_completed_at timestamp with time zone,
  updated_at timestamp with time zone default timezone('utc'::text, now()),
  unique(user_id, surah_number)
);

-- Enable Row Level Security (RLS)
alter table public.hifz_progress enable row level security;

-- Policy: Users can view their own progress
create policy "Users can view own hifz progress"
  on public.hifz_progress for select
  using ( auth.uid() = user_id );

-- Policy: Users can insert their own progress
create policy "Users can insert own hifz progress"
  on public.hifz_progress for insert
  with check ( auth.uid() = user_id );

-- Policy: Users can update their own progress
create policy "Users can update own hifz progress"
  on public.hifz_progress for update
  using ( auth.uid() = user_id );

-- Policy: Users can delete their own progress (optional, if needed)
create policy "Users can delete own hifz progress"
  on public.hifz_progress for delete
  using ( auth.uid() = user_id );

-- Create hifz_history table
create table public.hifz_history (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  session_type text not null,
  surah_number integer,
  title text not null,
  completed_at timestamp with time zone not null,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- Enable Row Level Security (RLS)
alter table public.hifz_history enable row level security;

-- Policy: Users can view their own history
create policy "Users can view own hifz history"
  on public.hifz_history for select
  using ( auth.uid() = user_id );

-- Policy: Users can insert their own history
create policy "Users can insert own hifz history"
  on public.hifz_history for insert
  with check ( auth.uid() = user_id );

-- Policy: Users can delete their own history (optional)
create policy "Users can delete own hifz history"
  on public.hifz_history for delete
  using ( auth.uid() = user_id );

alter table if exists public.user_settings
  add column if not exists keep_awake boolean not null default true,
  add column if not exists reading_display_mode text not null default 'quran_translation',
  add column if not exists translation_font_size numeric not null default 16,
  add column if not exists primary_translation_id text not null default 'thai_v3',
  add column if not exists secondary_translation_id text,
  add column if not exists language_code text not null default 'th',
  add column if not exists web_host_url text;

alter table if exists public.user_settings
  drop constraint if exists user_settings_reading_display_mode_check,
  add constraint user_settings_reading_display_mode_check
    check (reading_display_mode in ('quran_only', 'translation_only', 'quran_translation'));

alter table if exists public.user_settings
  drop constraint if exists user_settings_language_code_check,
  add constraint user_settings_language_code_check
    check (language_code in ('th', 'en'));

update public.user_settings
set
  primary_translation_id = case
    when show_thai_v3 then 'thai_v3'
    when show_thai_v2 then 'thai_v2'
    when show_english then 'english'
    else primary_translation_id
  end,
  secondary_translation_id = case
    when show_thai_v3 and show_thai_v2 then 'thai_v2'
    when show_thai_v3 and show_english then 'english'
    when show_thai_v2 and show_english then 'english'
    else secondary_translation_id
  end,
  translation_font_size = thai_font_size
where primary_translation_id = 'thai_v3'
  and secondary_translation_id is null;

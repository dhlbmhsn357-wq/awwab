-- ════════════════════════════════════════════════════════════
--  أواب — Migration 001: Unified Worship Data Model
--  آمنة تمامًا: لا تحذف ولا تعدّل أي جدول أو بيانات موجودة.
--  تضيف فقط جداول وأعمدة جديدة. شغّلها مرة واحدة من
--  Supabase Dashboard → SQL Editor → Run.
-- ════════════════════════════════════════════════════════════

-- إضافة أعمدة onboarding لجدول users الموجود (بدون كسر أي شيء)
alter table users add column if not exists onboarding_done boolean not null default false;
alter table users add column if not exists onboarding_type text;

-- ────────────────────────────────────────────
-- 1) worships — العبادات اللي كل مستخدم بيبنيها بنفسه
-- ────────────────────────────────────────────
create table if not exists worships (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  name           text not null,
  description    text,
  icon           text,
  tracking_type  text not null default 'boolean'
                 check (tracking_type in ('boolean','count','quantity','multi')),
  target_value   numeric,
  target_unit    text,
  category       text default 'custom',           -- 'prayer' | 'quran' | 'custom' ...
  recurrence_type text not null default 'daily'
                 check (recurrence_type in ('daily','specific_days','weekly','once','times_per_week')),
  days_of_week   int[],                            -- 0=أحد .. 6=سبت (لـ specific_days)
  weekly_target  int,                               -- لـ times_per_week / weekly
  day_section    text not null default 'after_fajr',-- إحدى الفترات الـ16
  specific_time  time,
  sort_order     int not null default 0,
  is_active      boolean not null default true,
  is_paused      boolean not null default false,
  is_hidden      boolean not null default false,
  start_date     date,
  end_date       date,
  legacy_key     text,                              -- لربط العبادات القديمة الثابتة بسجلاتها التاريخية
  -- حقول القرآن (تُستخدم فقط لو category='quran')
  quran_mode       text check (quran_mode in ('read','memorize','review')),
  quran_surah      text,
  quran_start_ayah int,
  quran_end_ayah   int,
  quran_start_page int,
  quran_end_page   int,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists idx_worships_user on worships(user_id);
create unique index if not exists idx_worships_user_legacy on worships(user_id, legacy_key) where legacy_key is not null;

-- ────────────────────────────────────────────
-- 2) daily_worship_logs — السجل اليومي لكل عبادة (مستقل تمامًا لكل تاريخ)
-- ────────────────────────────────────────────
create table if not exists daily_worship_logs (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  worship_id     uuid not null references worships(id) on delete cascade,
  date           date not null,
  status         text not null default 'unrecorded'
                 check (status in ('completed','missed','unrecorded')),
  value          numeric,
  notes          text,
  quality_rating text check (quality_rating in ('mutqin','good','needs_review')),
  order_override int,                                -- ترتيب "لهذا اليوم فقط"
  completed_at   timestamptz,
  updated_at     timestamptz not null default now(),
  unique(user_id, worship_id, date)
);
create index if not exists idx_dwl_user_date on daily_worship_logs(user_id, date);
create index if not exists idx_dwl_worship on daily_worship_logs(worship_id);

-- ────────────────────────────────────────────
-- 2b) daily_notes — ملاحظة عامة لليوم (مستقلة عن أي عبادة بعينها)
-- ────────────────────────────────────────────
create table if not exists daily_notes (
  user_id  uuid not null references users(id) on delete cascade,
  date     date not null,
  notes    text,
  updated_at timestamptz not null default now(),
  primary key (user_id, date)
);

-- ────────────────────────────────────────────
-- 3) fellowship_settings — خصوصية "رفقة أواب" (افتراضيًا: لا مشاركة)
-- ────────────────────────────────────────────
create table if not exists fellowship_settings (
  user_id      uuid primary key references users(id) on delete cascade,
  share_level  text not null default 'none'
               check (share_level in ('none','percentage','streak','selected')),
  selected_text text,
  show_name    boolean not null default false,
  updated_at   timestamptz not null default now()
);

-- ────────────────────────────────────────────
-- 4) encouragements — "شجّعه 💚" بدون شات
-- ────────────────────────────────────────────
create table if not exists encouragements (
  id           uuid primary key default gen_random_uuid(),
  to_user_id   uuid not null references users(id) on delete cascade,
  from_user_id uuid references users(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_enc_to on encouragements(to_user_id);

-- ملحوظة: RLS متروك متطابق مع باقي الجداول الحالية (users/daily_records) —
-- التطبيق يعتمد نظام دخول مخصص وليس Supabase Auth، فلو فعّلت RLS على
-- الجداول الجديدة فقط هتكسر القراءة/الكتابة من الفرونت. لو حابب تأمين
-- أعمق (RLS حقيقي + Supabase Auth) ده مجهود منفصل هنتكلم عنه بعدين.

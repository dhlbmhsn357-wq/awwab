-- ════════════════════════════════════════════════════════════
--  أواب — Migration 007: Auth حقيقي (Production Readiness P0، جزء 1)
--  الهدف: الانتقال من users (اسم + كلمة مرور نص صريح) إلى
--  Supabase Auth الحقيقي (auth.users + كلمة مرور مشفّرة bcrypt)،
--  مع جدول profiles جديد يحمل بيانات الملف الشخصي فقط (بدون كلمة
--  مرور نهائيًا) ومرتبط بـ auth.uid().
--
--  إضافية بالكامل: لا تحذف ولا تعدّل جدول users القديم — الترحيل
--  الفعلي للمستخدمين بيحصل بعدها عبر سكريبت منفصل
--  (scripts/migrate-users-to-auth.mjs)، وبعد التأكد من نجاحه
--  هنشيل عمود pass من users القديم في خطوة لاحقة منفصلة.
-- ════════════════════════════════════════════════════════════

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null default 'member' check (role in ('member','admin')),
  pages_goal int not null default 0,
  onboarding_done boolean not null default false,
  onboarding_type text,
  onboarding_tour_status text check (onboarding_tour_status in ('not_started','in_progress','completed','skipped')),
  onboarding_tour_step int not null default 0,
  onboarding_tour_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- منع تكرار الاسم على مستوى القاعدة نفسها (مش بس فحص فرونت إند)
create unique index if not exists profiles_display_name_unique_idx
  on profiles (lower(display_name));

-- ── دالة: هل المستخدم الحالي admin؟ ──
-- SECURITY DEFINER عشان تقدر تقرا جدول profiles حتى لو RLS مفعّل
-- عليه، وتُستخدم جوه سياسات RLS نفسها بدل الاعتماد على role جاي
-- من الـclient (اللي ممكن أي حد يزوّره بسهولة).
create or replace function is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from profiles where id = auth.uid() and role = 'admin'
  );
$$;

-- ── دالة: تحويل الاسم لإيميل الدخول وقت اللوجين ──
-- الواجهة بتطلب اسم فقط من المستخدم، لكن Supabase Auth محتاج
-- إيميل. الدالة دي بترجع الإيميل المصطنع المرتبط بالاسم من غير
-- ما تكشف أي بيانة تانية (لا كلمة مرور ولا أي عمود حساس).
create or replace function get_login_email(p_name text)
returns text
language sql
security definer
set search_path = public, auth
stable
as $$
  select u.email
  from profiles p
  join auth.users u on u.id = p.id
  where lower(p.display_name) = lower(p_name)
  limit 1;
$$;

-- ── دالة: هل الاسم ده مستخدم بالفعل؟ ──
-- بديل عن جلب كل المستخدمين والعد يدويًا وقت التسجيل.
create or replace function is_name_taken(p_name text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from profiles where lower(display_name) = lower(p_name)
  );
$$;

-- ── دالة: تلخيص "رفقة أواب" باستعلام واحد مجمّع ──
-- بديل عن حلقة "لكل مستخدم: هات سجلاته واحسب نسبته" (N+1) القديمة.
-- بتراعي إعدادات الخصوصية (share_level) داخل الاستعلام نفسه، وترجع
-- بيانات ملخّصة بس (مش سجلات خام)، بحد أقصى 50 صف.
create or replace function get_fellowship_feed()
returns table(
  user_id uuid,
  display_name text,
  share_level text,
  selected_text text,
  scheduled int,
  completed int,
  pct int,
  active_last7 int,
  active_prev7 int
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_today date := current_date;
  v_week_start date := v_today - extract(dow from v_today)::int;
begin
  return query
  with active_worships as (
    select w.id, w.user_id, w.recurrence_type, w.weekly_target,
           w.days_of_week, w.day_section, w.start_date, w.end_date, w.recurrence_type as rtype
    from worships w
    where w.is_paused = false and w.is_hidden = false and w.deleted_at is null
  ),
  week_logs as (
    select l.user_id, l.worship_id, l.date, l.status
    from daily_worship_logs l
    where l.date >= v_week_start and l.date <= v_today
  ),
  per_user_week as (
    select
      p.id as uid,
      count(distinct aw.id) filter (where aw.recurrence_type <> 'times_per_week') as sched_daily,
      coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type = 'times_per_week'), 0) as sched_weekly,
      count(wl.*) filter (where wl.status = 'completed') as done
    from profiles p
    left join active_worships aw on aw.user_id = p.id
    left join week_logs wl on wl.user_id = p.id and wl.status = 'completed'
    group by p.id
  ),
  last14 as (
    select l.user_id, l.date
    from daily_worship_logs l
    where l.status = 'completed' and l.date >= v_today - 13
    group by l.user_id, l.date
  )
  select
    p.id,
    p.display_name,
    coalesce(fs.share_level, 'none'),
    fs.selected_text,
    (coalesce(puw.sched_daily,0) + coalesce(puw.sched_weekly,0))::int as scheduled,
    coalesce(puw.done,0)::int as completed,
    case when (coalesce(puw.sched_daily,0) + coalesce(puw.sched_weekly,0)) > 0
      then round(coalesce(puw.done,0)::numeric / (puw.sched_daily+puw.sched_weekly) * 100)::int
      else 0 end as pct,
    (select count(*) from last14 l14 where l14.user_id = p.id and l14.date >= v_today-6)::int as active_last7,
    (select count(*) from last14 l14 where l14.user_id = p.id and l14.date < v_today-6)::int as active_prev7
  from profiles p
  left join fellowship_settings fs on fs.user_id = p.id
  left join per_user_week puw on puw.uid = p.id
  order by pct desc
  limit 50;
  -- ملحوظة: بترجع المستخدم الحالي كمان (مش مستبعد) — الواجهة هي اللي
  -- بتفصل "بطاقة الهدف الجماعي" (بتجمع الكل) عن "قائمة الرفقاء"
  -- (بتستبعد المستخدم نفسه). حد الـ50 يعني هدف المجموعة تقريبي لو
  -- عدد الأعضاء أكبر من كده — قابل للتحسين لاحقًا بأجريجيت منفصل.
end;
$$;

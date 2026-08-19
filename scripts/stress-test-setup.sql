-- ════════════════════════════════════════════════════════════
--  أواب — سكريبت اختبار تحمّل (P4) — يتشغّل في مشروع Supabase
--  المؤقت المنفصل بس، أبدًا مش في الإنتاج.
--
--  نسخة مبسّطة من الجداول المهمة (بدون Auth حقيقي، مش محتاجينه
--  لقياس أداء الاستعلام نفسه) + نفس الفهارس المستخدمة فعليًا في
--  الإنتاج، عشان نقيس نفس شكل الاستعلام بالظبط.
-- ════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

create table st_profiles (
  id uuid primary key default gen_random_uuid(),
  seq bigserial unique, -- بس عشان نقدر نجرب "لو كان عدد المستخدمين كذا" على نفس البيانات المزروعة بدون إعادة زرع لكل مقياس
  display_name text not null
);

create table st_worships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references st_profiles(id),
  recurrence_type text not null default 'daily',
  weekly_target int,
  is_paused boolean not null default false,
  is_hidden boolean not null default false,
  deleted_at timestamptz
);

create table st_daily_worship_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references st_profiles(id),
  worship_id uuid not null references st_worships(id),
  date date not null,
  status text not null
);

create table st_fellowship_settings (
  user_id uuid primary key references st_profiles(id),
  share_level text default 'none',
  selected_text text
);

-- نفس الفهارس المستخدمة فعليًا في الإنتاج (migrations 001-014)
create index idx_st_dwl_date_status on st_daily_worship_logs (date, status);
create index idx_st_dwl_user_date on st_daily_worship_logs (user_id, date);
create index idx_st_worships_active on st_worships (user_id, recurrence_type, weekly_target)
  where is_paused = false and is_hidden = false and deleted_at is null;

-- نسخة من get_fellowship_feed بتاخد المستخدم الحالي كباراميتر بدل
-- auth.uid() (عشان نقدر نختبرها من SQL Editor مباشرة من غير جلسة
-- Auth حقيقية) — نفس منطق الاستعلام الحقيقي بالظبط
create or replace function st_get_fellowship_feed(p_caller uuid)
returns table(
  user_id uuid, display_name text, share_level text, selected_text text,
  scheduled int, completed int, pct int, active_last7 int, active_prev7 int,
  group_scheduled int, group_completed int
)
language plpgsql
as $$
declare
  v_today date := current_date;
  v_week_start date := v_today - extract(dow from v_today)::int;
  v_group_scheduled int;
  v_group_completed int;
begin
  with active_worships as (
    select w.id, w.user_id, w.recurrence_type, w.weekly_target
    from st_worships w
    where w.is_paused = false and w.is_hidden = false and w.deleted_at is null
  ),
  week_logs as (
    select l.user_id, l.worship_id, l.date, l.status
    from st_daily_worship_logs l
    where l.date >= v_week_start and l.date <= v_today
  ),
  per_user_week as (
    select p.id as uid,
      count(distinct aw.id) filter (where aw.recurrence_type <> 'times_per_week') as sched_daily,
      coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type = 'times_per_week'), 0) as sched_weekly,
      count(wl.*) filter (where wl.status = 'completed') as done
    from st_profiles p
    left join active_worships aw on aw.user_id = p.id
    left join week_logs wl on wl.user_id = p.id and wl.status = 'completed'
    group by p.id
  )
  select coalesce(sum(puw.sched_daily + puw.sched_weekly), 0)::int, coalesce(sum(puw.done), 0)::int
  into v_group_scheduled, v_group_completed
  from per_user_week puw;

  return query
  with active_worships as (
    select w.id, w.user_id, w.recurrence_type, w.weekly_target
    from st_worships w
    where w.is_paused = false and w.is_hidden = false and w.deleted_at is null
  ),
  week_logs as (
    select l.user_id, l.worship_id, l.date, l.status
    from st_daily_worship_logs l
    where l.date >= v_week_start and l.date <= v_today
  ),
  per_user_week as (
    select p.id as uid,
      count(distinct aw.id) filter (where aw.recurrence_type <> 'times_per_week') as sched_daily,
      coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type = 'times_per_week'), 0) as sched_weekly,
      count(wl.*) filter (where wl.status = 'completed') as done
    from st_profiles p
    left join active_worships aw on aw.user_id = p.id
    left join week_logs wl on wl.user_id = p.id and wl.status = 'completed'
    group by p.id
  ),
  last14 as (
    select l.user_id, l.date from st_daily_worship_logs l
    where l.status = 'completed' and l.date >= v_today - 13
    group by l.user_id, l.date
  ),
  computed as (
    select p.id as uid, p.display_name as dname, coalesce(fs.share_level,'none') as slevel,
      fs.selected_text as stext,
      (coalesce(puw.sched_daily,0)+coalesce(puw.sched_weekly,0))::int as sched,
      coalesce(puw.done,0)::int as comp,
      case when (coalesce(puw.sched_daily,0)+coalesce(puw.sched_weekly,0))>0
        then round(coalesce(puw.done,0)::numeric/(puw.sched_daily+puw.sched_weekly)*100)::int else 0 end as p,
      (select count(*) from last14 l14 where l14.user_id=p.id and l14.date>=v_today-6)::int as a7,
      (select count(*) from last14 l14 where l14.user_id=p.id and l14.date<v_today-6)::int as p7
    from st_profiles p
    left join st_fellowship_settings fs on fs.user_id = p.id
    left join per_user_week puw on puw.uid = p.id
  )
  select c.uid, c.dname, c.slevel,
    case when c.uid=p_caller or c.slevel='selected' then c.stext else null end,
    case when c.uid=p_caller or c.slevel='percentage' then c.sched else null end,
    case when c.uid=p_caller or c.slevel='percentage' then c.comp else null end,
    case when c.uid=p_caller or c.slevel='percentage' then c.p else null end,
    case when c.uid=p_caller or c.slevel='streak' then c.a7 else null end,
    case when c.uid=p_caller or c.slevel='streak' then c.p7 else null end,
    v_group_scheduled, v_group_completed
  from computed c
  order by c.p desc
  limit 50;
end;
$$;

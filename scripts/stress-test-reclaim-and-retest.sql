-- ════════════════════════════════════════════════════════════
--  تحرير مساحة (تقليل العبادات لـ2 بدل 8 لكل مستخدم) + زرع نشاط
--  حقيقي لـ6000 مستخدم (أكتر من سقف الأمان 5000 في الدالة الجديدة،
--  عشان نختبر أسوأ سيناريو واقعي فعليًا) + تحديث الدالة للنسخة
--  الجديدة المحدودة + قياس الأداء.
--  خطوة واحدة، ممكن تاخد شوية وقت.
-- ════════════════════════════════════════════════════════════

truncate st_worships cascade;
insert into st_worships (user_id, recurrence_type, weekly_target, is_paused, is_hidden)
select p.id,
  case when w = 2 then 'times_per_week' else 'daily' end,
  case when w = 2 then 3 else null end,
  false, false
from st_profiles p
cross join generate_series(1, 2) w;

insert into st_daily_worship_logs (user_id, worship_id, date, status)
select w.user_id, w.id, (current_date - d), case when random() < 0.7 then 'completed' else 'skipped' end
from st_worships w
join st_profiles p on p.id = w.user_id and p.seq <= 6000
cross join generate_series(0, 13) d
where random() < 0.5;

-- تحديث الدالة للنسخة الجديدة المحدودة (candidates بدل كل المستخدمين)
drop function if exists st_get_fellowship_feed(uuid);
create function st_get_fellowship_feed(p_caller uuid)
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
  with active_users as (
    select distinct l.user_id from st_daily_worship_logs l
    where l.date >= v_week_start and l.date <= v_today
    limit 5000
  ),
  candidates as (
    select p_caller as id
    union
    select active_users.user_id as id from active_users
  ),
  active_worships as (
    select w.id, w.user_id, w.recurrence_type, w.weekly_target
    from st_worships w
    where w.user_id in (select id from candidates)
      and w.is_paused=false and w.is_hidden=false and w.deleted_at is null
  ),
  week_logs as (
    select l.user_id, l.worship_id, l.date, l.status from st_daily_worship_logs l
    where l.user_id in (select id from candidates)
      and l.date >= v_week_start and l.date <= v_today
  ),
  per_user_week as (
    select c.id as uid,
      count(distinct aw.id) filter (where aw.recurrence_type<>'times_per_week') as sched_daily,
      coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type='times_per_week'),0) as sched_weekly,
      count(wl.*) filter (where wl.status='completed') as done
    from candidates c
    left join active_worships aw on aw.user_id=c.id
    left join week_logs wl on wl.user_id=c.id and wl.status='completed'
    group by c.id
  )
  select coalesce(sum(puw.sched_daily+puw.sched_weekly),0)::int, coalesce(sum(puw.done),0)::int
  into v_group_scheduled, v_group_completed
  from per_user_week puw;

  return query
  with active_users as (
    select distinct l.user_id from st_daily_worship_logs l
    where l.date >= v_week_start and l.date <= v_today
    limit 5000
  ),
  candidates as (
    select p_caller as id
    union
    select active_users.user_id as id from active_users
  ),
  active_worships as (
    select w.id, w.user_id, w.recurrence_type, w.weekly_target
    from st_worships w
    where w.user_id in (select id from candidates)
      and w.is_paused=false and w.is_hidden=false and w.deleted_at is null
  ),
  week_logs as (
    select l.user_id, l.worship_id, l.date, l.status from st_daily_worship_logs l
    where l.user_id in (select id from candidates)
      and l.date >= v_week_start and l.date <= v_today
  ),
  per_user_week as (
    select c.id as uid,
      count(distinct aw.id) filter (where aw.recurrence_type<>'times_per_week') as sched_daily,
      coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type='times_per_week'),0) as sched_weekly,
      count(wl.*) filter (where wl.status='completed') as done
    from candidates c
    left join active_worships aw on aw.user_id=c.id
    left join week_logs wl on wl.user_id=c.id and wl.status='completed'
    group by c.id
  ),
  last14 as (
    select l.user_id, l.date from st_daily_worship_logs l
    where l.user_id in (select id from candidates)
      and l.status='completed' and l.date >= v_today-13
    group by l.user_id, l.date
  ),
  computed as (
    select c.id as uid, p.display_name as dname, coalesce(fs.share_level,'none') as slevel,
      fs.selected_text as stext,
      (coalesce(puw.sched_daily,0)+coalesce(puw.sched_weekly,0))::int as sched,
      coalesce(puw.done,0)::int as comp,
      case when (coalesce(puw.sched_daily,0)+coalesce(puw.sched_weekly,0))>0
        then round(coalesce(puw.done,0)::numeric/(puw.sched_daily+puw.sched_weekly)*100)::int else 0 end as p,
      (select count(*) from last14 l14 where l14.user_id=c.id and l14.date>=v_today-6)::int as a7,
      (select count(*) from last14 l14 where l14.user_id=c.id and l14.date<v_today-6)::int as p7
    from candidates c
    join st_profiles p on p.id = c.id
    left join st_fellowship_settings fs on fs.user_id = c.id
    left join per_user_week puw on puw.uid = c.id
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

analyze st_worships; analyze st_daily_worship_logs;

select (select count(*) from st_worships) as worships_count,
  (select count(*) from st_daily_worship_logs) as logs_count,
  (select count(distinct user_id) from st_daily_worship_logs) as active_users_count,
  pg_size_pretty(pg_database_size(current_database())) as total_db_size;

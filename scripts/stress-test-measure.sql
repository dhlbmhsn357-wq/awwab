-- ════════════════════════════════════════════════════════════
--  أواب — قياس زمن get_fellowship_feed عند 4 مقاييس مختلفة، على
--  نفس الـ200,000 صف المزروعة (فلترة seq بدل إعادة زرع 4 مرات).
--  شغّل الأربع كتل دي واحدة واحدة، وابعتلي نتيجة كل واحدة (خصوصًا
--  سطر "Execution Time" في الآخر).
-- ════════════════════════════════════════════════════════════

-- ── 1: عند 1,000 مستخدم ──
explain analyze
with scoped_profiles as (select * from st_profiles where seq <= 1000),
active_worships as (
  select w.id, w.user_id, w.recurrence_type, w.weekly_target
  from st_worships w join scoped_profiles p on p.id=w.user_id
  where w.is_paused=false and w.is_hidden=false and w.deleted_at is null
),
week_logs as (
  select l.user_id, l.worship_id, l.date, l.status from st_daily_worship_logs l
  join scoped_profiles p on p.id=l.user_id
  where l.date >= current_date - extract(dow from current_date)::int and l.date <= current_date
),
per_user_week as (
  select p.id as uid,
    count(distinct aw.id) filter (where aw.recurrence_type<>'times_per_week') as sched_daily,
    coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type='times_per_week'),0) as sched_weekly,
    count(wl.*) filter (where wl.status='completed') as done
  from scoped_profiles p
  left join active_worships aw on aw.user_id=p.id
  left join week_logs wl on wl.user_id=p.id and wl.status='completed'
  group by p.id
)
select p.id, p.display_name, coalesce(fs.share_level,'none'), puw.sched_daily+puw.sched_weekly, puw.done
from scoped_profiles p
left join st_fellowship_settings fs on fs.user_id=p.id
left join per_user_week puw on puw.uid=p.id
order by puw.done desc nulls last
limit 50;

-- ── 2: عند 10,000 مستخدم ── (نفس الاستعلام، seq <= 10000)
explain analyze
with scoped_profiles as (select * from st_profiles where seq <= 10000),
active_worships as (
  select w.id, w.user_id, w.recurrence_type, w.weekly_target
  from st_worships w join scoped_profiles p on p.id=w.user_id
  where w.is_paused=false and w.is_hidden=false and w.deleted_at is null
),
week_logs as (
  select l.user_id, l.worship_id, l.date, l.status from st_daily_worship_logs l
  join scoped_profiles p on p.id=l.user_id
  where l.date >= current_date - extract(dow from current_date)::int and l.date <= current_date
),
per_user_week as (
  select p.id as uid,
    count(distinct aw.id) filter (where aw.recurrence_type<>'times_per_week') as sched_daily,
    coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type='times_per_week'),0) as sched_weekly,
    count(wl.*) filter (where wl.status='completed') as done
  from scoped_profiles p
  left join active_worships aw on aw.user_id=p.id
  left join week_logs wl on wl.user_id=p.id and wl.status='completed'
  group by p.id
)
select p.id, p.display_name, coalesce(fs.share_level,'none'), puw.sched_daily+puw.sched_weekly, puw.done
from scoped_profiles p
left join st_fellowship_settings fs on fs.user_id=p.id
left join per_user_week puw on puw.uid=p.id
order by puw.done desc nulls last
limit 50;

-- ── 3: عند 100,000 مستخدم ──
explain analyze
with scoped_profiles as (select * from st_profiles where seq <= 100000),
active_worships as (
  select w.id, w.user_id, w.recurrence_type, w.weekly_target
  from st_worships w join scoped_profiles p on p.id=w.user_id
  where w.is_paused=false and w.is_hidden=false and w.deleted_at is null
),
week_logs as (
  select l.user_id, l.worship_id, l.date, l.status from st_daily_worship_logs l
  join scoped_profiles p on p.id=l.user_id
  where l.date >= current_date - extract(dow from current_date)::int and l.date <= current_date
),
per_user_week as (
  select p.id as uid,
    count(distinct aw.id) filter (where aw.recurrence_type<>'times_per_week') as sched_daily,
    coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type='times_per_week'),0) as sched_weekly,
    count(wl.*) filter (where wl.status='completed') as done
  from scoped_profiles p
  left join active_worships aw on aw.user_id=p.id
  left join week_logs wl on wl.user_id=p.id and wl.status='completed'
  group by p.id
)
select p.id, p.display_name, coalesce(fs.share_level,'none'), puw.sched_daily+puw.sched_weekly, puw.done
from scoped_profiles p
left join st_fellowship_settings fs on fs.user_id=p.id
left join per_user_week puw on puw.uid=p.id
order by puw.done desc nulls last
limit 50;

-- ── 4: عند 200,000 مستخدم (كل البيانات المزروعة) ──
explain analyze
select * from st_get_fellowship_feed((select id from st_profiles limit 1));

-- ── 5: استعلام قائمة الإدارة (profiles pagination) عند 200,000 ──
explain analyze
select id, display_name, 'member' as role from st_profiles order by display_name asc limit 51 offset 0;

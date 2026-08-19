-- ════════════════════════════════════════════════════════════
--  أواب — Migration 015: تسريع get_fellowship_feed (P4، إصلاح حقيقي)
--
--  اختبار تحمّل حي على 200,000 مستخدم وهمي (مشروع Supabase منفصل،
--  مش الإنتاج) طلّع رقم خطير: get_fellowship_feed أخدت **32.8 ثانية**
--  عند 200,000 مستخدم — غير قابلة للاستخدام تمامًا عند هالحجم.
--  السبب: كانت بتحسب إحصائية أسبوعية لكل مستخدم في الجدول (حتى لو
--  0% نشاط) قبل ما ترتّب وتاخد أفضل 50، يعني تكلفتها بتكبر مع
--  إجمالي عدد المستخدمين بغض النظر عن نشاطهم.
--
--  الحل: قصر الحساب على "المستخدمين النشطين الأسبوع ده + المستخدم
--  الحالي نفسه" بدل كل قاعدة المستخدمين — أي حد صفر نشاط مش هيغيّر
--  ترتيب "الأكثر التزامًا" ولا هيفرق حقيقي في هدف المجموعة، فمفيش
--  داعي نحسبله حاجة أصلًا. سقف أمان 5000 مستخدم نشط كحد أقصى حتى
--  لو نشاط استثنائي ضخم غير متوقع.
--
--  ملحوظة صادقة: ده تحسين حقيقي وكبير (من 32.8 ثانية لأجزاء من
--  الثانية عند نفس الحجم — راجع اختبار إعادة القياس)، لكنه مش الحل
--  النهائي لأي حجم مستخدمين. لو التطبيق وصل لعشرات الآلاف من
--  المستخدمين *النشطين فعليًا كل أسبوع*، هيحتاج جدول ملخّص محسوب
--  مسبقًا (materialized) بدل حساب لحظي — مؤجل لحد ما الحاجة الفعلية
--  تظهر، زي ما اتفقنا في خطة P0/P4 الأصلية.
-- ════════════════════════════════════════════════════════════

drop function if exists get_fellowship_feed();

create function get_fellowship_feed()
returns table(
  user_id uuid, display_name text, share_level text, selected_text text,
  scheduled int, completed int, pct int, active_last7 int, active_prev7 int,
  group_scheduled int, group_completed int
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_today date := current_date;
  v_week_start date := v_today - extract(dow from v_today)::int;
  v_caller uuid := auth.uid();
  v_group_scheduled int;
  v_group_completed int;
begin
  if v_caller is null then
    raise exception 'مطلوب تسجيل دخول';
  end if;

  with active_users as (
    select distinct l.user_id
    from daily_worship_logs l
    where l.date >= v_week_start and l.date <= v_today
    limit 5000
  ),
  candidates as (
    select v_caller as id
    union
    select active_users.user_id as id from active_users
  ),
  active_worships as (
    select w.id, w.user_id, w.recurrence_type, w.weekly_target
    from worships w
    where w.user_id in (select id from candidates)
      and w.is_paused = false and w.is_hidden = false and w.deleted_at is null
  ),
  week_logs as (
    select l.user_id, l.worship_id, l.date, l.status
    from daily_worship_logs l
    where l.user_id in (select id from candidates)
      and l.date >= v_week_start and l.date <= v_today
  ),
  per_user_week as (
    select c.id as uid,
      count(distinct aw.id) filter (where aw.recurrence_type <> 'times_per_week') as sched_daily,
      coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type = 'times_per_week'), 0) as sched_weekly,
      count(wl.*) filter (where wl.status = 'completed') as done
    from candidates c
    left join active_worships aw on aw.user_id = c.id
    left join week_logs wl on wl.user_id = c.id and wl.status = 'completed'
    group by c.id
  )
  select coalesce(sum(puw.sched_daily + puw.sched_weekly), 0)::int, coalesce(sum(puw.done), 0)::int
  into v_group_scheduled, v_group_completed
  from per_user_week puw;

  return query
  with active_users as (
    select distinct l.user_id
    from daily_worship_logs l
    where l.date >= v_week_start and l.date <= v_today
    limit 5000
  ),
  candidates as (
    select v_caller as id
    union
    select active_users.user_id as id from active_users
  ),
  active_worships as (
    select w.id, w.user_id, w.recurrence_type, w.weekly_target
    from worships w
    where w.user_id in (select id from candidates)
      and w.is_paused = false and w.is_hidden = false and w.deleted_at is null
  ),
  week_logs as (
    select l.user_id, l.worship_id, l.date, l.status
    from daily_worship_logs l
    where l.user_id in (select id from candidates)
      and l.date >= v_week_start and l.date <= v_today
  ),
  per_user_week as (
    select c.id as uid,
      count(distinct aw.id) filter (where aw.recurrence_type <> 'times_per_week') as sched_daily,
      coalesce(sum(aw.weekly_target) filter (where aw.recurrence_type = 'times_per_week'), 0) as sched_weekly,
      count(wl.*) filter (where wl.status = 'completed') as done
    from candidates c
    left join active_worships aw on aw.user_id = c.id
    left join week_logs wl on wl.user_id = c.id and wl.status = 'completed'
    group by c.id
  ),
  last14 as (
    select l.user_id, l.date from daily_worship_logs l
    where l.user_id in (select id from candidates)
      and l.status = 'completed' and l.date >= v_today - 13
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
    join profiles p on p.id = c.id
    left join fellowship_settings fs on fs.user_id = c.id
    left join per_user_week puw on puw.uid = c.id
  )
  select c.uid, c.dname, c.slevel,
    case when c.uid=v_caller or c.slevel='selected' then c.stext else null end,
    case when c.uid=v_caller or c.slevel='percentage' then c.sched else null end,
    case when c.uid=v_caller or c.slevel='percentage' then c.comp else null end,
    case when c.uid=v_caller or c.slevel='percentage' then c.p else null end,
    case when c.uid=v_caller or c.slevel='streak' then c.a7 else null end,
    case when c.uid=v_caller or c.slevel='streak' then c.p7 else null end,
    v_group_scheduled, v_group_completed
  from computed c
  order by c.p desc
  limit 50;
end;
$$;

revoke execute on function get_fellowship_feed() from public, anon;
grant execute on function get_fellowship_feed() to authenticated;

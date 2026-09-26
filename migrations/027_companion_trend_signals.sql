-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 027: إشارات صحبتي (انقطاع/تراجع) + موافقة
--
--  غير هدّامة: إضافة عمود موافقة + إعادة تعريف get_my_companions
--  بإضافة حقول حالة (status, days_since_activity) محسوبة server-side.
--  مفيش raw logs بتوصل للعميل — بس status + عدّاد أيام + الملخص
--  المسموح به (زي ما كان). كل الحساب في aggregate واحد (مفيش N+1).
--
--  الخصوصية: إشارتا "انقطاع/تراجع" مايتشاركوش إلا لو صاحبها فعّل
--  share_decline_signal (افتراضي false للجميع). "أحتاج تفقدًا"
--  (needs_checkin) بيفضل ظاهرًا لأنه اختيار صريح من المستخدم نفسه.
--
--  تعريف الانقطاع: مفيش أي daily_worship_log مكتمل لأكثر من يومين
--  كاملين (>2). تعريف التراجع: نشاط آخر 7 أيام أقل من 60% من baseline
--  آخر 21 يوم، بشرط baseline كافٍ (تفادي الإنذار الكاذب) وإلا فلا إشارة.
-- ════════════════════════════════════════════════════════════

alter table companion_settings add column if not exists share_decline_signal boolean not null default false;

-- تغيير توقيع الإرجاع يستلزم DROP قبل CREATE
drop function if exists get_my_companions();

create function get_my_companions()
returns table(
  comp_id uuid, user_id uuid, display_name text,
  today_pct int, active_last7 int, active_prev7 int,
  encourage_names text[], needs_checkin boolean, needs_checkin_note text,
  whatsapp text,
  status text, days_since_activity int
)
language plpgsql security definer set search_path = public stable as $$
declare
  v_caller uuid := auth.uid();
  v_today date := current_date;
  v_dow int := extract(dow from current_date)::int;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  return query
  with mine as (
    select c.id as comp_id,
      case when c.requester_id=v_caller then c.recipient_id else c.requester_id end as uid
    from companionships c
    where c.status='accepted' and (c.requester_id=v_caller or c.recipient_id=v_caller)
    limit 10
  ),
  sched as (
    select m.uid, count(*)::int as cnt
    from mine m
    join worships w on w.user_id=m.uid
      and w.is_paused=false and w.is_hidden=false and w.deleted_at is null
      and (w.recurrence_type='daily' or (w.recurrence_type='specific_days' and v_dow = any(w.days_of_week)))
    group by m.uid
  ),
  donetoday as (
    select m.uid, count(*)::int as cnt
    from mine m
    join daily_worship_logs l on l.user_id=m.uid and l.date=v_today and l.status='completed'
    join worships w on w.id=l.worship_id and w.is_paused=false and w.is_hidden=false and w.deleted_at is null
      and (w.recurrence_type='daily' or (w.recurrence_type='specific_days' and v_dow = any(w.days_of_week)))
    group by m.uid
  ),
  -- أيام النشاط (يوم فيه تسجيل مكتمل واحد على الأقل) خلال آخر 28 يوم
  actdays as (
    select m.uid, l.date
    from mine m
    join daily_worship_logs l on l.user_id=m.uid and l.status='completed' and l.date >= v_today-27
    group by m.uid, l.date
  ),
  agg as (
    select m.uid,
      (select count(*) from actdays a where a.uid=m.uid and a.date>=v_today-6)::int as cur7,
      (select count(*) from actdays a where a.uid=m.uid and a.date>=v_today-6)::int as last7,
      (select count(*) from actdays a where a.uid=m.uid and a.date< v_today-6 and a.date>=v_today-13)::int as prev7,
      (select count(*) from actdays a where a.uid=m.uid and a.date< v_today-6)::int as base21,
      (select max(a.date) from actdays a where a.uid=m.uid) as last_act
    from mine m
  )
  select m.comp_id, m.uid, p.display_name,
    -- نسبة اليوم (لو سامح)
    case when coalesce(cs.share_today_pct,false) and coalesce(s.cnt,0)>0
      then round(coalesce(d.cnt,0)::numeric/s.cnt*100)::int else null end,
    -- ملخص أسبوعي (لو سامح)
    case when coalesce(cs.share_weekly,false) then g.last7 else null end,
    case when coalesce(cs.share_weekly,false) then g.prev7 else null end,
    (select coalesce(array_agg(w2.name), '{}'::text[]) from worships w2
       where w2.user_id=m.uid and w2.id = any(coalesce(cs.encourage_worship_ids,'{}'::uuid[]))
         and w2.deleted_at is null),
    (cs.needs_checkin_at is not null),
    case when cs.needs_checkin_at is not null then cs.needs_checkin_note else null end,
    cs.whatsapp,
    -- الحالة: needs_checkin دايمًا (اختيار صريح) ثم إشارات التراجع/الانقطاع
    -- بموافقة فقط، وإلا 'ok'. مع تفادي الإنذار الكاذب.
    (case
       when cs.needs_checkin_at is not null then 'needs_checkin'
       when not coalesce(cs.share_decline_signal,false) then 'ok'
       when g.last_act is null or g.base21 < 3 then 'ok'  -- بيانات غير كافية → لا إشارة
       when (v_today - g.last_act) > 2 then 'inactive'
       when g.base21 >= 8 and (g.cur7::numeric/7.0) < (g.base21::numeric/21.0)*0.6 then 'decline'
       else 'ok'
     end),
    case when coalesce(cs.share_decline_signal,false) and g.last_act is not null
         then (v_today - g.last_act)::int else null end
  from mine m
  join profiles p on p.id=m.uid
  left join companion_settings cs on cs.user_id=m.uid
  left join sched s on s.uid=m.uid
  left join donetoday d on d.uid=m.uid
  left join agg g on g.uid=m.uid;
end; $$;

revoke execute on function get_my_companions() from public, anon;
grant  execute on function get_my_companions() to authenticated;

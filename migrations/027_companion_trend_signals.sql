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
  -- عدد المجدول لكل يوم-أسبوع من العبادات الحالية النشطة (تقريب معقول
  -- للجدول التاريخي — يراعي تغيّر الجدول قدر الممكن بالاعتماد على
  -- الحالة الحالية للعبادات)
  sched_dow as (
    select m.uid, gs.dow, count(*)::int as cnt
    from mine m
    join worships w on w.user_id=m.uid and w.is_paused=false and w.is_hidden=false and w.deleted_at is null
    cross join generate_series(0,6) as gs(dow)
    where w.recurrence_type='daily' or (w.recurrence_type='specific_days' and gs.dow = any(w.days_of_week))
    group by m.uid, gs.dow
  ),
  sched_today as ( select uid, cnt from sched_dow where dow = v_dow ),
  donetoday as (
    select m.uid, count(*)::int as cnt
    from mine m
    join daily_worship_logs l on l.user_id=m.uid and l.date=v_today and l.status='completed'
    join worships w on w.id=l.worship_id and w.is_paused=false and w.is_hidden=false and w.deleted_at is null
      and (w.recurrence_type='daily' or (w.recurrence_type='specific_days' and v_dow = any(w.days_of_week)))
    group by m.uid
  ),
  -- أيام فيها إنجاز (للملخص الأسبوعي فقط — streak text)
  compdays as (
    select m.uid, l.date
    from mine m
    join daily_worship_logs l on l.user_id=m.uid and l.status='completed' and l.date >= v_today-13
    group by m.uid, l.date
  ),
  -- إنجاز فعلي لكل يوم (ضمن العبادات النشطة) خلال 28 يوم
  done_day as (
    select m.uid, l.date, count(*)::int as cnt
    from mine m
    join daily_worship_logs l on l.user_id=m.uid and l.status='completed' and l.date between v_today-27 and v_today-1
    join worships w on w.id=l.worship_id and w.is_paused=false and w.is_hidden=false and w.deleted_at is null
    group by m.uid, l.date
  ),
  -- أي تسجيل (أي حالة: completed/missed/…) — لقياس "بيانات كافية" وعدد أيام التفاعل
  anylog_day as (
    select m.uid, l.date
    from mine m
    join daily_worship_logs l on l.user_id=m.uid and l.date between v_today-27 and v_today-1
    group by m.uid, l.date
  ),
  -- شبكة الأيام × نسبة الإنجاز اليومية (مقام = مجدول ذلك اليوم؛ نتجاهل
  -- الأيام التي لا جدول فيها)
  daygrid as (
    select m.uid, d::date as day, extract(dow from d)::int as dow
    from mine m
    cross join generate_series(v_today-27, v_today-1, interval '1 day') d
  ),
  rates as (
    select dg.uid, dg.day,
      case when coalesce(sd.cnt,0) > 0
        then least(1.0, coalesce(dn.cnt,0)::numeric / sd.cnt) else null end as rate
    from daygrid dg
    left join sched_dow sd on sd.uid=dg.uid and sd.dow=dg.dow
    left join done_day dn on dn.uid=dg.uid and dn.date=dg.day
  ),
  trend as (
    select r.uid,
      avg(r.rate) filter (where r.day <  v_today-6) as base_rate,
      count(r.rate) filter (where r.day <  v_today-6) as base_days,
      avg(r.rate) filter (where r.day >= v_today-6) as cur_rate,
      count(r.rate) filter (where r.day >= v_today-6) as cur_days,
      (select count(*) from anylog_day a where a.uid=r.uid and a.date <  v_today-6)::int as base_active_days
    from rates r group by r.uid
  ),
  -- آخر نشاط تسجيلي حقيقي (أي حالة) عبر updated_at — أساس الانقطاع
  lastact as (
    select m.uid,
      (select max(l.updated_at)::date from daily_worship_logs l where l.user_id=m.uid) as last_any,
      (select count(*) from anylog_day a where a.uid=m.uid)::int as active28
    from mine m
  ),
  wk as (
    select m.uid,
      (select count(*) from compdays x where x.uid=m.uid and x.date>=v_today-6)::int as last7,
      (select count(*) from compdays x where x.uid=m.uid and x.date< v_today-6)::int as prev7
    from mine m
  )
  select m.comp_id, m.uid, p.display_name,
    case when coalesce(cs.share_today_pct,false) and coalesce(s.cnt,0)>0
      then round(coalesce(d.cnt,0)::numeric/s.cnt*100)::int else null end,
    case when coalesce(cs.share_weekly,false) then wk.last7 else null end,
    case when coalesce(cs.share_weekly,false) then wk.prev7 else null end,
    (select coalesce(array_agg(w2.name), '{}'::text[]) from worships w2
       where w2.user_id=m.uid and w2.id = any(coalesce(cs.encourage_worship_ids,'{}'::uuid[]))
         and w2.deleted_at is null),
    (cs.needs_checkin_at is not null),
    case when cs.needs_checkin_at is not null then cs.needs_checkin_note else null end,
    cs.whatsapp,
    -- الحالة: اختيار صريح أولًا، ثم (بموافقة فقط) انقطاع/تراجع/بيانات
    -- غير كافية. الانقطاع = مفيش أي تسجيل (أي حالة) لأكثر من يومين مع
    -- وجود تاريخ سابق. التراجع = نسبة إنجاز آخر 7 أيام < 60% من baseline
    -- (≥40% هبوط) مع بيانات كافية. غير كده = ok أو insufficient_data.
    (case
       when cs.needs_checkin_at is not null then 'needs_checkin'
       when not coalesce(cs.share_decline_signal,false) then 'ok'
       when la.last_any is not null and (v_today - la.last_any) > 2 and la.active28 >= 3 then 'inactive'
       when t.base_days < 10 or t.base_active_days < 8 or t.cur_days < 3 then 'insufficient_data'
       when t.base_rate is not null and t.base_rate > 0 and t.cur_rate < t.base_rate * 0.6 then 'decline'
       else 'ok'
     end),
    case when coalesce(cs.share_decline_signal,false) and la.last_any is not null
         then (v_today - la.last_any)::int else null end
  from mine m
  join profiles p on p.id=m.uid
  left join companion_settings cs on cs.user_id=m.uid
  left join sched_today s on s.uid=m.uid
  left join donetoday d on d.uid=m.uid
  left join trend t on t.uid=m.uid
  left join lastact la on la.uid=m.uid
  left join wk on wk.uid=m.uid;
end; $$;

revoke execute on function get_my_companions() from public, anon;
grant  execute on function get_my_companions() to authenticated;

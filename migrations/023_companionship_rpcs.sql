-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 023: صحبتي — الدوال المؤمّنة (RPCs)
--  كل تعديل على العلاقات بيمرّ من هنا. الدوال SECURITY DEFINER لكن
--  بتتحقق من auth.uid() وقواعد الحالة بنفسها — العميل مايقدرش يكتب
--  على الجدول مباشرة (مفيش write policies في 022).
--  المبدأ الأمني: Pending مايفتحش أي بيانات؛ Accepted بس؛ الإزالة/
--  الحظر يقفلوا الوصول فورًا. الحد 5 أشخاص مقبولين بيتفرض في القبول.
-- ════════════════════════════════════════════════════════════

-- عدد الصحبة المقبولين لمستخدم (للحد الأقصى 5)
create or replace function _companion_accepted_count(p_user uuid)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from companionships
  where status='accepted' and (requester_id=p_user or recipient_id=p_user);
$$;

-- ── إرسال طلب صحبة ──
create or replace function send_companion_request(p_target uuid, p_message text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid(); v_id uuid;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  if p_target = v_caller then raise exception 'لا يمكنك دعوة نفسك'; end if;
  if not exists (select 1 from profiles where id = p_target) then raise exception 'المستخدم غير موجود'; end if;
  -- فيه علاقة نشطة/محظورة بالفعل؟
  if exists (
    select 1 from companionships
    where status in ('pending','accepted','blocked')
      and least(requester_id,recipient_id)=least(v_caller,p_target)
      and greatest(requester_id,recipient_id)=greatest(v_caller,p_target)
  ) then raise exception 'يوجد طلب أو علاقة بالفعل مع هذا الشخص'; end if;
  -- حد الصحبة عند المُرسِل نفسه (مايبعتش لو هو أصلاً وصل الحد)
  if _companion_accepted_count(v_caller) >= 5 then
    raise exception 'وصلت الحد الأقصى (5 أشخاص) في صحبتك';
  end if;
  insert into companionships(requester_id, recipient_id, status, invite_message)
  values (v_caller, p_target, 'pending', nullif(trim(coalesce(p_message,'')),''))
  returning id into v_id;
  return v_id;
end; $$;

-- ── الرد على طلب (المستلم فقط): قبول/رفض ──
create or replace function respond_companion_request(p_id uuid, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid(); r companionships;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  select * into r from companionships where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if r.recipient_id <> v_caller then raise exception 'غير مصرّح'; end if;
  if r.status <> 'pending' then raise exception 'الطلب لم يعد معلّقًا'; end if;
  if p_accept then
    -- الحد 5 للطرفين وقت القبول
    if _companion_accepted_count(r.requester_id) >= 5 then raise exception 'الطرف الآخر وصل الحد الأقصى'; end if;
    if _companion_accepted_count(r.recipient_id) >= 5 then raise exception 'وصلت الحد الأقصى (5 أشخاص)'; end if;
    update companionships set status='accepted', accepted_at=now(), updated_at=now() where id=p_id;
  else
    update companionships set status='declined', updated_at=now() where id=p_id;
  end if;
end; $$;

-- ── إلغاء طلب معلّق (المُرسِل فقط) ──
create or replace function cancel_companion_request(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid(); r companionships;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  select * into r from companionships where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if r.requester_id <> v_caller then raise exception 'غير مصرّح'; end if;
  if r.status <> 'pending' then raise exception 'الطلب لم يعد معلّقًا'; end if;
  update companionships set status='cancelled', updated_at=now() where id=p_id;
end; $$;

-- ── إزالة صحبة قائمة (أي طرف) ──
create or replace function remove_companion(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid(); r companionships;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  select * into r from companionships where id = p_id;
  if not found then raise exception 'العلاقة غير موجودة'; end if;
  if v_caller not in (r.requester_id, r.recipient_id) then raise exception 'غير مصرّح'; end if;
  if r.status <> 'accepted' then raise exception 'لا توجد صحبة قائمة لإزالتها'; end if;
  update companionships set status='removed', updated_at=now() where id=p_id;
end; $$;

-- ── حظر (أي طرف، في أي حالة نشطة) ──
create or replace function block_companion(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid(); r companionships;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  select * into r from companionships where id = p_id;
  if not found then raise exception 'العلاقة غير موجودة'; end if;
  if v_caller not in (r.requester_id, r.recipient_id) then raise exception 'غير مصرّح'; end if;
  update companionships set status='blocked', blocked_by=v_caller, updated_at=now() where id=p_id;
end; $$;

-- ── فك الحظر (اللي حظر فقط) ──
create or replace function unblock_companion(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid(); r companionships;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  select * into r from companionships where id = p_id;
  if not found then raise exception 'العلاقة غير موجودة'; end if;
  if r.status <> 'blocked' or r.blocked_by <> v_caller then raise exception 'غير مصرّح'; end if;
  update companionships set status='removed', blocked_by=null, updated_at=now() where id=p_id;
end; $$;

-- ── "أحتاج تفقدًا" — حالة مؤقتة تظهر لكل صحبتي (أو إلغاؤها) ──
create or replace function set_needs_checkin(p_on boolean, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid();
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  insert into companion_settings(user_id, needs_checkin_at, needs_checkin_note)
  values (v_caller, case when p_on then now() else null end, case when p_on then nullif(trim(coalesce(p_note,'')),'') else null end)
  on conflict (user_id) do update
    set needs_checkin_at = case when p_on then now() else null end,
        needs_checkin_note = case when p_on then nullif(trim(coalesce(p_note,'')),'') else null end,
        updated_at = now();
end; $$;

-- ── طلبات الصحبة المعلّقة (واردة + صادرة) مع اسم الطرف الآخر ──
create or replace function get_companion_requests()
returns table(id uuid, other_id uuid, other_name text, direction text, invite_message text, created_at timestamptz)
language plpgsql security definer set search_path = public stable as $$
declare v_caller uuid := auth.uid();
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  return query
    select c.id,
      case when c.requester_id=v_caller then c.recipient_id else c.requester_id end,
      p.display_name,
      case when c.requester_id=v_caller then 'outgoing' else 'incoming' end,
      c.invite_message, c.created_at
    from companionships c
    join profiles p on p.id = (case when c.requester_id=v_caller then c.recipient_id else c.requester_id end)
    where c.status='pending' and (c.requester_id=v_caller or c.recipient_id=v_caller)
    order by c.created_at desc;
end; $$;

-- ── صحبتي المقبولين + الملخص المسموح به (المكان الوحيد اللي بيكشف
--    بيانات طرف تاني، وبيراعي تفضيلاته بنفسه — لا Raw logs للعميل) ──
create or replace function get_my_companions()
returns table(
  comp_id uuid, user_id uuid, display_name text,
  today_pct int, active_last7 int, active_prev7 int,
  encourage_names text[], needs_checkin boolean, needs_checkin_note text,
  whatsapp text
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
    limit 5
  ),
  sched as ( -- عبادات النهاردة المجدولة لكل صاحب (يومي/أيام محددة فقط)
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
  last14 as (
    select m.uid, l.date
    from mine m
    join daily_worship_logs l on l.user_id=m.uid and l.status='completed' and l.date >= v_today-13
    group by m.uid, l.date
  )
  select m.comp_id, m.uid, p.display_name,
    case when coalesce(cs.share_today_pct,false) and coalesce(s.cnt,0)>0
      then round(coalesce(d.cnt,0)::numeric/s.cnt*100)::int else null end,
    case when coalesce(cs.share_weekly,false)
      then (select count(*) from last14 x where x.uid=m.uid and x.date>=v_today-6)::int else null end,
    case when coalesce(cs.share_weekly,false)
      then (select count(*) from last14 x where x.uid=m.uid and x.date<v_today-6)::int else null end,
    (select coalesce(array_agg(w2.name), '{}'::text[]) from worships w2
       where w2.user_id=m.uid and w2.id = any(coalesce(cs.encourage_worship_ids,'{}'::uuid[]))
         and w2.deleted_at is null),
    (cs.needs_checkin_at is not null),
    case when cs.needs_checkin_at is not null then cs.needs_checkin_note else null end,
    cs.whatsapp
  from mine m
  join profiles p on p.id=m.uid
  left join companion_settings cs on cs.user_id=m.uid
  left join sched s on s.uid=m.uid
  left join donetoday d on d.uid=m.uid;
end; $$;

-- الصلاحيات: الدوال للمستخدمين المسجّلين بس، مش anon
revoke execute on function send_companion_request(uuid,text)   from public, anon;
revoke execute on function respond_companion_request(uuid,boolean) from public, anon;
revoke execute on function cancel_companion_request(uuid)      from public, anon;
revoke execute on function remove_companion(uuid)              from public, anon;
revoke execute on function block_companion(uuid)               from public, anon;
revoke execute on function unblock_companion(uuid)             from public, anon;
revoke execute on function set_needs_checkin(boolean,text)     from public, anon;
revoke execute on function get_companion_requests()            from public, anon;
revoke execute on function get_my_companions()                 from public, anon;
grant execute on function send_companion_request(uuid,text)    to authenticated;
grant execute on function respond_companion_request(uuid,boolean) to authenticated;
grant execute on function cancel_companion_request(uuid)       to authenticated;
grant execute on function remove_companion(uuid)               to authenticated;
grant execute on function block_companion(uuid)                to authenticated;
grant execute on function unblock_companion(uuid)              to authenticated;
grant execute on function set_needs_checkin(boolean,text)      to authenticated;
grant execute on function get_companion_requests()             to authenticated;
grant execute on function get_my_companions()                  to authenticated;

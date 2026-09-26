-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 026: معرّف رقمي عام + بحث آمن + رفع حد صحبتي 10
--
--  غير هدّامة تمامًا: إضافة عمود جديد (nullable ثم backfill آمن)،
--  دوال/triggers جديدة، وإعادة تعريف RPCs موجودة برفع الحد 5→10.
--  مفيش drop لأي جدول/عمود بيانات، ومفيش mass-destructive update.
--
--  1) profiles.public_numeric_id — معرّف رقمي عام (8 أرقام) منفصل تمامًا
--     عن auth.users.id و عن PK. Unique، immutable، السيرفر هو اللي
--     بيولّده (العميل مايقررش قيمته). عشوائي (مش sequential) فمايكشفش
--     عدد المستخدمين ولا سهل التخمين بالجملة.
--  2) companion_settings.discoverable_by_id — تفضيل "السماح بالعثور
--     عليّ عبر المعرّف" (افتراضي true؛ غياب الصف = مسموح).
--  3) find_user_by_public_id() — بحث exact-match واحد فقط، مع rate
--     limit عبر check_rate_limit (منع enumeration)، يرجّع أقل بيانات
--     (اسم + معرّف + حالة العلاقة) — لا إيميل/هاتف/logs/عبادات.
--  4) رفع حد الصحبة المقبولين 5→10 في كل الأماكن السيرفرية.
-- ════════════════════════════════════════════════════════════

-- ── (1) العمود ──
alter table profiles add column if not exists public_numeric_id bigint;

-- مولّد معرّف رقمي عشوائي فريد (8 أرقام: 10000000..99999999) مع retry
create or replace function gen_public_numeric_id()
returns bigint language plpgsql security definer set search_path = public as $$
declare cand bigint; tries int := 0;
begin
  loop
    cand := 10000000 + floor(random() * 90000000)::bigint;  -- [1e7 .. ~1e8)
    exit when not exists (select 1 from profiles where public_numeric_id = cand);
    tries := tries + 1;
    if tries > 50 then raise exception 'تعذّر توليد معرّف فريد'; end if;
  end loop;
  return cand;
end; $$;

-- backfill للمستخدمين الحاليين: صفًا صفًا عشان الـunique index يمنع أي
-- تصادم داخل نفس العملية (كل صف بياخد معرّفًا واحدًا فريدًا)
do $$
declare r record;
begin
  for r in select id from profiles where public_numeric_id is null loop
    update profiles set public_numeric_id = gen_public_numeric_id() where id = r.id;
  end loop;
end $$;

-- فهرس فريد بعد الـbackfill
create unique index if not exists uq_profiles_public_numeric_id
  on profiles (public_numeric_id);

-- السيرفر يولّد المعرّف عند الإنشاء ويتجاهل أي قيمة من العميل
create or replace function set_public_numeric_id()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.public_numeric_id := gen_public_numeric_id();
  return new;
end; $$;
drop trigger if exists trg_profiles_set_public_id on profiles;
create trigger trg_profiles_set_public_id
  before insert on profiles for each row execute function set_public_numeric_id();

-- immutable بعد الإنشاء: منع أي تغيير للمعرّف (حتى من صاحب الصف)
create or replace function protect_public_numeric_id()
returns trigger language plpgsql set search_path = public as $$
begin
  if old.public_numeric_id is not null and new.public_numeric_id is distinct from old.public_numeric_id then
    raise exception 'المعرّف الرقمي غير قابل للتغيير';
  end if;
  return new;
end; $$;
drop trigger if exists trg_profiles_protect_public_id on profiles;
create trigger trg_profiles_protect_public_id
  before update on profiles for each row execute function protect_public_numeric_id();

-- ── (2) تفضيل الاكتشاف عبر المعرّف ──
alter table companion_settings add column if not exists discoverable_by_id boolean not null default true;

-- ── (3) البحث الآمن exact-match + rate limit ──
-- بيرجّع صف واحد بحد أقصى، وبلا أي UUID داخلي (خصوصية): اسم + معرّف
-- عام + حالة علاقة مبسّطة فقط. لو المعرّف غير موجود أو صاحبه قافل
-- الاكتشاف أو بتبحث عن نفسك أو العلاقة blocked → مفيش نتيجة (بلا كشف
-- أي فرق للمهاجم، وبلا كشف أن أحدًا قام بالحظر).
create or replace function find_user_by_public_id(p_public_id bigint)
returns table(display_name text, public_numeric_id bigint, relation text)
language plpgsql security definer set search_path = public as $$
declare
  v_caller uuid := auth.uid();
  v_target profiles;
  v_rel text := 'none';
  v_status text;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  -- منع enumeration: حد أقصى 20 محاولة/دقيقة لكل مستخدم
  if not check_rate_limit('finduid:'||v_caller::text, 20, 60) then
    raise exception 'محاولات كثيرة، انتظر قليلًا' using errcode = '53400';
  end if;
  if p_public_id is null then return; end if;

  -- نأهّل اسم العمود (profiles.public_numeric_id) لتفادي الالتباس مع
  -- متغيّر الإخراج المسمّى public_numeric_id (خطأ 42702)
  select * into v_target from profiles where profiles.public_numeric_id = p_public_id;
  if not found then return; end if;
  if v_target.id = v_caller then return; end if;  -- مش بتدوّر على نفسك

  -- احترام تفضيل الاكتشاف (غياب صف = مسموح)
  if exists (
    select 1 from companion_settings cs
    where cs.user_id = v_target.id and cs.discoverable_by_id = false
  ) then
    return;  -- قافل الاكتشاف → كأنه غير موجود
  end if;

  -- حالة العلاقة الحالية
  select c.status into v_status from companionships c
  where least(c.requester_id,c.recipient_id)=least(v_caller,v_target.id)
    and greatest(c.requester_id,c.recipient_id)=greatest(v_caller,v_target.id)
    and c.status in ('pending','accepted','blocked')
  limit 1;
  -- الحظر: نتعامل معاه كأن النتيجة غير متاحة (مانكشفش أن أحدًا حظر)
  if v_status = 'blocked' then return; end if;
  if v_status = 'accepted' then v_rel := 'companion';
  elsif v_status = 'pending' then v_rel := 'pending';
  else v_rel := 'none'; end if;

  display_name := v_target.display_name;
  public_numeric_id := v_target.public_numeric_id;
  relation := v_rel;
  return next;
end; $$;

-- إرسال طلب صحبة بالمعرّف العام — الحل الوحيد لإرسال طلب لنتيجة بحث
-- (العميل مايشوفش UUID أبدًا). بيحل الـUUID داخليًا server-side، مع
-- rate limit وأخطاء عامة (مايكشفش وجود/عدم وجود المعرّف للمهاجم).
create or replace function send_companion_request_by_public_id(p_public_id bigint, p_message text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid(); v_target uuid; v_status text; v_id uuid;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  if not check_rate_limit('sendreq:'||v_caller::text, 20, 60) then
    raise exception 'محاولات كثيرة، انتظر قليلًا' using errcode = '53400';
  end if;
  -- حل المعرّف + احترام الاكتشاف؛ أي فشل هنا = رسالة عامة موحّدة
  select p.id into v_target from profiles p where p.public_numeric_id = p_public_id;
  if v_target is null
     or v_target = v_caller
     or exists (select 1 from companion_settings cs where cs.user_id=v_target and cs.discoverable_by_id=false)
  then raise exception 'تعذّر إرسال الطلب لهذا المعرّف'; end if;
  -- علاقة قائمة/محظورة؟ (بلا كشف تفاصيل الحظر)
  select c.status into v_status from companionships c
  where status in ('pending','accepted','blocked')
    and least(c.requester_id,c.recipient_id)=least(v_caller,v_target)
    and greatest(c.requester_id,c.recipient_id)=greatest(v_caller,v_target)
  limit 1;
  if v_status = 'blocked' then raise exception 'تعذّر إرسال الطلب لهذا المعرّف'; end if;
  if v_status in ('pending','accepted') then raise exception 'يوجد طلب أو علاقة بالفعل مع هذا الشخص'; end if;
  if _companion_accepted_count(v_caller) >= 10 then raise exception 'وصلت الحد الأقصى (10 أشخاص) في صحبتك'; end if;
  insert into companionships(requester_id, recipient_id, status, invite_message)
  values (v_caller, v_target, 'pending', nullif(trim(coalesce(p_message,'')),''))
  returning id into v_id;
  return v_id;
end; $$;

revoke execute on function find_user_by_public_id(bigint) from public, anon;
grant  execute on function find_user_by_public_id(bigint) to authenticated;
revoke execute on function send_companion_request_by_public_id(bigint,text) from public, anon;
grant  execute on function send_companion_request_by_public_id(bigint,text) to authenticated;
revoke execute on function gen_public_numeric_id() from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════
--  (4) رفع حد الصحبة المقبولين 5 → 10 (السيرفر) — إعادة تعريف
--  نفس دوال 023 بالحد الجديد (create or replace، بلا تغيير توقيع).
-- ════════════════════════════════════════════════════════════
create or replace function send_companion_request(p_target uuid, p_message text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_caller uuid := auth.uid(); v_id uuid;
begin
  if v_caller is null then raise exception 'مطلوب تسجيل دخول'; end if;
  if p_target = v_caller then raise exception 'لا يمكنك دعوة نفسك'; end if;
  if not exists (select 1 from profiles where id = p_target) then raise exception 'المستخدم غير موجود'; end if;
  if exists (
    select 1 from companionships
    where status in ('pending','accepted','blocked')
      and least(requester_id,recipient_id)=least(v_caller,p_target)
      and greatest(requester_id,recipient_id)=greatest(v_caller,p_target)
  ) then raise exception 'يوجد طلب أو علاقة بالفعل مع هذا الشخص'; end if;
  if _companion_accepted_count(v_caller) >= 10 then
    raise exception 'وصلت الحد الأقصى (10 أشخاص) في صحبتك';
  end if;
  insert into companionships(requester_id, recipient_id, status, invite_message)
  values (v_caller, p_target, 'pending', nullif(trim(coalesce(p_message,'')),''))
  returning id into v_id;
  return v_id;
end; $$;

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
    if _companion_accepted_count(r.requester_id) >= 10 then raise exception 'الطرف الآخر وصل الحد الأقصى'; end if;
    if _companion_accepted_count(r.recipient_id) >= 10 then raise exception 'وصلت الحد الأقصى (10 أشخاص)'; end if;
    update companionships set status='accepted', accepted_at=now(), updated_at=now() where id=p_id;
  else
    update companionships set status='declined', updated_at=now() where id=p_id;
  end if;
end; $$;

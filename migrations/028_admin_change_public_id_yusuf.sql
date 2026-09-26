-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 028: تغيير معرّف عام إداري (one-time)
--
--  المطلوب: تغيير public_numeric_id للمستخدم «يوسف حمدي»
--           من 74325511 إلى 20072003 — مرة واحدة فقط.
--
--  الأمان:
--   - استثناء إداري one-time فقط. لا نلغي immutability نهائيًا، ولا
--     نفتح UPDATE للـfrontend، ولا ننشئ RPC عامة.
--   - نعطّل trigger الحماية (trg_profiles_protect_public_id) داخل هذه
--     المعاملة فقط ثم نعيد تفعيله فورًا. لو فشل أي تحقّق → الـDO block
--     يُجهض والمعاملة ترجع (rollback) والـtrigger يعود مفعّلًا.
--   - unique index (uq_profiles_public_numeric_id) يبقى موجودًا طوال
--     الوقت — يمنع أي تكرار.
--   - لا نغيّر auth.uid/UUID، ولا companionships (مبنية على UUID
--     الداخلي مش على public_numeric_id)، ولا logs.
--
--  تحقّقات إلزامية قبل التعديل:
--   1) القديم 74325511 موجود بالضبط مرة واحدة.
--   2) الاسم يطابق «يوسف» (نوقف لو لم يطابق).
--   3) الجديد 20072003 غير مستخدم نهائيًا.
--  (أي فشل → إجهاض بلا أي تغيير)
-- ════════════════════════════════════════════════════════════

do $$
declare
  v_old bigint := 74325511;
  v_new bigint := 20072003;
  v_id  uuid;
  v_cnt int;
  v_name text;
begin
  -- 1) القديم موجود بالضبط مرة واحدة
  select count(*) into v_cnt from profiles where public_numeric_id = v_old;
  if v_cnt <> 1 then
    raise exception 'المعرّف القديم % غير موجود بشكل فريد (count=%) — أوقفنا الإجراء', v_old, v_cnt;
  end if;
  select id, display_name into v_id, v_name from profiles where public_numeric_id = v_old;

  -- 2) تطابق الاسم (best effort — نوقف لو مفيش «يوسف» في الاسم)
  raise notice 'المستخدم المستهدف: id=% | display_name=%', v_id, v_name;
  if position('يوسف' in coalesce(v_name,'')) = 0 then
    raise exception 'الاسم (%) لا يطابق «يوسف» — أوقفنا الإجراء للأمان', v_name;
  end if;

  -- 3) الجديد غير مستخدم
  if exists (select 1 from profiles where public_numeric_id = v_new) then
    raise exception 'المعرّف الجديد % مستخدم بالفعل — أوقفنا الإجراء', v_new;
  end if;

  -- 4) استثناء الحماية داخل هذه المعاملة فقط
  alter table profiles disable trigger trg_profiles_protect_public_id;
  update profiles set public_numeric_id = v_new, updated_at = now() where id = v_id;
  alter table profiles enable trigger trg_profiles_protect_public_id;

  -- 5) تحقّق نهائي
  if not exists (select 1 from profiles where id = v_id and public_numeric_id = v_new) then
    raise exception 'فشل التحقق: المعرّف الجديد لم يُطبَّق';
  end if;
  if exists (select 1 from profiles where public_numeric_id = v_old) then
    raise exception 'فشل التحقق: المعرّف القديم لا يزال موجودًا';
  end if;

  raise notice 'تم بنجاح: المستخدم % — المعرّف من % إلى %', v_id, v_old, v_new;
end $$;

-- تأكيد نهائي (اختياري للعرض): يجب أن يرجع صفًا واحدًا بالمعرّف الجديد
-- select id, display_name, public_numeric_id from profiles where public_numeric_id = 20072003;

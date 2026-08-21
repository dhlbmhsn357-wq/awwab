-- ════════════════════════════════════════════════════════════
--  أواب — Migration 020: إصلاح ثغرة حرجة — رفع صلاحية ذاتي
--  (اكتُشفت أثناء فحص أمان شامل، خطيرة وقابلة للاستغلال فعليًا)
--
--  المشكلة: سياسة profiles_update_own_or_admin (migration 008)
--  بتتحقق إن الصف المُعدَّل بتاع صاحبه بس (id = auth.uid())، لكن
--  مبتتحققش *إيه اللي بيتغيّر فيه*. أي مستخدم عادي يقدر يبعت
--  PATCH لصفه هو بنفسه ويحط role='admin' — الطلب هيتقبل لأنه
--  بيعدّل صفه هو فعلًا. بعدها is_admin() بترجع true له، وبيقدر
--  يشوف/يعدّل/يحذف أي حساب تاني (وحتى يحذف حساب Auth كامل عبر
--  admin-delete-member Edge Function).
--
--  الحل: Trigger بيرفض أي تغيير في عمود role إلا لو المستخدم اللي
--  طالب التعديل admin فعلًا already (مش المستخدم اللي بيتعدّل صفه).
--  التغيير بيترفض بهدوء (يرجّع role لقيمته القديمة) بدل ما يفشل
--  الطلب كله، عشان مايبوظش أي تحديث تاني شرعي (زي onboarding_done)
--  لو حصل بالغلط في نفس الطلب.
-- ════════════════════════════════════════════════════════════

create or replace function prevent_role_self_escalation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role and not is_admin() then
    new.role := old.role;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_role_escalation on profiles;
create trigger trg_prevent_role_escalation
  before update on profiles
  for each row
  execute function prevent_role_self_escalation();

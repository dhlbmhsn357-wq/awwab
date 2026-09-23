-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 025: إحصاءات المشرف (Counts فقط، admin-only)
--
--  الهدف: نعرض للمشرف بس أرقام مجمّعة (إجمالي المستخدمين + النشطون
--  آخر 30/7 يوم) من غير ما الواجهة تحمّل أي صف مستخدم أو تكشف أي
--  بيانة شخصية. دالة واحدة SECURITY DEFINER بترجع Counts فقط.
--
--  الأمان:
--   - الدالة بتتحقق is_admin() جوّاها؛ أي مستخدم عادي بياخد خطأ
--     forbidden (42501)، والـanon محروم من execute أصلًا.
--   - مفيش أي emails/أسماء/IDs بترجع — أرقام صحيحة بس.
--   - غير هدّامة: مفيش تعديل على أي policy أو جدول موجود؛ بس إضافة
--     index مساعد (if not exists) + دالة جديدة.
--
--  تعريف "المستخدم النشط": مستخدم عنده صف واحد على الأقل في
--  daily_worship_logs اتعدّل (updated_at) خلال المدة — يعني سجّل/عدّل
--  عبادة فعليًا، مش مجرد إنشاء حساب.
-- ════════════════════════════════════════════════════════════

-- index مساعد للتجميع على updated_at (رخيص، غير هدّام، بيسرّع
-- العدّ الدوري النادر اللي المشرف بس بيعمله)
create index if not exists idx_dwl_updated_at on daily_worship_logs (updated_at);

create or replace function get_admin_stats()
returns json
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_total int;
  v_30 int;
  v_7 int;
begin
  -- الحارس الحقيقي: مش معتمدين على أي role جاي من الـclient
  if not is_admin() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select count(*) into v_total from profiles;

  select count(distinct user_id) into v_30
  from daily_worship_logs
  where updated_at >= now() - interval '30 days';

  select count(distinct user_id) into v_7
  from daily_worship_logs
  where updated_at >= now() - interval '7 days';

  return json_build_object(
    'totalUsers', v_total,
    'active30d',  v_30,
    'active7d',   v_7
  );
end;
$$;

-- دفاع في العمق: الـanon مايقدرش ينده الدالة خالص؛ الـauthenticated
-- يقدر ينده بس الدالة نفسها بترفض لو مش admin.
revoke all on function get_admin_stats() from public, anon;
grant execute on function get_admin_stats() to authenticated;

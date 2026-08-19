-- ════════════════════════════════════════════════════════════
--  أواب — Migration 016ب: قفل الوصول المباشر (شغّلها آخر حاجة بس،
--  بعد نشر auth-helper Edge Function ونشر كود الواجهة الجديد
--  وتأكيد إنه شغال صح — وإلا تسجيل الدخول/الحساب هيتعطل فورًا).
-- ════════════════════════════════════════════════════════════

revoke execute on function get_login_email(text) from public, anon, authenticated;
grant execute on function get_login_email(text) to service_role;

revoke execute on function is_name_taken(text) from public, anon, authenticated;
grant execute on function is_name_taken(text) to service_role;

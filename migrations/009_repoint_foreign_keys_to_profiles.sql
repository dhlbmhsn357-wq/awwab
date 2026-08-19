-- ════════════════════════════════════════════════════════════
--  أواب — Migration 009: فك الربط القديم بـ users (P0، جزء 3أ)
--
--  اكتشفنا إن worships.user_id (وباقي الجداول) عندها Foreign Key
--  حقيقي بيشاور على users القديم. الترتيب الصحيح للترحيل:
--    1) الملف ده: نشيل القيد القديم بس (من غير ما نضيف بديل دلوقتي)
--       عشان تقدر تتحدّث بيانات worships/... للمعرف الجديد من غير
--       ما تتصادم مع القيد القديم.
--    2) بعد الملف ده تمام: هعيد تشغيل سكريبت الترحيل — دلوقتي
--       هينجح لأن مفيش قيد يمنعه.
--    3) بعد ما الترحيل ينجح 100%: هبعتلك migration 010 اللي بتضيف
--       القيد الجديد (يشاور على profiles) بعد ما البيانات بقت صح.
-- ════════════════════════════════════════════════════════════

alter table worships drop constraint if exists worships_user_id_fkey;
alter table daily_worship_logs drop constraint if exists daily_worship_logs_user_id_fkey;
alter table daily_notes drop constraint if exists daily_notes_user_id_fkey;
alter table fellowship_settings drop constraint if exists fellowship_settings_user_id_fkey;
alter table encouragements drop constraint if exists encouragements_to_user_id_fkey;
alter table encouragements drop constraint if exists encouragements_from_user_id_fkey;

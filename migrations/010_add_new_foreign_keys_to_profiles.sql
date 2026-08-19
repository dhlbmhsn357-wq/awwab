-- ════════════════════════════════════════════════════════════
--  أواب — Migration 010: ربط جديد بـ profiles (P0، جزء 3ب)
--  شغّل الملف ده بعد ما سكريبت الترحيل (migrate-users-to-auth.mjs)
--  ينجح 100% لكل الـ30 مستخدم (يعني كل بيانات worships وباقي
--  الجداول بقت بتشاور على معرف auth.uid() الجديد مش القديم) —
--  وإلا الإضافة هتفشل بنفس الخطأ اللي شفته قبل كده.
-- ════════════════════════════════════════════════════════════

alter table worships add constraint worships_user_id_fkey
  foreign key (user_id) references profiles(id) on delete cascade;

alter table daily_worship_logs add constraint daily_worship_logs_user_id_fkey
  foreign key (user_id) references profiles(id) on delete cascade;

alter table daily_notes add constraint daily_notes_user_id_fkey
  foreign key (user_id) references profiles(id) on delete cascade;

alter table fellowship_settings add constraint fellowship_settings_user_id_fkey
  foreign key (user_id) references profiles(id) on delete cascade;

alter table encouragements add constraint encouragements_to_user_id_fkey
  foreign key (to_user_id) references profiles(id) on delete cascade;

alter table encouragements add constraint encouragements_from_user_id_fkey
  foreign key (from_user_id) references profiles(id) on delete cascade;

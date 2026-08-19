-- ════════════════════════════════════════════════════════════
--  أواب — Migration 005: حالة الجولة التعريفية (Onboarding Tour)
--  آمنة تمامًا: أعمدة جديدة بقيم افتراضية NULL/0، بدون حذف أو
--  تعديل أي بيانة موجودة. أي مستخدم قديم يعتبر تلقائيًا
--  "not_started" في الكود (القيمة NULL = لسه ما شافهاش).
-- ════════════════════════════════════════════════════════════

alter table users add column if not exists onboarding_tour_status text
  check (onboarding_tour_status in ('not_started','in_progress','completed','skipped'));
alter table users add column if not exists onboarding_tour_step int not null default 0;
alter table users add column if not exists onboarding_tour_completed_at timestamptz;

-- ════════════════════════════════════════════════════════════
--  أواب — Migration 017: جداول تلخيص شهري (تحضير للأرشفة)
--
--  إضافية بالكامل، مفيش أي حذف أو تعديل على بيانات موجودة. جدولين:
--
--  1) monthly_worship_summary: إجمالي شهري لكل عبادة (scheduled/
--     completed) — بيحافظ على معدلات الإنجاز في صفحة "تقدّمي" حتى
--     بعد أرشفة السجلات اليومية الخام.
--  2) monthly_day_summary: إجمالي كل يوم بمفرده (applicable/
--     completed) — بيحافظ على تلوين التقويم بالظبط بنفس الدقة
--     الحالية (يوم بيوم)، حتى بعد أرشفة السجلات الخام.
--
--  التفصيلة الوحيدة اللي مش بتتحفظ بعد الأرشفة: الحالة الدقيقة لكل
--  سجل بمفرده (مثلاً "جماعة" ولا "منفرد" بالظبط لصلاة معينة يوم
--  معين قديم) — الملخصات دي بتحافظ على كل حاجة ظاهرة فعليًا في
--  الواجهة (ألوان التقويم، نسب الإنجاز)، بس مش التفصيلة الدقيقة
--  جوه كل سجل بمفرده لأيام قديمة جدًا (أقدم من 90 يوم).
-- ════════════════════════════════════════════════════════════

create table if not exists monthly_worship_summary (
  user_id uuid not null references profiles(id) on delete cascade,
  worship_id uuid not null references worships(id) on delete cascade,
  year int not null,
  month int not null,
  scheduled int not null default 0,
  completed int not null default 0,
  primary key (user_id, worship_id, year, month)
);

create table if not exists monthly_day_summary (
  user_id uuid not null references profiles(id) on delete cascade,
  date date not null,
  applicable_count int not null default 0,
  completed_count int not null default 0,
  has_record boolean not null default true,
  primary key (user_id, date)
);

alter table monthly_worship_summary enable row level security;
create policy "mws_select_own" on monthly_worship_summary for select using (user_id = auth.uid());

alter table monthly_day_summary enable row level security;
create policy "mds_select_own" on monthly_day_summary for select using (user_id = auth.uid());

-- الكتابة على الجدولين دول بتحصل بس من عملية الأرشفة الإدارية
-- (service_role)، مش من المستخدم مباشرة، فمفيش policy لـinsert/
-- update/delete هنا عمدًا.

create index if not exists idx_mds_user_date on monthly_day_summary (user_id, date);

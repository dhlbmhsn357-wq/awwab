-- ════════════════════════════════════════════════════════════
--  أواب — Migration 003: نوع متابعة جديد للصلوات (4 حالات)
--  آمنة تمامًا: تضيف قيمة جديدة لقيد موجود + تحدّث الصلوات
--  الخمس المفروضة بس (بالاسم + الفئة)، بدون حذف أو فقد أي بيانة.
-- ════════════════════════════════════════════════════════════

alter table worships drop constraint if exists worships_tracking_type_check;
alter table worships add constraint worships_tracking_type_check
  check (tracking_type in ('boolean','count','quantity','multi','prayer'));

update worships
set tracking_type = 'prayer'
where category = 'prayer'
  and name in ('صلاة الفجر','صلاة الظهر','صلاة العصر','صلاة المغرب','صلاة العشاء');

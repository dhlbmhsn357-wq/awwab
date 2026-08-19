-- ════════════════════════════════════════════════════════════
--  أواب — Migration 014: فهارس تدعم get_fellowship_feed (P1)
--
--  راجعنا كل الفهارس والـForeign Keys الموجودة فعليًا ولقينا
--  معظمها متظبط بالفعل من مراحل سابقة (idx_dwl_user_date،
--  daily_worship_logs_user_id_worship_id_date_key كـUNIQUE،
--  idx_worships_user، كل الـFKs بترجع cascade صح على profiles).
--
--  الفجوة الوحيدة الحقيقية: get_fellowship_feed() هي الاستعلام
--  الوحيد في التطبيق اللي بيمسح daily_worship_logs وworships عبر
--  *كل* المستخدمين مرة واحدة (مش مفلتر بـuser_id زي باقي
--  الاستعلامات)، فمحتاجة فهارس مختلفة شكلها — على date/status
--  مباشرة، وعلى شروط العبادة النشطة، بدل فهرس يبدأ بـuser_id.
-- ════════════════════════════════════════════════════════════

create index if not exists idx_dwl_date_status
  on daily_worship_logs (date, status);

create index if not exists idx_worships_active_partial
  on worships (user_id, recurrence_type, weekly_target)
  where is_paused = false and is_hidden = false and deleted_at is null;

-- ════════════════════════════════════════════════════════════
--  أواب — زرع بيانات وهمية للاختبار (200,000 مستخدم، أقصى سيناريو
--  متوقع). ممكن ياخد دقيقة لدقيقتين. شغّله بعد stress-test-setup.sql.
-- ════════════════════════════════════════════════════════════

insert into st_profiles (display_name)
select 'مستخدم ' || g
from generate_series(1, 200000) g;

-- 10 عبادات لكل مستخدم (2,000,000 صف) — معظمها يومية، جزء أهداف أسبوعية
insert into st_worships (user_id, recurrence_type, weekly_target, is_paused, is_hidden)
select p.id,
  case when w % 8 = 0 then 'times_per_week' else 'daily' end,
  case when w % 8 = 0 then 1 + (w % 5) else null end,
  false, false
from st_profiles p
cross join generate_series(1, 10) w;

-- سجلات آخر 14 يوم بس (نفس النطاق اللي الاستعلام الحقيقي بيفلتر
-- بيه) بمعدل امتلاء ~50% — أي عدد أكبر من كده هيكون خارج نطاق
-- فلتر التاريخ أصلًا ومش مؤثر على أداء الاستعلام ده تحديدًا
insert into st_daily_worship_logs (user_id, worship_id, date, status)
select w.user_id, w.id, (current_date - d), case when random() < 0.7 then 'completed' else 'skipped' end
from st_worships w
cross join generate_series(0, 13) d
where random() < 0.5;

-- إعدادات خصوصية متنوعة لـ~20% من المستخدمين (الباقي الافتراضي 'none')
insert into st_fellowship_settings (user_id, share_level, selected_text)
select p.id,
  (array['percentage','streak','selected'])[1 + floor(random()*3)::int],
  'إنجاز تجريبي'
from st_profiles p
where random() < 0.2;

analyze st_profiles;
analyze st_worships;
analyze st_daily_worship_logs;
analyze st_fellowship_settings;

select
  (select count(*) from st_profiles) as profiles_count,
  (select count(*) from st_worships) as worships_count,
  (select count(*) from st_daily_worship_logs) as logs_count,
  (select count(*) from st_fellowship_settings) as settings_count,
  pg_size_pretty(pg_total_relation_size('st_daily_worship_logs')) as logs_table_size;

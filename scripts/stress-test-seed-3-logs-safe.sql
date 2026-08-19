-- نسخة أخف: سجلات لعينة 30,000 مستخدم بس (بدل الـ200,000 كلهم) —
-- المساحة المتاحة في الخطة المجانية خلصت مع أول محاولة أكبر.
-- ~1,000,000 صف تقريبًا، آمنة على المساحة المتبقية.
insert into st_daily_worship_logs (user_id, worship_id, date, status)
select w.user_id, w.id, (current_date - d), case when random() < 0.7 then 'completed' else 'skipped' end
from st_worships w
join st_profiles p on p.id = w.user_id and p.seq <= 30000
cross join generate_series(0, 13) d
where random() < 0.3;

insert into st_fellowship_settings (user_id, share_level, selected_text)
select p.id, (array['percentage','streak','selected'])[1 + floor(random()*3)::int], 'إنجاز تجريبي'
from st_profiles p
where p.seq <= 30000 and random() < 0.2;

analyze st_daily_worship_logs; analyze st_fellowship_settings;

select
  (select count(*) from st_daily_worship_logs) as logs_count,
  (select count(*) from st_fellowship_settings) as settings_count,
  pg_size_pretty(pg_database_size(current_database())) as total_db_size;

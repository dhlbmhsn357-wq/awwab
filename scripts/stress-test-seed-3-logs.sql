-- خطوة 3 من 3: سجلات آخر 14 يوم بمعدل امتلاء ~30% (~6.7 مليون صف)
-- ده أثقل خطوة، ممكن تاخد دقيقة أو أكتر
insert into st_daily_worship_logs (user_id, worship_id, date, status)
select w.user_id, w.id, (current_date - d), case when random() < 0.7 then 'completed' else 'skipped' end
from st_worships w
cross join generate_series(0, 13) d
where random() < 0.3;

-- إعدادات خصوصية لـ~20% من المستخدمين
insert into st_fellowship_settings (user_id, share_level, selected_text)
select p.id, (array['percentage','streak','selected'])[1 + floor(random()*3)::int], 'إنجاز تجريبي'
from st_profiles p
where random() < 0.2;

analyze st_profiles; analyze st_worships; analyze st_daily_worship_logs; analyze st_fellowship_settings;

select
  (select count(*) from st_profiles) as profiles_count,
  (select count(*) from st_worships) as worships_count,
  (select count(*) from st_daily_worship_logs) as logs_count,
  (select count(*) from st_fellowship_settings) as settings_count,
  pg_size_pretty(pg_total_relation_size('st_daily_worship_logs')) as logs_table_size;

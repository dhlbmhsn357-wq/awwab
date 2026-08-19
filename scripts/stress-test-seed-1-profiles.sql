-- خطوة 1 من 3: زرع 200,000 مستخدم وهمي — خفيفة، ثواني بس
insert into st_profiles (display_name)
select 'مستخدم ' || g
from generate_series(1, 200000) g;

select count(*) as profiles_count from st_profiles;

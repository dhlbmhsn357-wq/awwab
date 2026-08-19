-- خطوة 2 من 3: 8 عبادات لكل مستخدم (1,600,000 صف) — ممكن تاخد شوية وقت
insert into st_worships (user_id, recurrence_type, weekly_target, is_paused, is_hidden)
select p.id,
  case when w % 8 = 0 then 'times_per_week' else 'daily' end,
  case when w % 8 = 0 then 1 + (w % 5) else null end,
  false, false
from st_profiles p
cross join generate_series(1, 8) w;

select count(*) as worships_count from st_worships;

-- ════════════════════════════════════════════════════════════
--  أواب — Migration 016أ: بنية Rate Limiting (آمنة، مفيش قفل هنا)
--  جزء أول بس — إضافة جديدة، مش بتلمس أي صلاحيات موجودة، آمن
--  100% تشغّله دلوقتي مهما كان كود الواجهة الحالي.
-- ════════════════════════════════════════════════════════════

create table if not exists rate_limits (
  key text primary key,
  window_start timestamptz not null default now(),
  count int not null default 0
);

create or replace function check_rate_limit(p_key text, p_max int, p_window_seconds int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row rate_limits;
begin
  insert into rate_limits (key, window_start, count)
  values (p_key, now(), 1)
  on conflict (key) do update set
    count = case when rate_limits.window_start < now() - (p_window_seconds || ' seconds')::interval
                 then 1 else rate_limits.count + 1 end,
    window_start = case when rate_limits.window_start < now() - (p_window_seconds || ' seconds')::interval
                 then now() else rate_limits.window_start end
  returning * into v_row;

  return v_row.count <= p_max;
end;
$$;

revoke execute on function check_rate_limit(text,int,int) from public, anon, authenticated;
grant execute on function check_rate_limit(text,int,int) to service_role;

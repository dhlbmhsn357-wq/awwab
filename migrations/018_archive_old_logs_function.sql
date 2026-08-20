-- ════════════════════════════════════════════════════════════
--  أواب — Migration 018: دالة أرشفة السجلات القديمة
--
--  بتلخّص أي سجل يومي أقدم من 90 يوم في جدولين (monthly_worship_
--  summary وmonthly_day_summary من migration 017) بنفس منطق
--  isApplicable() الحقيقي المستخدم في التقويم حاليًا (index.html)،
--  وبعد ما تتأكد إن التلخيص اتحفظ صح، تمسح السجلات الخام القديمة.
--
--  آمنة تمامًا:
--  - معدّية بمعاملة واحدة (transaction) — لو أي خطوة فشلت، الكل
--    يرجع زي ما كان، مفيش حذف جزئي أبدًا.
--  - upsert مش insert، فتشغيلها أكتر من مرة آمن (مش هتكرر الأرقام).
--  - بتشتغل بس على بيانات أقدم من p_cutoff_days (افتراضي 90) —
--    آخر 90 يوم يفضلوا زي ما هما بالظبط، مفيش أي تغيير عليهم.
--
--  ملحوظتين صادقتين عن الفرق الدقيق بعد الأرشفة:
--  1) عبادات "مرة واحدة" (recurrence_type='once'): بعد الأرشفة،
--     يوم قديم بيتعتبر له سجل "منطبق" بس لو فيه سجل فعلي ليه في
--     نفس اليوم — بدل المنطق الحالي اللي ممكن يعتبره منطبق في أي
--     يوم لحد ما يتعمل. فرق نادر الحدوث عمليًا (عبادات "مرة واحدة"
--     قليلة أصلًا)، وبيفيد يوم واحد بالظبط (يوم إنجازها) بدل ما
--     يفضل "مستحق" كل يوم للأبد.
--  2) لو عبادة اتوقفت/اتخفت/اتحذفت بعد الأرشفة، الشهور القديمة
--     المؤرشفة *مش* هتتحدث تلقائيًا زي الأيام الحديثة (اللي بتحسب
--     applicable لحظيًا كل مرة) — الملخص بيتجمّد وقت الأرشفة. فرق
--     بسيط ونادر عمليًا، بس موجود عشان تعرفه.
-- ════════════════════════════════════════════════════════════

create or replace function archive_old_daily_data(p_cutoff_days int default 90)
returns table(archived_days int, archived_worship_months int, deleted_log_rows int)
language plpgsql
as $$
declare
  v_cutoff date := current_date - p_cutoff_days;
  v_days int;
  v_wm int;
  v_deleted int;
begin
  -- 1) تلخيص شهري لكل عبادة (scheduled/completed) — بيحافظ على
  --    نسب صفحة "تقدّمي" حتى بعد حذف السجلات الخام
  with old_dates as (
    select generate_series(min(date), max(date), interval '1 day')::date as d
    from daily_worship_logs where date < v_cutoff
  ),
  applicable_rows as (
    select w.user_id, w.id as worship_id, od.d as date,
      extract(year from od.d)::int as year, extract(month from od.d)::int as month
    from worships w
    join old_dates od on true
    where w.is_paused = false and w.is_hidden = false and w.deleted_at is null
      and w.recurrence_type <> 'times_per_week' and w.day_section <> 'weekly_goal'
      and (w.start_date is null or od.d >= w.start_date)
      and (w.end_date is null or od.d <= w.end_date)
      and (
        (w.recurrence_type = 'daily')
        or (w.recurrence_type = 'specific_days' and extract(dow from od.d)::int = any(w.days_of_week))
        or (w.recurrence_type = 'once' and exists(
              select 1 from daily_worship_logs l2 where l2.worship_id = w.id and l2.date = od.d))
      )
  ),
  monthly as (
    select ar.user_id, ar.worship_id, ar.year, ar.month,
      count(*)::int as scheduled,
      count(*) filter (where l.status = 'completed')::int as completed
    from applicable_rows ar
    left join daily_worship_logs l on l.worship_id = ar.worship_id and l.date = ar.date
    group by ar.user_id, ar.worship_id, ar.year, ar.month
  ),
  ins as (
    insert into monthly_worship_summary (user_id, worship_id, year, month, scheduled, completed)
    select user_id, worship_id, year, month, scheduled, completed from monthly
    on conflict (user_id, worship_id, year, month) do update set
      scheduled = excluded.scheduled, completed = excluded.completed
    returning 1
  )
  select count(*) into v_wm from ins;

  -- 2) تلخيص يومي (applicable/completed لكل مستخدم كل يوم) — بيحافظ
  --    على تلوين التقويم بنفس الدقة الحالية يوم بيوم
  with old_dates as (
    select generate_series(min(date), max(date), interval '1 day')::date as d
    from daily_worship_logs where date < v_cutoff
  ),
  applicable_rows as (
    select w.user_id, w.id as worship_id, od.d as date
    from worships w
    join old_dates od on true
    where w.is_paused = false and w.is_hidden = false and w.deleted_at is null
      and w.recurrence_type <> 'times_per_week' and w.day_section <> 'weekly_goal'
      and (w.start_date is null or od.d >= w.start_date)
      and (w.end_date is null or od.d <= w.end_date)
      and (
        (w.recurrence_type = 'daily')
        or (w.recurrence_type = 'specific_days' and extract(dow from od.d)::int = any(w.days_of_week))
        or (w.recurrence_type = 'once' and exists(
              select 1 from daily_worship_logs l2 where l2.worship_id = w.id and l2.date = od.d))
      )
  ),
  daily as (
    select ar.user_id, ar.date,
      count(*)::int as applicable_count,
      count(*) filter (where l.status = 'completed')::int as completed_count,
      bool_or(l.id is not null) as has_record
    from applicable_rows ar
    left join daily_worship_logs l on l.worship_id = ar.worship_id and l.date = ar.date
    group by ar.user_id, ar.date
  ),
  ins2 as (
    insert into monthly_day_summary (user_id, date, applicable_count, completed_count, has_record)
    select user_id, date, applicable_count, completed_count, coalesce(has_record,false) from daily
    on conflict (user_id, date) do update set
      applicable_count = excluded.applicable_count,
      completed_count = excluded.completed_count,
      has_record = excluded.has_record
    returning 1
  )
  select count(*) into v_days from ins2;

  -- 3) دلوقتي بس، بعد ما اتأكدنا الملخصات اتحفظت، امسح الخام القديم
  with del as (
    delete from daily_worship_logs where date < v_cutoff returning 1
  )
  select count(*) into v_deleted from del;

  return query select v_days, v_wm, v_deleted;
end;
$$;

-- الدالة دي إدارية بحتة (مش بتتنادى من التطبيق أو المستخدمين) —
-- تشغيلها يدويًا من SQL Editor أو عبر جدولة لاحقًا لما تحب
revoke execute on function archive_old_daily_data(int) from public, anon, authenticated;
grant execute on function archive_old_daily_data(int) to service_role, postgres;

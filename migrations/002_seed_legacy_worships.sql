-- ════════════════════════════════════════════════════════════
--  أواب — Migration 002: تحويل العبادات الثابتة (Hardcoded) إلى
--  Records حقيقية لكل مستخدم حالي + ترحيل السجلات التاريخية.
--  آمنة ومتكررة التشغيل (Idempotent) — لو شغّلتها أكتر من مرة
--  مش هتكرر بيانات. شغّلها بعد 001_worship_model.sql مباشرة.
-- ════════════════════════════════════════════════════════════

-- ── الخطوة 1: زرع العبادات اليومية/الأسبوعية الافتراضية لكل مستخدم
--    ما عندوش عبادات لسه (legacy_key هو مفتاح الربط بالتاريخ القديم) ──
do $$
declare
  u record;
  -- (legacy_key, name, category, tracking_type, day_section, recurrence, days_of_week, weekly_target, sort_order, quran_mode)
  defs text[][] := array[
    array['rawatib-fajr','سنة الفجر','prayer','boolean','fajr','daily',null,null,'10',null],
    array['azkar-salah:fajr','أذكار بعد الفجر','prayer','boolean','after_fajr','daily',null,null,'20',null],
    array['azkar-sobh','أذكار الصباح','prayer','boolean','after_fajr','daily',null,null,'30',null],
    array['quran','ورد القرآن','quran','quantity','between_fajr_zuhr','daily',null,null,'40','read'],
    array['doha-pray','ركعتي الضحى','prayer','boolean','between_fajr_zuhr','daily',null,null,'50',null],
    array['rawatib-zuhr-b','سنة الظهر القبلية','prayer','boolean','before_zuhr','daily',null,null,'60',null],
    array['azkar-salah:zuhr','أذكار بعد الظهر','prayer','boolean','after_zuhr','daily',null,null,'70',null],
    array['rawatib-zuhr-a','سنة الظهر البعدية','prayer','boolean','after_zuhr','daily',null,null,'80',null],
    array['azkar-salah:asr','أذكار بعد العصر','prayer','boolean','after_asr','daily',null,null,'90',null],
    array['azkar-masa','أذكار المساء','prayer','boolean','after_asr','daily',null,null,'100',null],
    array['rawatib-mgrb','سنة المغرب','prayer','boolean','after_maghrib','daily',null,null,'110',null],
    array['azkar-salah:mgrb','أذكار بعد المغرب','prayer','boolean','after_maghrib','daily',null,null,'120',null],
    array['rawatib-isha','سنة العشاء','prayer','boolean','after_isha','daily',null,null,'130',null],
    array['azkar-salah:isha','أذكار بعد العشاء','prayer','boolean','after_isha','daily',null,null,'140',null],
    array['witr','ركعة الوتر','prayer','boolean','before_sleep','daily',null,null,'150',null],
    array['azkar-nawm','أذكار النوم','prayer','boolean','before_sleep','daily',null,null,'160',null],
    array['doha-juma','جلسة الضحى (الجمعة)','prayer','boolean','between_fajr_zuhr','specific_days','{5}',null,'170',null],
    array['asr-juma','ساعة إجابة الجمعة','prayer','boolean','asr','specific_days','{5}',null,'180',null],
    array['rahm','صلة الرحم','custom','boolean','weekly_goal','times_per_week',null,'1','190',null],
    array['sadaqa','صدقة','custom','boolean','weekly_goal','times_per_week',null,'1','200',null]
  ];
  d text[];
begin
  for u in select id, pages_goal from users loop
    foreach d slice 1 in array defs loop
      insert into worships (
        user_id, legacy_key, name, category, tracking_type, day_section,
        recurrence_type, days_of_week, weekly_target, sort_order,
        quran_mode, target_value, target_unit
      ) values (
        u.id, d[1], d[2], d[3], d[4], d[5],
        d[6],
        case when d[7] is not null then d[7]::int[] else null end,
        case when d[8] is not null then d[8]::int else null end,
        d[9]::int,
        d[10],
        case when d[1]='quran' then coalesce(u.pages_goal,2)::numeric else null end,
        case when d[1]='quran' then 'صفحات' else null end
      )
      on conflict (user_id, legacy_key) where legacy_key is not null do nothing;
    end loop;
  end loop;
end $$;

-- ── الخطوة 2: ترحيل بيانات daily_records القديمة (JSONB) إلى
--    daily_worship_logs الجديدة، لكل مستخدم وكل تاريخ ──
do $$
declare
  r record;
  uid uuid;
  wid uuid;
  pr_name text;
  pr_val text;
  chk_key text;
  chk_val text;
  az_key text;
  az_val boolean;
  prayer_map jsonb := '{"فجر":"rawatib-fajr","ظهر":"rawatib-zuhr-b","عصر":null,"مغرب":"rawatib-mgrb","عشاء":"rawatib-isha"}';
begin
  for r in select * from daily_records loop
    select id into uid from users where name = r.username limit 1;
    if uid is null then continue; end if;

    -- checks{} -> boolean/quantity worships (yes/no)
    for chk_key, chk_val in select * from jsonb_each_text(coalesce(r.data->'checks','{}'::jsonb)) loop
      select id into wid from worships where user_id=uid and legacy_key=chk_key;
      if wid is not null then
        insert into daily_worship_logs (user_id, worship_id, date, status, completed_at)
        values (uid, wid, r.date::date, case when chk_val='yes' then 'completed' else 'missed' end,
                case when chk_val='yes' then r.updated_at::timestamptz else null end)
        on conflict (user_id, worship_id, date) do nothing;
      end if;
    end loop;

    -- azkarSalah{fajr,zuhr,asr,mgrb,isha: true} -> completed only (false = اتركها Unrecorded)
    for az_key, az_val in select key, value::boolean from jsonb_each_text(coalesce(r.data->'azkarSalah','{}'::jsonb)) as t(key,value) loop
      if az_val then
        select id into wid from worships where user_id=uid and legacy_key='azkar-salah:'||az_key;
        if wid is not null then
          insert into daily_worship_logs (user_id, worship_id, date, status, completed_at)
          values (uid, wid, r.date::date, 'completed', r.updated_at::timestamptz)
          on conflict (user_id, worship_id, date) do nothing;
        end if;
      end if;
    end loop;

    -- quran: 'done' -> completed بكامل الهدف
    if (r.data->>'quran') = 'done' then
      select id, target_value into wid, chk_val from worships where user_id=uid and legacy_key='quran';
      -- (chk_val reused loosely; نعيد الاستعلام بشكل صحيح تحت)
      if wid is not null then
        insert into daily_worship_logs (user_id, worship_id, date, status, value, completed_at)
        select uid, id, r.date::date, 'completed', target_value, r.updated_at::timestamptz
        from worships where id = wid
        on conflict (user_id, worship_id, date) do nothing;
      end if;
    end if;

    -- prayers{name: 'takbir'|'jamaa'|'fardi'} -> نربطها بعبادة "سنة" المرتبطة كتقريب،
    -- ونحفظ نوع الأداء الأصلي كملاحظة حتى لا نفقد التفاصيل التاريخية
    for pr_name, pr_val in select * from jsonb_each_text(coalesce(r.data->'prayers','{}'::jsonb)) loop
      -- نخزّنها في worship مستقل بالاسم "صلاة <الفرض>" لو مش موجودة، وإلا نضيفها كملاحظة على سجل اليوم العام
      insert into worships (user_id, legacy_key, name, category, tracking_type, day_section, recurrence_type, sort_order)
      values (uid, 'prayer-fard:'||pr_name, 'صلاة '||pr_name, 'prayer', 'boolean',
              case pr_name when 'فجر' then 'fajr' when 'ظهر' then 'zuhr' when 'عصر' then 'asr'
                            when 'مغرب' then 'maghrib' when 'عشاء' then 'isha' else 'anytime' end,
              'daily', 5)
      on conflict (user_id, legacy_key) where legacy_key is not null do nothing;

      select id into wid from worships where user_id=uid and legacy_key='prayer-fard:'||pr_name;
      if wid is not null then
        insert into daily_worship_logs (user_id, worship_id, date, status, notes, completed_at)
        values (uid, wid, r.date::date, 'completed', 'نوع الأداء (بيانات قديمة): '||pr_val, r.updated_at::timestamptz)
        on conflict (user_id, worship_id, date) do nothing;
      end if;
    end loop;

  end loop;
end $$;

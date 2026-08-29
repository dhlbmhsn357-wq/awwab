-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 021: ثوابت اليوم (Worship Pins)
--  آمنة تمامًا: جدول جديد فقط، مايلمسش أي جدول/عمود/بيانات موجودة.
--  Backward-compatible: الكود القديم مايعرفش الجدول ده أصلاً فمايتأثرش.
--  شغّلها مرة واحدة من Supabase Dashboard → SQL Editor → Run.
-- ════════════════════════════════════════════════════════════

-- عبادة "مثبّتة" تظهر في مساحة "ثوابت اليوم" أعلى عبادات اليوم.
-- scope='always' → تظهر كل يوم تكون فيه العبادة مجدولة (pin_date = NULL).
-- scope='today'  → تظهر في يوم واحد بعينه فقط (pin_date = ذلك اليوم).
-- إلغاء التثبيت = Soft delete (deleted_at) — نفس نمط حذف العبادات
-- (tombstone) عشان يتزامن صح بين الأجهزة عبر نفس مسار الـupsert
-- الموجود، بدل ما نحتاج مسار DELETE جديد في الـSync Queue.
create table if not exists worship_pins (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  worship_id  uuid not null references worships(id) on delete cascade,
  scope       text not null default 'always' check (scope in ('always','today')),
  pin_date    date,                              -- NULL لـ always، تاريخ محدد لـ today
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists idx_worship_pins_user on worship_pins(user_id);
create index if not exists idx_worship_pins_worship on worship_pins(worship_id);

-- منع التكرار: ثابت دائم واحد لكل عبادة، وثابت "اليوم فقط" واحد لكل
-- (عبادة + تاريخ). نتجاهل الصفوف المحذوفة (deleted_at is not null)
-- عشان لو المستخدم ثبّت ثم ألغى ثم ثبّت تاني مايحصلش تعارض.
create unique index if not exists uq_worship_pins_always
  on worship_pins(user_id, worship_id)
  where scope = 'always' and deleted_at is null;
create unique index if not exists uq_worship_pins_today
  on worship_pins(user_id, worship_id, pin_date)
  where scope = 'today' and deleted_at is null;

-- ── RLS: صاحب الصف بس (نفس نمط كل جداول بيانات المستخدم) ──
alter table worship_pins enable row level security;

create policy "worship_pins_select_own" on worship_pins
  for select using (user_id = auth.uid());
create policy "worship_pins_insert_own" on worship_pins
  for insert with check (user_id = auth.uid());
create policy "worship_pins_update_own" on worship_pins
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "worship_pins_delete_own" on worship_pins
  for delete using (user_id = auth.uid());

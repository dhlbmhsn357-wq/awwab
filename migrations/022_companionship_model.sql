-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 022: صحبتي (Companionship) — النموذج + RLS
--  آمنة: جداول جديدة فقط، مايلمسش أي جدول/عمود/بيانات موجودة.
--  الكتابة على companionships مقفولة تمامًا من العميل — كل تعديل
--  بيمرّ عبر RPCs مؤمّنة (migration 023) بتتحقق من الصلاحيات في
--  السيرفر. RLS هنا بتسمح بالقراءة للطرفين المعنيين بس.
-- ════════════════════════════════════════════════════════════

-- ── العلاقات ──
create table if not exists companionships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references profiles(id) on delete cascade,
  recipient_id  uuid not null references profiles(id) on delete cascade,
  status        text not null default 'pending'
                check (status in ('pending','accepted','declined','cancelled','blocked','removed')),
  invite_message text,
  blocked_by    uuid references profiles(id) on delete set null,
  created_at    timestamptz not null default now(),
  accepted_at   timestamptz,
  updated_at    timestamptz not null default now(),
  check (requester_id <> recipient_id)
);

create index if not exists idx_comp_requester on companionships(requester_id);
create index if not exists idx_comp_recipient on companionships(recipient_id);

-- منع تكرار علاقة بين نفس الشخصين (بأي اتجاه) طالما فيها علاقة نشطة
-- أو محظورة. الصفوف declined/cancelled/removed مبتمنعش طلب جديد لاحقًا.
create unique index if not exists uq_comp_pair
  on companionships (least(requester_id, recipient_id), greatest(requester_id, recipient_id))
  where status in ('pending','accepted','blocked');

-- ── تفضيلات المشاركة داخل صحبتي (منفصلة تمامًا عن رفقة أوّاب) ──
-- الافتراضي: الأكثر خصوصية (كله false / فاضي).
create table if not exists companion_settings (
  user_id           uuid primary key references profiles(id) on delete cascade,
  share_today_pct   boolean not null default false,   -- أشارك نسبة اليوم
  share_weekly      boolean not null default false,   -- أشارك الملخص الأسبوعي
  encourage_worship_ids uuid[] not null default '{}', -- "أحتاج تشجيعًا في" (أسماؤها تظهر لصحبتي)
  whatsapp          text,                              -- اختياري، مايتعرضش مباشرة في الواجهة
  needs_checkin_at   timestamptz,          -- "أحتاج تفقدًا" — حالة مؤقتة تظهر لكل صحبتي
  needs_checkin_note text,
  updated_at        timestamptz not null default now()
);

-- ── RLS: companionships — قراءة للطرفين بس، والكتابة مقفولة (RPCs بس) ──
alter table companionships enable row level security;

create policy "comp_select_involved" on companionships
  for select using (requester_id = auth.uid() or recipient_id = auth.uid());
-- ملاحظة: مفيش policies للـinsert/update/delete عمدًا — يعني العميل
-- مايقدرش يكتب مباشرة خالص. كل التعديلات عبر SECURITY DEFINER RPCs
-- (migration 023) اللي بتفرض قواعد الحالة بنفسها.

-- ── RLS: companion_settings — صاحب الصف بس (زي fellowship_settings) ──
-- القراءة مقصورة على صاحبها؛ عرضها لصحبتي بيحصل فقط عبر
-- get_my_companions() (SECURITY DEFINER) اللي بتراعي التفضيلات بنفسها.
alter table companion_settings enable row level security;

create policy "cs_select_own" on companion_settings
  for select using (user_id = auth.uid());
create policy "cs_insert_own" on companion_settings
  for insert with check (user_id = auth.uid());
create policy "cs_update_own" on companion_settings
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "cs_delete_own" on companion_settings
  for delete using (user_id = auth.uid());

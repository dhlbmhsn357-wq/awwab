-- ════════════════════════════════════════════════════════════
--  أواب — Migration 008: تفعيل Row Level Security (P0، جزء 2)
--  لازم تتشغّل بعد 007 وبعد نشر كود الواجهة الجديد اللي بيبعت
--  Authorization: Bearer <access_token الخاص بالمستخدم> بدل الـanon
--  key الثابت — وإلا كل الاستعلامات هترفض فورًا (auth.uid() = null).
--
--  كل سياسة هنا بمبدأ واحد: المستخدم يشوف/يعدّل صفوفه هو بس
--  (user_id = auth.uid())، والحماية دي في قاعدة البيانات نفسها،
--  مش شرط في كود الواجهة.
-- ════════════════════════════════════════════════════════════

-- ── profiles ──
alter table profiles enable row level security;

create policy "profiles_select_own_or_admin" on profiles
  for select using (id = auth.uid() or is_admin());

create policy "profiles_insert_own" on profiles
  for insert with check (id = auth.uid());

create policy "profiles_update_own_or_admin" on profiles
  for update using (id = auth.uid() or is_admin())
  with check (id = auth.uid() or is_admin());

create policy "profiles_delete_own_or_admin" on profiles
  for delete using (id = auth.uid() or is_admin());

-- ── worships ──
alter table worships enable row level security;

create policy "worships_select_own" on worships
  for select using (user_id = auth.uid());
create policy "worships_insert_own" on worships
  for insert with check (user_id = auth.uid());
create policy "worships_update_own" on worships
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "worships_delete_own" on worships
  for delete using (user_id = auth.uid());

-- ── daily_worship_logs ──
alter table daily_worship_logs enable row level security;

create policy "logs_select_own" on daily_worship_logs
  for select using (user_id = auth.uid());
create policy "logs_insert_own" on daily_worship_logs
  for insert with check (user_id = auth.uid());
create policy "logs_update_own" on daily_worship_logs
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "logs_delete_own" on daily_worship_logs
  for delete using (user_id = auth.uid());

-- ── daily_notes ──
alter table daily_notes enable row level security;

create policy "notes_select_own" on daily_notes
  for select using (user_id = auth.uid());
create policy "notes_insert_own" on daily_notes
  for insert with check (user_id = auth.uid());
create policy "notes_update_own" on daily_notes
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "notes_delete_own" on daily_notes
  for delete using (user_id = auth.uid());

-- ── fellowship_settings ──
-- ملحوظة: القراءة هنا مقصورة على صاحب الصف بس. عرض إعدادات باقي
-- الأعضاء في "رفقة أواب" بيحصل فقط عبر get_fellowship_feed()
-- (SECURITY DEFINER) اللي بتراعي share_level بنفسها، مش عبر SELECT
-- مباشر على الجدول ده.
alter table fellowship_settings enable row level security;

create policy "fsettings_select_own" on fellowship_settings
  for select using (user_id = auth.uid());
create policy "fsettings_insert_own" on fellowship_settings
  for insert with check (user_id = auth.uid());
create policy "fsettings_update_own" on fellowship_settings
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "fsettings_delete_own" on fellowship_settings
  for delete using (user_id = auth.uid());

-- ── encouragements ──
-- المُرسِل يقدر يبعت وياخد بالّ إنه بعت، والمُستقبِل يقدر يشوف اللي
-- اتبعتله. محدش يقدر يقرا تشجيع بين شخصين تانيين.
alter table encouragements enable row level security;

create policy "enc_select_involved" on encouragements
  for select using (to_user_id = auth.uid() or from_user_id = auth.uid());
create policy "enc_insert_own" on encouragements
  for insert with check (from_user_id = auth.uid());

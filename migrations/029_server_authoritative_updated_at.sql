-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 029: updated_at موثوق من السيرفر (Sync root cause)
--
--  المشكلة الجذرية للمزامنة: مؤشّر السحب (last_sync) بيقارن بـ
--  updated_at، لكن updated_at كان بيتكتب من ساعة الجهاز الكاتب
--  (العميل بيبعته في الـpayload). فأي اختلاف بين ساعة الجهاز وساعة
--  السيرفر (أو بين جهازين) بيخلّي ترتيب updated_at غير موثوق،
--  فتُفوَّت تغييرات (Android مايلتقطش تغييرات Web).
--
--  الإصلاح الجذري: نخلّي updated_at يُضبط من السيرفر (now()) في كل
--  INSERT/UPDATE عبر trigger — فيبقى وقت سيرفر أحادي المصدر، والمؤشّر
--  يشتغل بدقة مهما كانت ساعة أي جهاز.
--
--  غير هدّامة: triggers + دالة فقط. لا تغيير بيانات، لا drop، لا
--  تعديل schema. متوافقة رجوعيًا: العميل يقدر يفضل يبعت updated_at
--  (هيتجاهله السيرفر ويحط now())، والـpull بيصلّح النسخة المحلية.
-- ════════════════════════════════════════════════════════════

create or replace function awwab_set_synced_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end; $$;

-- worships
drop trigger if exists trg_worships_updated_at on worships;
create trigger trg_worships_updated_at
  before insert or update on worships for each row execute function awwab_set_synced_updated_at();

-- daily_worship_logs
drop trigger if exists trg_dwl_updated_at on daily_worship_logs;
create trigger trg_dwl_updated_at
  before insert or update on daily_worship_logs for each row execute function awwab_set_synced_updated_at();

-- daily_notes
drop trigger if exists trg_dn_updated_at on daily_notes;
create trigger trg_dn_updated_at
  before insert or update on daily_notes for each row execute function awwab_set_synced_updated_at();

-- worship_pins (لو الجدول موجود — migration 021)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='worship_pins') then
    drop trigger if exists trg_wp_updated_at on worship_pins;
    create trigger trg_wp_updated_at
      before insert or update on worship_pins for each row execute function awwab_set_synced_updated_at();
  end if;
end $$;

-- fellowship_settings + companion_settings (مزامنة إعدادات المشاركة)
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='fellowship_settings') then
    drop trigger if exists trg_fs_updated_at on fellowship_settings;
    create trigger trg_fs_updated_at
      before insert or update on fellowship_settings for each row execute function awwab_set_synced_updated_at();
  end if;
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='companion_settings') then
    drop trigger if exists trg_cs_updated_at on companion_settings;
    create trigger trg_cs_updated_at
      before insert or update on companion_settings for each row execute function awwab_set_synced_updated_at();
  end if;
end $$;

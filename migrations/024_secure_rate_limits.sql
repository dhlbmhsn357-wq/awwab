-- ════════════════════════════════════════════════════════════
--  أوّاب — Migration 024: إغلاق ثغرة rate_limits (Security P1)
--
--  المشكلة: جدول rate_limits (من migration 016a) اتعمل بدون
--  enable row level security. في Supabase، أي جدول في schema
--  public من غير RLS بيكون مكشوف تلقائيًا لدور anon (المفتاح العام
--  الموجود في الواجهة) — يعني أي حد يقدر يقرا/يعدّل/يمسح صفوف الجدول
--  مباشرة، ويتخطّى دالة check_rate_limit، فيعطّل الـrate limiting
--  بتاع auth-helper أو يقرا مفاتيح تتضمّن IPs. اتأكد حيًّا: طلب anon
--  على /rest/v1/rate_limits رجع HTTP 200 (مسموح).
--
--  الإصلاح آمن 100% وغير هدّام: الواجهة والـEdge Functions مابيلمسوش
--  الجدول مباشرة أبدًا — بس دالة check_rate_limit (SECURITY DEFINER،
--  مقصورة على service_role) بتتعامل معاه، والـSECURITY DEFINER بيتخطّى
--  RLS، فتفعيل RLS + سحب صلاحيات الأدوار العميلة مايكسرش أي حاجة.
-- ════════════════════════════════════════════════════════════

alter table rate_limits enable row level security;

-- عمدًا مفيش أي policies — يعني مفيش وصول عميل خالص. الوصول الوحيد
-- عبر check_rate_limit() اللي بتشتغل كصاحب الدالة (يتخطّى RLS).

-- دفاع في العمق: اسحب أي صلاحيات جدول مباشرة من أدوار العميل.
revoke all on table rate_limits from anon, authenticated;

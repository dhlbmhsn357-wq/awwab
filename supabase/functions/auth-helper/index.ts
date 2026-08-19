// ════════════════════════════════════════════════════════════
//  أواب — auth-helper Edge Function
//  بديل استدعاء get_login_email/is_name_taken مباشرة من المتصفح —
//  دلوقتي معديين من هنا بس، وهنا بنفرض حد أقصى للمحاولات لكل IP
//  (20 محاولة كل 5 دقايق لكل نوع عملية) قبل ما نلمس قاعدة البيانات.
//  SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY
//  متاحين تلقائيًا كـ env vars لأي Edge Function من غير إعداد يدوي.
// ════════════════════════════════════════════════════════════
import { createClient } from 'jsr:@supabase/supabase-js@2';

const SB_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const { action, name } = await req.json();
    if (!name || typeof name !== 'string' || name.length > 100) {
      return new Response(JSON.stringify({ error: 'بيانات غير صالحة' }), {
        status: 400, headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }
    if (action !== 'login_email' && action !== 'name_taken') {
      return new Response(JSON.stringify({ error: 'invalid action' }), {
        status: 400, headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
    const admin = createClient(SB_URL, SERVICE_KEY);

    const { data: allowed, error: rlErr } = await admin.rpc('check_rate_limit', {
      p_key: `${ip}:${action}`, p_max: 20, p_window_seconds: 300,
    });
    if (rlErr) throw rlErr;
    if (!allowed) {
      return new Response(JSON.stringify({ error: 'محاولات كتير، حاول تاني بعد شوية' }), {
        status: 429, headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    if (action === 'login_email') {
      const { data, error } = await admin.rpc('get_login_email', { p_name: name });
      if (error) throw error;
      return new Response(JSON.stringify({ email: data }), {
        headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const { data, error } = await admin.rpc('is_name_taken', { p_name: name });
    if (error) throw error;
    return new Response(JSON.stringify({ taken: data }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('auth-helper error:', e);
    return new Response(JSON.stringify({ error: 'خطأ في الخادم' }), {
      status: 500, headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});

// ════════════════════════════════════════════════════════════
//  أواب — admin-delete-member Edge Function
//  الحل الحقيقي لحذف عضو بالكامل (حساب Auth كامل، مش صف profiles
//  بس) — العملية دي محتاجة service_role، ومينفعش نحطه في المتصفح
//  أبدًا. الدالة دي بتتحقق إن اللي طالب الحذف admin فعلًا (عبر
//  التوكن بتاعه هو، وRLS بتفرض إنه يشوف صفه بس) قبل ما تستخدم
//  service_role. حذف حساب Auth بيسحب معاه كل بياناته تلقائيًا
//  (profiles → worships → logs → ... كلهم ON DELETE CASCADE).
// ════════════════════════════════════════════════════════════
import { createClient } from 'jsr:@supabase/supabase-js@2';

const SB_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), {
        status: 401, headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    // عميل بتوكن المستخدم الطالب نفسه — RLS شغّالة عادي، هيشوف صفه هو بس
    const asUser = createClient(SB_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await asUser.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), {
        status: 401, headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const { data: myProfile } = await asUser.from('profiles').select('role').eq('id', user.id).single();
    if (myProfile?.role !== 'admin') {
      return new Response(JSON.stringify({ error: 'forbidden' }), {
        status: 403, headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const { target_id } = await req.json();
    if (!target_id || typeof target_id !== 'string' || target_id === user.id) {
      return new Response(JSON.stringify({ error: 'invalid target' }), {
        status: 400, headers: { ...cors, 'Content-Type': 'application/json' },
      });
    }

    const admin = createClient(SB_URL, SERVICE_KEY);
    const { error } = await admin.auth.admin.deleteUser(target_id);
    if (error) throw error;

    return new Response(JSON.stringify({ ok: true }), {
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error('admin-delete-member error:', e);
    return new Response(JSON.stringify({ error: 'خطأ في الخادم' }), {
      status: 500, headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});

// ════════════════════════════════════════════════════════════
//  أوّاب — اختبارات RLS/RPC هجومية لصحبتي (Companionship)
//
//  لازم يتشغّل *بعد* تطبيق migrations 022 + 023 على Supabase.
//  بيعمل 3 حسابات Auth مؤقتة (A,B,C)، بيجرّب هجمات، وبيمسحهم في الآخر.
//
//  التشغيل:
//    SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE=... \
//      node scripts/test-companionship-rls.mjs
//
//  (الـservice_role سرّي — من env بس، مش متسجّل في Git.)
// ════════════════════════════════════════════════════════════
const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SR = process.env.SUPABASE_SERVICE_ROLE;
if(!URL || !ANON || !SR){ console.error('محتاج SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE'); process.exit(1); }

let pass=0, fail=0;
function ok(name, cond){ (cond?pass++:fail++); console.log((cond?'✓':'✗')+' '+name); }

async function adminCreateUser(email, password){
  const r = await fetch(`${URL}/auth/v1/admin/users`, { method:'POST',
    headers:{ apikey:SR, Authorization:'Bearer '+SR, 'Content-Type':'application/json' },
    body: JSON.stringify({ email, password, email_confirm:true }) });
  const j = await r.json(); if(!r.ok) throw new Error(JSON.stringify(j)); return j.id;
}
async function adminDeleteUser(id){ await fetch(`${URL}/auth/v1/admin/users/${id}`, { method:'DELETE', headers:{ apikey:SR, Authorization:'Bearer '+SR } }).catch(()=>{}); }
async function signIn(email, password){
  const r = await fetch(`${URL}/auth/v1/token?grant_type=password`, { method:'POST',
    headers:{ apikey:ANON, 'Content-Type':'application/json' }, body: JSON.stringify({ email, password }) });
  const j = await r.json(); if(!r.ok) throw new Error(JSON.stringify(j)); return j.access_token;
}
// profiles صف مطلوب لكل مستخدم (FK)، ننشئه بالـservice_role
async function ensureProfile(id, name){
  await fetch(`${URL}/rest/v1/profiles`, { method:'POST',
    headers:{ apikey:SR, Authorization:'Bearer '+SR, 'Content-Type':'application/json', Prefer:'resolution=merge-duplicates' },
    body: JSON.stringify({ id, display_name:name }) });
}
function asUser(token){
  return {
    rpc: async (fn, args)=>{
      const r = await fetch(`${URL}/rest/v1/rpc/${fn}`, { method:'POST',
        headers:{ apikey:ANON, Authorization:'Bearer '+token, 'Content-Type':'application/json' }, body: JSON.stringify(args||{}) });
      const t = await r.text(); let j=null; try{ j=t?JSON.parse(t):null; }catch(e){ j=t; }
      return { ok:r.ok, status:r.status, data:j };
    },
    get: async (path)=>{
      const r = await fetch(`${URL}/rest/v1/${path}`, { headers:{ apikey:ANON, Authorization:'Bearer '+token } });
      return { ok:r.ok, status:r.status, data: await r.json() };
    },
  };
}

const rand = Math.floor(Math.random()*1e6);
const users = [];
async function mk(letter){
  const email = `rlstest_${rand}_${letter}@awwab.local`; const pw = 'Test!'+rand+letter;
  const id = await adminCreateUser(email, pw); await ensureProfile(id, 'RLS '+letter);
  const token = await signIn(email, pw); users.push({letter,id,email,token,api:asUser(token)});
  return users[users.length-1];
}

try {
  const A = await mk('A'), B = await mk('B'), C = await mk('C');

  // 1) A يبعت طلب لـB
  let r = await A.api.rpc('send_companion_request', { p_target:B.id, p_message:'صحبة؟' });
  ok('A يقدر يبعت طلب لـB', r.ok);
  const reqId = r.data; // uuid

  // 2) C مايشوفش علاقة A-B (RLS SELECT للطرفين بس)
  r = await C.api.get(`companionships?select=id`);
  ok('C مايشوفش علاقة A-B', r.ok && Array.isArray(r.data) && r.data.length===0);

  // 3) C مايقدرش يقبل طلب مش موجّه له
  r = await C.api.rpc('respond_companion_request', { p_id:reqId, p_accept:true });
  ok('C مايقدرش يقبل طلب A→B', !r.ok || r.status>=400);

  // 4) pending مايفتحش summary — get_my_companions لـA لسه فاضية
  r = await A.api.rpc('get_my_companions', {});
  ok('pending: get_my_companions لـA فاضية', r.ok && Array.isArray(r.data) && r.data.length===0);

  // 5) A (المُرسِل) مايقدرش يقبل طلبه هو
  r = await A.api.rpc('respond_companion_request', { p_id:reqId, p_accept:true });
  ok('A مايقدرش يقبل طلبه بنفسه', !r.ok || r.status>=400);

  // 6) B يقبل
  r = await B.api.rpc('respond_companion_request', { p_id:reqId, p_accept:true });
  ok('B يقدر يقبل الطلب', r.ok);

  // 7) بعد القبول: A تشوف B في صحبتها، وبالعكس
  r = await A.api.rpc('get_my_companions', {});
  ok('accepted: A تشوف B', r.ok && r.data.some(x=>x.user_id===B.id));

  // 8) C لسه مايشوفش لا A ولا B
  r = await C.api.rpc('get_my_companions', {});
  ok('C مايشوفش A/B في صحبته', r.ok && !r.data.some(x=>x.user_id===A.id||x.user_id===B.id));

  // 9) A مايقدرش يقرا companion_settings بتاعة B مباشرة
  r = await A.api.get(`companion_settings?user_id=eq.${B.id}&select=*`);
  ok('A مايقرأش companion_settings بتاعة B', r.ok && Array.isArray(r.data) && r.data.length===0);

  // 10) A مايقدرش يكتب على companionships مباشرة (مفيش write policy)
  r = await A.api.rpc('noop_skip', {}).catch(()=>({ok:false}));
  const wr = await fetch(`${URL}/rest/v1/companionships`, { method:'PATCH',
    headers:{ apikey:ANON, Authorization:'Bearer '+A.token, 'Content-Type':'application/json' },
    body: JSON.stringify({ status:'accepted' }) });
  ok('A مايقدرش يعدّل companionships مباشرة (RLS)', wr.status===403 || wr.status===401 || (wr.ok && (await wr.json()).length===0));

  // 11) إزالة: A تزيل B → C فحص إن الوصول اتقفل
  r = await A.api.rpc('remove_companion', { p_id:reqId });
  ok('A تقدر تزيل الصحبة', r.ok);
  r = await A.api.rpc('get_my_companions', {});
  ok('بعد الإزالة: A مبقتش تشوف B', r.ok && !r.data.some(x=>x.user_id===B.id));

  console.log(`\nنتيجة: ${pass} نجحت، ${fail} فشلت`);
} catch(e){
  console.error('خطأ في التشغيل:', e.message);
} finally {
  for(const u of users) await adminDeleteUser(u.id);
  console.log('اتمسحت الحسابات المؤقتة.');
  process.exit(fail>0?1:0);
}

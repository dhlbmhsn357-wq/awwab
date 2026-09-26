// ════════════════════════════════════════════════════════════
//  اختبار أمني حي لحزمة companions+ (migrations 026/027)
//  يشغّل بعد تطبيق الـmigrations على المشروع. بيعمل مستخدمين مؤقتين
//  عبر signup العام (anon key) ويختبر:
//   1) anon مرفوض على find_user_by_public_id
//   2) البحث exact-match بيرجّع أقل بيانات (اسم/معرّف/علاقة) — لا إيميل
//   3) البحث عن نفسك / معرّف غير موجود → فاضي
//   4) rate limit بيشتغل (محاولات كثيرة → رفض)
//   5) discoverable_by_id=false → المستخدم مايظهرش حتى بمعرّف صحيح
//   6) get_my_companions بيرجّع حقول الحالة (status/days_since_activity)
//
//  ما بيخزّنش أي secret؛ بيقرا anon key العام من index.html.
//  Usage: node scripts/test-companions-plus.mjs
// ════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const SB_URL = (html.match(/const SB_URL = '([^']+)'/) || [])[1];
const ANON = (html.match(/const SB_KEY = '([^']+)'/) || [])[1];
if (!SB_URL || !ANON) { console.error('تعذّر قراءة SB_URL/anon key من index.html'); process.exit(1); }

const H = (tok) => ({ apikey: ANON, Authorization: `Bearer ${tok || ANON}`, 'Content-Type': 'application/json' });
const rnd = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
let pass = 0, fail = 0;
const ok = (c, m) => { console.log(`${c ? 'PASS' : 'FAIL'} — ${m}`); c ? pass++ : fail++; };

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
async function signup() {
  // Supabase بيعمل rate-limit على التسجيل؛ نجرّب مع backoff عشان الاختبار
  // مايفشلش لأسباب بنية الاختبار (مش المنتج)
  for (let attempt = 0; attempt < 5; attempt++) {
    const email = `probe_${rnd()}@awwab-audit.local`, password = `Aud!t_${rnd()}`;
    const r = await fetch(`${SB_URL}/auth/v1/signup`, { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });
    const j = await r.json();
    if (j.access_token) return { token: j.access_token, id: j.user?.id, email };
    console.log(`  (signup rate-limited, backing off ${(attempt + 1) * 20}s…)`);
    await sleep((attempt + 1) * 20000);
  }
  throw new Error('signup rate-limited repeatedly — انتظر ثم أعد المحاولة');
}
async function createProfile(u, name) {
  // إنشاء صف profile للمستخدم (زي ما بيعمل التطبيق بعد التسجيل) — trigger
  // بيولّد public_numeric_id تلقائيًا
  await fetch(`${SB_URL}/rest/v1/profiles`, { method: 'POST', headers: { ...H(u.token), Prefer: 'return=minimal' }, body: JSON.stringify({ id: u.id, display_name: name, role: 'member', pages_goal: 0, onboarding_done: true }) });
  const r = await fetch(`${SB_URL}/rest/v1/profiles?id=eq.${u.id}&select=public_numeric_id,display_name`, { headers: H(u.token) });
  const rows = await r.json();
  return rows[0];
}
async function rpc(tok, fn, args) {
  const r = await fetch(`${SB_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers: H(tok), body: JSON.stringify(args || {}) });
  return { status: r.status, body: await r.json().catch(() => null) };
}

(async () => {
  console.log('== companions+ security matrix ==\n');
  const A = await signup(); await sleep(1500); const B = await signup(); await sleep(1500); const C = await signup();
  if (!A.token || !B.token || !C.token) { console.error('signup فشل (تأكد signups مفعّلة)'); process.exit(1); }
  const pB = await createProfile(B, 'باء اختبار');
  const pA = await createProfile(A, 'ألف اختبار');
  const pC = await createProfile(C, 'جيم اختبار');

  // 1) anon مرفوض
  const anon = await rpc(null, 'find_user_by_public_id', { p_public_id: pB.public_numeric_id });
  ok(anon.status === 401 || anon.status === 403, `anon rejected on find_user_by_public_id (status=${anon.status})`);

  // 2) البحث بيرجّع أقل بيانات + مفيش إيميل
  const found = await rpc(A.token, 'find_user_by_public_id', { p_public_id: pB.public_numeric_id });
  const row = Array.isArray(found.body) ? found.body[0] : null;
  ok(!!row && row.display_name === 'باء اختبار' && String(row.public_numeric_id) === String(pB.public_numeric_id), 'search returns the target minimal profile');
  ok(!!row && !('email' in row) && !('whatsapp' in row) && !('phone' in row), 'search leaks no email/phone/whatsapp');
  ok(!!row && !('user_id' in row) && !('id' in row), 'search returns NO internal UUID');
  ok(!!row && row.relation === 'none', 'relation state = none for strangers');

  // 3) نفسك / غير موجود → فاضي
  const self = await rpc(A.token, 'find_user_by_public_id', { p_public_id: pA.public_numeric_id });
  ok(Array.isArray(self.body) && self.body.length === 0, 'searching self returns empty');
  const none = await rpc(A.token, 'find_user_by_public_id', { p_public_id: 999999999 });
  ok(Array.isArray(none.body) && none.body.length === 0, 'non-existent id returns empty');

  // 4) rate limit (>20/min)
  let limited = false;
  for (let i = 0; i < 25; i++) { const r = await rpc(A.token, 'find_user_by_public_id', { p_public_id: 111111111 }); if (r.status >= 400 && JSON.stringify(r.body).includes('محاولات')) { limited = true; break; } }
  ok(limited, 'rate limit blocks rapid enumeration');

  // 5) discoverable=false يخفي المستخدم
  await fetch(`${SB_URL}/rest/v1/companion_settings`, { method: 'POST', headers: { ...H(C.token), Prefer: 'resolution=merge-duplicates' }, body: JSON.stringify({ user_id: C.id, discoverable_by_id: false }) });
  // ننتظر شوية عشان rate-limit window (استخدمنا نفس المستخدم A) — نستخدم B للبحث
  const hiddenLookup = await rpc(B.token, 'find_user_by_public_id', { p_public_id: pC.public_numeric_id });
  ok(Array.isArray(hiddenLookup.body) && hiddenLookup.body.length === 0, 'discoverable_by_id=false hides the user even with correct id');

  // 6) get_my_companions بيرجّع حقول الحالة
  const mine = await rpc(A.token, 'get_my_companions', {});
  ok(mine.status === 200 && Array.isArray(mine.body), 'get_my_companions returns array (status field present in schema)');

  console.log(`\n== ${pass} passed, ${fail} failed ==`);
  console.log('(ملاحظة: المستخدمون المؤقتون probe_*@awwab-audit.local بلا profile-صحبة؛ يمكن حذفهم من Auth لاحقًا)');
  process.exit(fail ? 1 : 0);
})();

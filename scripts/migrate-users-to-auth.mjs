#!/usr/bin/env node
// ════════════════════════════════════════════════════════════
//  أواب — سكريبت ترحيل لمرة واحدة: users (اسم+كلمة مرور نص صريح)
//  → Supabase Auth حقيقي + profiles.
//
//  الاستخدام:
//    SUPABASE_SERVICE_ROLE_KEY=xxx node scripts/migrate-users-to-auth.mjs
//
//  المفتاح بيتقرا من environment variable بس — ممنوع نهائيًا يتحط
//  في أي ملف أو يتسجل في Git. السكريبت ده مش جزء من التطبيق
//  المنشور، بيتشغّل مرة واحدة يدويًا من جهازك.
//
//  آمن لإعادة التشغيل: أي مستخدم اتم ترحيله بالفعل (له profile
//  بنفس الاسم) بيتم تجاوزه، فمينفعش تتكرر بياناته لو السكريبت
//  فشل في النص وشغّلته تاني.
// ════════════════════════════════════════════════════════════

const SB_URL = 'https://uzzrkqkudyroswvekeoz.supabase.co';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SERVICE_KEY) {
  console.error('✗ محتاج SUPABASE_SERVICE_ROLE_KEY كـ environment variable. راجع migrations/007 و008 وشغّلهم الأول لو لسه ما عملتش.');
  process.exit(1);
}

const headers = {
  apikey: SERVICE_KEY,
  Authorization: 'Bearer ' + SERVICE_KEY,
  'Content-Type': 'application/json',
};

async function rest(method, path, body, extraHeaders = {}) {
  const r = await fetch(SB_URL + '/rest/v1/' + path, {
    method,
    headers: { ...headers, ...extraHeaders },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path} -> ${r.status}: ${text}`);
  return text ? JSON.parse(text) : null;
}

async function adminCreateAuthUser(email, password, displayName) {
  const r = await fetch(SB_URL + '/auth/v1/admin/users', {
    method: 'POST',
    headers,
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { display_name: displayName },
    }),
  });
  const body = await r.json();
  if (!r.ok) throw new Error(`admin/users -> ${r.status}: ${JSON.stringify(body)}`);
  return body.id || body.user?.id;
}

async function main() {
  console.log('▸ جاري جلب المستخدمين القدامى...');
  const oldUsers = await rest('GET', 'users?select=*&order=created_at.asc');
  console.log(`▸ لقيت ${oldUsers.length} مستخدم`);

  const results = { migrated: [], skipped: [], failed: [] };

  for (const u of oldUsers) {
    try {
      // إعادة تشغيل آمنة: لو الحساب (auth+profile) اتعمل قبل كده،
      // استخدم نفس الـid الجديد وكمّل خطوة إعادة توجيه البيانات —
      // مينفعش نتجاوز المستخدم بالكامل، لأن آخر مرة ممكن يكون
      // الحساب اتعمل لكن البيانات (worships...) فشلت في نقلها
      const existing = await rest('GET', `profiles?select=id&display_name=eq.${encodeURIComponent(u.name)}`);
      let newId;
      if (existing.length) {
        newId = existing[0].id;
        console.log(`  ↻  ${u.name} — الحساب موجود بالفعل (${newId})، هكمّل نقل بياناته`);
      } else {
        const syntheticEmail = crypto.randomUUID() + '@awwab.local';
        newId = await adminCreateAuthUser(syntheticEmail, u.pass, u.name);
        await rest('POST', 'profiles', {
          id: newId,
          display_name: u.name,
          role: u.role || 'member',
          pages_goal: u.pages_goal ?? 0,
          onboarding_done: !!u.onboarding_done,
          onboarding_type: u.onboarding_type ?? null,
          onboarding_tour_status: u.onboarding_tour_status ?? null,
          onboarding_tour_step: u.onboarding_tour_step ?? 0,
          onboarding_tour_completed_at: u.onboarding_tour_completed_at ?? null,
          created_at: u.created_at,
        }, { Prefer: 'return=minimal' });
      }

      // إعادة توجيه كل الجداول المرتبطة للـid الجديد — آمنة تتكرر:
      // لو مفيش صفوف بالـid القديم (اتنقلت قبل كده) بترجع 0 صفوف
      // من غير أي خطأ
      await rest('PATCH', `worships?user_id=eq.${u.id}`, { user_id: newId }, { Prefer: 'return=minimal' });
      await rest('PATCH', `daily_worship_logs?user_id=eq.${u.id}`, { user_id: newId }, { Prefer: 'return=minimal' });
      await rest('PATCH', `daily_notes?user_id=eq.${u.id}`, { user_id: newId }, { Prefer: 'return=minimal' });
      await rest('PATCH', `fellowship_settings?user_id=eq.${u.id}`, { user_id: newId }, { Prefer: 'return=minimal' });
      await rest('PATCH', `encouragements?to_user_id=eq.${u.id}`, { to_user_id: newId }, { Prefer: 'return=minimal' });
      await rest('PATCH', `encouragements?from_user_id=eq.${u.id}`, { from_user_id: newId }, { Prefer: 'return=minimal' });

      results.migrated.push({ name: u.name, oldId: u.id, newId });
      console.log(`  ✓  ${u.name} → ${newId}`);
    } catch (e) {
      results.failed.push({ name: u.name, error: e.message });
      console.log(`  ✗  ${u.name} — فشل: ${e.message}`);
    }
  }

  console.log('\n════════════════════════════════');
  console.log(`تم الترحيل: ${results.migrated.length}`);
  console.log(`متجاوَز (متم قبل كده): ${results.skipped.length}`);
  console.log(`فشل: ${results.failed.length}`);
  if (results.failed.length) {
    console.log('\nالفاشلين (راجعهم وشغّل السكريبت تاني، آمن لإعادة التشغيل):');
    results.failed.forEach(f => console.log(`  - ${f.name}: ${f.error}`));
  }
  console.log('════════════════════════════════');
}

main().catch(e => { console.error('خطأ عام في السكريبت:', e); process.exit(1); });

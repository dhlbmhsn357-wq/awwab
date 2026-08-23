# أوّاب — نسخة Android (Capacitor)

طبقة Android حقيقية فوق نفس تطبيق الويب/PWA الموجود — نفس الحساب،
نفس قاعدة البيانات (Supabase)، نفس منطق العمل بالكامل. الويب/PWA
مايتأثرش خالص بوجود النسخة دي.

## البنية

```
index.html, manifest.json, sw.js, icon-*.png   ← المصدر الحقيقي الوحيد للكود (زي ما هو دايمًا)
capacitor.config.ts                             ← إعداد Capacitor (appId: com.awwab.app)
scripts/prepare-www.mjs                         ← بينسخ (مش يعدّل) الملفات دي لـwww/ قبل أي cap sync
www/                                             ← مولّد تلقائيًا، متسجلش في Git
android/                                         ← مشروع Android الحقيقي (Gradle)
.github/workflows/android-build.yml             ← بناء APK سحابيًا (Actions)
```

## ليه مفيش Build محلي هنا

الجهاز اللي بيتطوّر عليه المشروع حاليًا مفيهوش Android SDK/Java. كل
بناء الـAPK بيحصل عبر GitHub Actions (workflow `android-build.yml`)،
والنتيجة بتترفع كـArtifact قابل للتحميل من تبويب **Actions** في
الريبو (اسم الـArtifact: `awwab-debug-apk`).

لو عندك Android Studio مثبّت محليًا بدل كده:
```bash
npm install
npm run cap:sync      # بينسخ الويب لـwww/ ويزامن مشروع android/
npm run cap:open:android   # يفتح المشروع في Android Studio
```

## Package ID و App Name

- **Package ID**: `com.awwab.app` — ثابت، منتغيرش أبدًا بعد كده
  (مرتبط بأي تحديث مستقبلي/نشر على المتجر).
- **App Name**: أوّاب (بالعربي، ظاهر صح في Launcher — مُتحقق منه في
  `android/app/src/main/res/values/strings.xml`).

## الحالة الحالية (Phase 1 — مكتملة)

- ✅ مشروع Android مولّد (`npx cap add android`)، appId
  `com.awwab.app`، اسم التطبيق "أوّاب" ظاهر صح في الموارد.
- ✅ خط بناء APK سحابي شغّال وناجح (GitHub Actions، JDK 21 + Node 22
  — Capacitor 8 محتاجهم بالظبط).
- ✅ اتأكد إن ملفات `www/` (المنسوخة لـAndroid) مطابقة بايت-لبايت
  لملفات الويب الحقيقية.
- ✅ اتأكد إن نشر الويب/PWA على Vercel مش متأثر خالص (قبل وبعد إضافة
  ملفات Android، فحصت الموقع الحي مباشرة).
- ⏳ الأيقونة/Splash لسه افتراضية من Capacitor — Phase 2.
- ⏳ Auth/Offline/Widget/Notifications — مراحل لاحقة، راجع خطة
  التنفيذ في المحادثة.

## اختبار حي

كل تحقق من سلوك حقيقي على جهاز (استمرار الجلسة، الأوفلاين، الودجت)
محتاج تثبيت الـAPK على موبايل Android حقيقي — مفيش إيموليتر أو جهاز
متاح في بيئة التطوير الحالية.

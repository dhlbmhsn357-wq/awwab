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
- ⏳ Auth/Offline/Widget/Notifications — مراحل لاحقة، راجع خطة
  التنفيذ في المحادثة.

## الحالة الحالية (Phase 2 — مكتملة)

- ✅ أيقونة حقيقية بدل الافتراضية: `scripts/generate-android-icons.py`
  بيولّدها من `icon-512.png` نفسه (نفس أيقونة الويب/PWA، بدون تصميم
  جديد) — Legacy (بالشعار الكامل)، Adaptive foreground (الشعار بس،
  محطوط في المنطقة الآمنة عشان مايتقصش)، وRound، لكل الكثافات
  (mdpi→xxxhdpi).
- ✅ لون خلفية الأيقونة التكيّفية (`ic_launcher_background.xml`)
  مأخوذ من نفس لون خلفية الشعار الحقيقي (`#F2F0F1`).
- ✅ Splash Screen ببراند أوّاب (نفس لون الخلفية + الشعار الكامل في
  النص) بدل شاشة Capacitor الفاضية الافتراضية، لكل الكثافات
  واتجاهي الشاشة (port/land).
- ✅ ألوان شريط الحالة/التنقّل (`status/navigation bar`) بلون هوية
  أوّاب الأساسي (`#015C51`) بدل الأزرق الافتراضي، مع أيقونات فاتحة
  (`windowLightStatusBar=false`) لتباين واضح فوق اللون الغامق.
- ✅ `colors.xml` (كان ناقص من مشروع Capacitor المولّد تلقائيًا،
  رغم إن `styles.xml` بيرجع له) — اتضاف بألوان الهوية الحقيقية.

لإعادة توليد الأيقونات/الـSplash بعد أي تغيير مستقبلي في
`icon-512.png`:
```bash
python scripts/generate-android-icons.py
```

## اختبار حي

كل تحقق من سلوك حقيقي على جهاز (استمرار الجلسة، الأوفلاين، الودجت)
محتاج تثبيت الـAPK على موبايل Android حقيقي — مفيش إيموليتر أو جهاز
متاح في بيئة التطوير الحالية.

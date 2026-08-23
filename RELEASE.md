# أوّاب — تجهيز إصدار Android موقّع (Release)

هذا الملف بيوثّق خطوات آخر مرحلة (Phase 10) اللي **لازم تنفّذها إنت
شخصيًا** — مش حاجة ينفع تتعمل تلقائيًا. السبب: مفتاح التوقيع
(Keystore) هو الهوية الدائمة لتطبيقك على Google Play — لو اتفقد، مفيش
طريقة ترجّعه، ومحدش (بما فيه أنا) ينفع يعمله نيابة عنك ويحتفظ بيه في
مكان مش تحت سيطرتك المباشرة. ده بالظبط نفس سبب إن الـ.gitignore بيمنع
رفع أي `.keystore`/`.jks` لـ Git خالص.

## 1) إنشاء الـKeystore (مرة واحدة، للأبد)

محتاج Java (JDK) مثبّت على جهازك — لو مش موجود، أسهل حل تستخدم
[Android Studio](https://developer.android.com/studio) اللي بيجيله
معاه، أو تركّب JDK لوحده.

```bash
keytool -genkeypair -v -keystore awwab-release.keystore -alias awwab -keyalg RSA -keysize 2048 -validity 10000
```

هيسألك كام سؤال (اسمك، بلدك...) وباسورد للـkeystore والمفتاح — **احفظهم
في مدير باسورد، مش في ملاحظة عادية.** لو نسيتهم أو فقدت الملف، مش
هتقدر تنشر تحديثات لنفس التطبيق تاني على Google Play أبدًا — هيبقى
لازم تطبيق جديد بـpackage ID مختلف.

**اعمل نسخة احتياطية من `awwab-release.keystore` في أكتر من مكان آمن**
(مدير باسورد يدعم مرفقات، تخزين سحابي مشفّر... إلخ) — الملف ده أهم من
أي كود في المشروع.

## 2) إعداد المشروع محليًا

```bash
mv awwab-release.keystore android/awwab-release.keystore
cp android/keystore.properties.example android/keystore.properties
```

افتح `android/keystore.properties` وحط الباسوردات الحقيقية اللي
اخترتها فوق. الملف ده متسجّلش في Git أصلًا (`.gitignore`).

`android/app/build.gradle` بيقرا الملف ده تلقائيًا لو موجود، ويوقّع
أي `assembleRelease`/`bundleRelease` بيه — من غيره، بناء الـRelease
بيفضل شغال زي ما هو دلوقتي (من غير توقيع، للتطوير بس).

## 3) بناء إصدار موقّع

محليًا (لو عندك Android SDK):
```bash
npm run cap:sync
cd android && ./gradlew bundleRelease   # لـGoogle Play (.aab)
# أو
cd android && ./gradlew assembleRelease  # APK موقّع للتوزيع المباشر
```

عبر GitHub Actions (زي ما الـdebug APK بيتبني دلوقتي): ارفع محتوى
الـkeystore و`keystore.properties` كـ GitHub Secrets (`Settings →
Secrets and variables → Actions`)، وعدّل `.github/workflows/
android-build.yml` يفك تشفيرهم قبل خطوة البناء ويشغّل
`assembleRelease`/`bundleRelease` بدل `assembleDebug`. الخطوة دي
مقصودة تتعمل يدويًا لما تكون فعليًا جاهز تنشر — مش متعملة تلقائيًا
دلوقتي عشان تفعيلها من غير keystore حقيقي هيفشّل كل بناء موجود.

## 4) R8 / ProGuard (تصغير وتعتيم الكود)

`minifyEnabled` متسيّب `false` عمدًا في `android/app/build.gradle`.
القواعد اللازمة لـCapacitor (`android/app/proguard-rules.pro`) جاهزة
ومظبوطة، بس تفعيل R8 محتاج اختبار حقيقي على جهاز بعدها — لو حاجة
اتحذفت غلط بالـreflection (بعيد لكن ممكن)، التطبيق ممكن يوقّع بصمت من
غير أي رسالة خطأ واضحة وقت البناء. لما يكون عندك جهاز تختبر عليه:

```gradle
buildTypes {
    release {
        minifyEnabled true   // بدّلها من false
        ...
    }
}
```

ابني، ثبّت، وجرّب كل شاشات التطبيق (تسجيل دخول، تسجيل عبادة، أوفلاين،
الودجت) قبل ما تعتمد على النسخة دي.

## 5) رفع Google Play (أول مرة)

خارج نطاق هذا المستند — يحتاج حساب Google Play Console (رسوم لمرة
واحدة)، صفحة تطبيق (وصف، صور، سياسة خصوصية)، ومراجعة Google. لو قررت
تنشر فعليًا، قولّي وهساعدك تجهّز كل حاجة تقنية لازمة (Privacy Policy،
Data Safety form، AAB نهائي...).

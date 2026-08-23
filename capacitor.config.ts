import type { CapacitorConfig } from '@capacitor/cli';

// أوّاب — إعداد Capacitor. webDir بيشاور على مجلد www/ اللي فيه
// نسخة (مش تعديل) من ملفات الويب الفعلية بس — لازم مجلد مخصّص
// عشان مانديش لـCapacitor الريبو كله (node_modules، .git، migrations...).
// السكريبت scripts/prepare-www.mjs هو المصدر الوحيد اللي بيملأ
// www/، ودايمًا بينسخ نفس ملفات index.html/manifest/الأيقونات/sw.js
// الحقيقية زي ما هي — مفيش أي نسخة تانية من الكود أو منطق مختلف.
const config: CapacitorConfig = {
  appId: 'com.awwab.app',
  appName: 'أوّاب',
  webDir: 'www',
  android: {
    // WebView بيتعامل مع نفس روابط https://awwab-ashen.vercel.app لو
    // احتجنا نفتح رابط خارجي — external links هتتفتح في متصفح حقيقي
    // مش تتعلق جوه الـWebView (بند 69 من الخطة)
    allowMixedContent: false,
  },
  plugins: {
    LocalNotifications: {
      // أيقونة شريط الحالة (مولّدة من scripts/generate-android-icons.py)
      // + لون هوية أوّاب بدل الأخضر الافتراضي لأندرويد
      smallIcon: 'ic_stat_notify',
      iconColor: '#017C6E',
    },
  },
};

export default config;

// أوّاب — نسخ ملفات الويب الحقيقية (مش تعديلها) لمجلد www/ عشان
// Capacitor يقدر يبنيهم جوه تطبيق Android. شغّله قبل أي `cap sync`
// (السكريبت cap:sync في package.json بيعمل ده تلقائيًا).
import { existsSync, mkdirSync, copyFileSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const wwwDir = path.join(root, 'www');

const FILES = [
  'index.html',
  'manifest.json',
  'sw.js',
  'icon-192.png',
  'icon-512.png',
  'apple-touch-icon.png',
  'favicon-32.png',
];

if (existsSync(wwwDir)) rmSync(wwwDir, { recursive: true, force: true });
mkdirSync(wwwDir, { recursive: true });

let copied = 0;
for (const f of FILES) {
  const src = path.join(root, f);
  if (!existsSync(src)) { console.warn(`  ⚠ متلقاش ${f}، اتخطى`); continue; }
  copyFileSync(src, path.join(wwwDir, f));
  copied++;
}
console.log(`✓ نسخت ${copied} ملف لـ www/`);

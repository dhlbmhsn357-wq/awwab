#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# أوّاب — توليد أيقونات Android من icon-512.png الحقيقية (نفس أيقونة
# الويب/PWA، بدون أي تصميم جديد). بيولّد 3 أنواع:
#   1) Legacy (ic_launcher.png): الشعار الكامل (بالنص "أوّاب") زي ما
#      هو — مايتقصّش لأنه مش بيتقص بماسك دائري عادةً.
#   2) Adaptive foreground (ic_launcher_foreground.png): الشعار بس
#      (بدون النص) مقصوص ومحطوط في المنطقة الآمنة، عشان مايتقصش
#      لما أندرويد يطبّق شكل (دائرة/مربع مدوّر...) حسب جهاز المستخدم.
#   3) Round (ic_launcher_round.png): نفس الشعار بدون نص، على دائرة.
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'icon-512.png')
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')

# حدود قص "الشعار بس" (من غير النص) — اتحدّدت بالمعاينة المباشرة
GLYPH_BOX = (90, 25, 422, 340)
BG_COLOR = (242, 240, 241)  # نفس لون خلفية الشعار الحقيقي (Sampled)

LEGACY_SIZES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
ADAPTIVE_SIZES = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
SAFE_ZONE_RATIO = 0.62  # المنطقة الآمنة لأيقونات Adaptive (~66% كحد أقصى موصى بيه)


def circle_mask(size):
    mask = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((0, 0, size, size), fill=255)
    return mask


def main():
    src = Image.open(SRC).convert('RGBA')
    glyph = src.crop(GLYPH_BOX)

    for density, size in LEGACY_SIZES.items():
        out_dir = os.path.join(RES, f'mipmap-{density}')
        os.makedirs(out_dir, exist_ok=True)
        # 1) Legacy: الشعار الكامل زي ما هو
        legacy = src.resize((size, size), Image.LANCZOS)
        legacy.save(os.path.join(out_dir, 'ic_launcher.png'))
        # 3) Round: الشعار بس (بدون نص) على دائرة بلون الخلفية
        round_canvas = Image.new('RGBA', (size, size), BG_COLOR + (255,))
        g = glyph.copy()
        g.thumbnail((int(size * 0.82), int(size * 0.82)), Image.LANCZOS)
        pos = ((size - g.width) // 2, (size - g.height) // 2)
        round_canvas.paste(g, pos, g)
        round_canvas.putalpha(circle_mask(size))
        round_canvas.save(os.path.join(out_dir, 'ic_launcher_round.png'))

    for density, size in ADAPTIVE_SIZES.items():
        out_dir = os.path.join(RES, f'mipmap-{density}')
        os.makedirs(out_dir, exist_ok=True)
        # 2) Adaptive foreground: شفاف بالكامل، الشعار بس محطوط في
        #    المنطقة الآمنة عشان أي جهاز يقصّه بشكل مختلف مايقطعش الشعار
        canvas = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        g = glyph.copy()
        target = int(size * SAFE_ZONE_RATIO)
        g.thumbnail((target, target), Image.LANCZOS)
        pos = ((size - g.width) // 2, (size - g.height) // 2)
        canvas.paste(g, pos, g)
        canvas.save(os.path.join(out_dir, 'ic_launcher_foreground.png'))

    # لون خلفية الأيقونة التكيّفية (نفس لون خلفية الشعار الحقيقي)
    bg_hex = '#%02X%02X%02X' % BG_COLOR
    bg_xml = os.path.join(RES, 'values', 'ic_launcher_background.xml')
    with open(bg_xml, 'w', encoding='utf-8') as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="ic_launcher_background">{bg_hex}</color>\n'
            '</resources>\n'
        )

    # شاشة البدء (Splash): نفس لون خلفية الأيقونة + الشعار الكامل
    # (بالنص) في النص، بدل شاشة Capacitor الافتراضية الفاضية
    splash_targets = {
        'drawable/splash.png': (480, 320),
        'drawable-land-mdpi/splash.png': (480, 320),
        'drawable-land-hdpi/splash.png': (800, 480),
        'drawable-land-xhdpi/splash.png': (1280, 720),
        'drawable-land-xxhdpi/splash.png': (1600, 960),
        'drawable-land-xxxhdpi/splash.png': (1920, 1280),
        'drawable-port-mdpi/splash.png': (320, 480),
        'drawable-port-hdpi/splash.png': (480, 800),
        'drawable-port-xhdpi/splash.png': (720, 1280),
        'drawable-port-xxhdpi/splash.png': (960, 1600),
        'drawable-port-xxxhdpi/splash.png': (1280, 1920),
    }
    for rel_path, (w, h) in splash_targets.items():
        out_path = os.path.join(RES, rel_path)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        canvas = Image.new('RGB', (w, h), BG_COLOR)
        logo = src.convert('RGB')
        target = int(min(w, h) * 0.42)
        logo.thumbnail((target, target), Image.LANCZOS)
        pos = ((w - logo.width) // 2, (h - logo.height) // 2)
        canvas.paste(logo, pos)
        canvas.save(out_path)

    print('[OK] generated all icons (Legacy + Adaptive foreground + Round) for all densities')
    print('[OK] generated all splash screens (brand color + full logo, replacing default blank Capacitor splash)')
    print(f'[OK] adaptive icon background color: {bg_hex}')


if __name__ == '__main__':
    main()

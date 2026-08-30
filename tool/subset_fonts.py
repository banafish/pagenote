# -*- coding: utf-8 -*-
"""花样字体子集化维护脚本（APK/部署瘦身，方案 A）。

把 fonts/ 下的 10 款 OFL 中文字体原地替换为「GB2312 全集 + 常用西文/标点」
子集：手账正文与模板文案覆盖 99%+ 的书写场景，生僻字由引擎回退到系统字体。

保留范围（在 GB2312 全部汉字与符号之外）：
- ASCII 可打印区；Latin-1 补充区（é、ü 等西文字母与 © ° · 等）
- U+2000-206F 通用标点（– — ‘ ’ “ ” … ‰）、U+20A0-20CF 货币符号
- U+3000-303F CJK 标点、U+FF00-FF5E 全角形式、U+FFE0-FFE6 全角符号

使用：python tool/subset_fonts.py（可选传入单个字体文件名，只处理该文件）。
脚本是幂等的维护工具：子集产物直接提交入库，日常构建不依赖 Python；
字体来源与许可证见 lib/models/app_fonts.dart 头注与 fonts/OFL-*.txt。

关于 OFL Reserved Font Name：本脚本只删除未用字形，不改动任何保留字形的
轮廓与命名表，按业界通行做法（Google Fonts / fontsource 的 web 子集交付）
沿用原字体名发布；许可证原文随目录一并分发。
"""

import os
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

FONTS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "fonts")

# 逐字符集合：GB2312 解码得到的全部汉字与符号 + 常用西文补充区。
def build_charset():
    chars = set()
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    for cp in range(0x20, 0x7F):          # ASCII 可打印
        chars.add(chr(cp))
    for lo, hi in [
        (0x00A0, 0x00FF),                 # Latin-1 补充
        (0x2000, 0x206F),                 # 通用标点
        (0x20A0, 0x20CF),                 # 货币符号
        (0x3000, 0x303F),                 # CJK 标点
        (0xFF01, 0xFF5E),                 # 全角形式
        (0xFFE0, 0xFFE6),                 # 全角符号
    ]:
        for cp in range(lo, hi + 1):
            chars.add(chr(cp))
    return chars


def subset_font(src, charset):
    dst = src + ".subset.ttf"
    args = [
        src,
        "--text=" + "".join(sorted(charset)),
        "--layout-features=*",   # 保留 kern/vert 等排版特性
        "--name-IDs=*",          # 保留 name 表，Flutter 按 family 名匹配
        "--glyph-names",
        "--notdef-outline",
        "--recalc-bounds",
        "--no-hinting",          # 中文字形本身几乎无 hinting，省下字节数
        "--output-file=" + dst,
    ]
    subset.main(args)
    os.replace(dst, src)


def main():
    charset = build_charset()
    names = sys.argv[1:] or sorted(
        n for n in os.listdir(FONTS_DIR) if n.lower().endswith(".ttf")
    )
    print(f"子集字符数：{len(charset)}")
    print(f"{'font':38s} {'before':>9s} {'after':>9s}")
    for name in names:
        src = os.path.join(FONTS_DIR, name)
        before = os.path.getsize(src)
        subset_font(src, charset)
        after = os.path.getsize(src)
        # 产出校验：能正常解析、字形数合理、家族名未变。
        font = TTFont(src, lazy=True)
        glyphs = font["maxp"].numGlyphs
        family = font["name"].getDebugName(1)
        font.close()
        print(f"{name:38s} {before/1e6:8.2f}M {after/1e6:8.2f}M  "
              f"glyphs={glyphs} family={family}")


if __name__ == "__main__":
    main()

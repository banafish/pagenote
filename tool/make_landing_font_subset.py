# -*- coding: utf-8 -*-
"""落地页专用霞鹜文楷子集生成脚本（web 首帧提速）。

web 引擎初始化会下载 FontManifest 里声明的全部字体才出首帧。落地页只用
霞鹜文楷渲染固定文案：为其生成仅覆盖落地页字符（landing_page.dart 源码
全字符 + ASCII 可打印区 + 常用中文标点兜底）的小字体，构建期由
tool/strip_web_font_manifest.dart 换入 FontManifest，首帧字体下载从完整
字库（约 2.2MB 传输）降到几十 KB。

子集产物 fonts/LXGWWenKaiLite-LandingSubset.ttf 直接提交入库，日常构建
不依赖 Python；落地页文案变化后重跑本脚本再提交。完整字库仍随包部署，
编辑器内任意文本由 AppFontLoader 首次使用时经 rootBundle 补注册。

使用：python tool/make_landing_font_subset.py
"""

import os

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir)
SOURCE_DART = os.path.join(ROOT, "lib", "pages", "landing_page.dart")
SOURCE_FONT = os.path.join(ROOT, "fonts", "LXGWWenKaiLite-Regular.ttf")
OUTPUT_NAME = "LXGWWenKaiLite-LandingSubset.ttf"
OUTPUT_FONT = os.path.join(ROOT, "fonts", OUTPUT_NAME)


def build_charset():
    chars = set()
    with open(SOURCE_DART, encoding="utf-8") as f:
        chars.update(f.read())
    # ASCII 可打印区兜底：版本号、注入的仓库链接等动态拼接文本。
    for cp in range(0x20, 0x7F):
        chars.add(chr(cp))
    # 常用中文标点兜底，防止少量落网字符回退系统字体造成混排突兀。
    chars.update("，。、：；！？·—…「」『』《》（）")
    chars.difference_update({"\n", "\r", "\t"})
    return chars


def main():
    charset = build_charset()
    # 落地页文案里的 emoji 等符号由引擎回退字体渲染，源字库本就没有：
    # 子集只收录源字体实际存在的字形，其余照原样回退，不做缺失报错。
    source = TTFont(SOURCE_FONT, lazy=True)
    source_cmap = source.getBestCmap()
    source.close()
    charset = {c for c in charset if ord(c) in source_cmap}
    args = [
        SOURCE_FONT,
        "--text=" + "".join(sorted(charset)),
        "--layout-features=*",   # 保留 kern 等排版特性
        "--name-IDs=*",          # 保留 name 表，引擎按 family 名匹配
        "--glyph-names",
        "--notdef-outline",
        "--recalc-bounds",
        "--no-hinting",          # 中文字形本身几乎无 hinting，省下字节数
        f"--output-file={OUTPUT_FONT}",
    ]
    subset.main(args)

    # 产出校验：能正常解析、源字体覆盖的字符在子集中全部保留。引擎按
    # FontManifest 里的 family 别名注册（FontFace(family, url)），字体内部
    # name 表不参与匹配，且 OFL 保留名不允许改写命名表，故不做家族名断言。
    font = TTFont(OUTPUT_FONT, lazy=True)
    cmap = font.getBestCmap()
    missing = sorted(c for c in charset if ord(c) not in cmap)
    family = font["name"].getDebugName(1)
    font.close()
    if missing:
        raise SystemExit(f"子集丢失 {len(missing)} 个源字体已有字符：{''.join(missing[:20])}…")
    print(f"{OUTPUT_NAME}: {os.path.getsize(OUTPUT_FONT) / 1e3:.0f}KB, "
          f"{len(charset)} 字符全部覆盖，内部 family={family!r}")


if __name__ == "__main__":
    main()

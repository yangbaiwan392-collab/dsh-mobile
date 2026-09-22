# -*- coding: utf-8 -*-
"""图标几何预览 + 安全区自检。

自适应图标（adaptive icon）的规则：内容必须落在**中央安全区**内，否则圆形/方形遮罩会裁掉。
本脚本的几何与 res/drawable/ic_launcher_foreground.xml **一一对应** —— 改图标时先改这里、
看预览与断言，再同步到 vector xml（这是唯一能在这台机器上"看到"图标形状的办法）。

用法：python tools/icon-preview.py      # 退出码非零 = 有内容跑出安全区
"""
import math
import os

from PIL import Image, ImageDraw

# ---- 几何（viewBox 108×108）----
RING_R = 31.0          # 朱印圈半径
RING_W = 2.4
BODY_C = (50.0, 58.0)  # 鲸身椭圆中心
BODY_R = (20.0, 13.0)
TAIL = [(69, 58), (78, 48), (73, 58), (78, 68)]
EYE_C, EYE_R = (39.0, 55.0), 2.6
SPOUT = [((41.0, 42.0), 2.2), ((36.0, 37.0), 1.6)]

PAPER = (242, 234, 218)
RED = (168, 48, 36)
INK = (26, 26, 26)

SAFE_R = RING_R - RING_W / 2 - 0.5   # 印圈内沿再留 0.5 余量


def extremes():
    """每个形状离画布中心最远的点（用于安全区断言）。"""
    cx, cy = BODY_C
    yield "鲸身左端", (cx - BODY_R[0], cy)
    yield "鲸身右端", (cx + BODY_R[0], cy)
    for name, (x, y) in zip(("尾鳍上叶", "尾鳍下叶"), (TAIL[1], TAIL[3])):
        yield name, (x, y)
    for i, (c, r) in enumerate(SPOUT):
        yield f"水花{i + 1}", (c[0] - r, c[1] - r)


def check_safe_zone():
    bad = []
    for name, (x, y) in extremes():
        radius = math.hypot(x - 54.0, y - 54.0)
        ok = radius <= SAFE_R
        print(f"  {name:8s} r={radius:5.1f}  上限 {SAFE_R:.1f}  {'OK' if ok else '超界'}")
        if not ok:
            bad.append(name)
    return bad


def render(scale=4):
    size = 108 * scale

    def s(v):
        return v * scale

    img = Image.new("RGB", (size, size), PAPER)
    d = ImageDraw.Draw(img)
    d.ellipse((s(54 - RING_R), s(54 - RING_R), s(54 + RING_R), s(54 + RING_R)),
              outline=INK, width=max(1, int(RING_W * scale)))
    d.ellipse((s(BODY_C[0] - BODY_R[0]), s(BODY_C[1] - BODY_R[1]),
               s(BODY_C[0] + BODY_R[0]), s(BODY_C[1] + BODY_R[1])), fill=RED)
    d.polygon([(s(x), s(y)) for x, y in TAIL], fill=RED)
    d.ellipse((s(EYE_C[0] - EYE_R), s(EYE_C[1] - EYE_R),
               s(EYE_C[0] + EYE_R), s(EYE_C[1] + EYE_R)), fill=PAPER)
    for (cx, cy), r in SPOUT:
        d.ellipse((s(cx - r), s(cy - r), s(cx + r), s(cy + r)), fill=RED)
    return img, scale


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    print("安全区自检（安全半径 %.1f / 33）:" % SAFE_R)
    bad = check_safe_zone()

    img, scale = render()
    size = img.size[0]
    img.save(os.path.join(here, "_icon_preview_full.png"))
    img.resize((144, 144), Image.LANCZOS).save(os.path.join(here, "_icon_preview_small.png"))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((scale * 18, scale * 18, scale * 90, scale * 90), fill=255)  # 圆形遮罩
    round_img = Image.new("RGB", (size, size), (24, 24, 24))
    round_img.paste(img, (0, 0), mask)
    round_img.save(os.path.join(here, "_icon_preview_round.png"))

    if bad:
        print("超界：", "、".join(bad))
        raise SystemExit(1)
    print("全部落在安全区内；预览已写入 tools/_icon_preview_{full,round,small}.png")


if __name__ == "__main__":
    main()

"""把怪诞手绘插画合成成手机壁纸（精确到目标机型的物理分辨率）。

为什么要写这个（而不是直接设成壁纸）：
  · SDXL 出的线稿**带浅灰纸纹底**（技能里明确记过这个坑），直接贴到纯色画布上会露灰方块；
    这里按亮度阈值把"接近白"的像素统一成纸色 #FFFDF8，只保留真笔画与彩色。
  · 手机是 1440x3168（1:2.2），SDXL 排不出这种极端比例 → 出 2:3 的竖图，再按"避开状态栏
    与底部图标区"的版式铺到精确画布上。

用法：
  python tools/make-wallpaper.py --art <插画.png> --out <输出.png> [--accent-auto]
"""
import argparse
from pathlib import Path

from PIL import Image

PAPER = (255, 253, 248)     # 技能里的底色：#FFFDF8（白或轻微米白）
INK_THRESHOLD = 196         # 三通道都 >= 这个值就算"纸"（SDXL 的灰纹一般在 200-235）
TARGET = (1440, 3168)       # moto XT2611-1 物理分辨率（adb shell wm size 实测）
MARGIN_X = 150              # 左右留白
TOP_RATIO = 0.145           # 插画顶端落在画布的这个比例处（给状态栏/时钟让位）
BOTTOM_KEEP = 0.16          # 底部这么多比例保持空白（图标 dock 区）


def clean_background(image: Image.Image) -> Image.Image:
    """把接近白的像素统一成纸色，去掉 SDXL 的浅灰纸纹。"""
    image = image.convert("RGB")
    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            r, g, b = pixels[x, y]
            if r >= INK_THRESHOLD and g >= INK_THRESHOLD and b >= INK_THRESHOLD:
                pixels[x, y] = PAPER
    return image


def build(art_path: Path, out_path: Path) -> dict:
    art = clean_background(Image.open(art_path))
    canvas_w, canvas_h = TARGET

    art_w = canvas_w - MARGIN_X * 2
    art_h = round(art.height * art_w / art.width)
    max_h = round(canvas_h * (1 - TOP_RATIO - BOTTOM_KEEP))
    if art_h > max_h:
        art_h = max_h
        art_w = round(art.width * art_h / art.height)
    art = art.resize((art_w, art_h), Image.LANCZOS)

    canvas = Image.new("RGB", TARGET, PAPER)
    x = (canvas_w - art_w) // 2
    y = round(canvas_h * TOP_RATIO)
    canvas.paste(art, (x, y))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, "PNG", optimize=True)

    # 预览图（放聊天里看）
    preview = canvas.copy()
    preview.thumbnail((540, 1188), Image.LANCZOS)
    preview_path = out_path.with_name(out_path.stem + "-preview.png")
    preview.save(preview_path, "PNG", optimize=True)
    return {
        "out": str(out_path),
        "preview": str(preview_path),
        "art_box": (x, y, x + art_w, y + art_h),
        "size": canvas.size,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--art", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    info = build(Path(args.art), Path(args.out))
    print(f"output  : {info['out']}")
    print(f"preview : {info['preview']}")
    print(f"size    : {info['size'][0]}x{info['size'][1]}")
    print(f"art box : x={info['art_box'][0]}..{info['art_box'][2]}  y={info['art_box'][1]}..{info['art_box'][3]}")
    print(f"bottom empty: {info['size'][1] - info['art_box'][3]} px")


if __name__ == "__main__":
    main()

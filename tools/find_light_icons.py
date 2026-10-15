# 找出在深色外观下背景仍然偏浅的图标：取图标主体靠内一圈的像素，看亮度中位数
import sys, os, json
from PIL import Image, ImageDraw, ImageFont
import numpy as np
src, out = sys.argv[1], sys.argv[2]
rows = []
for f in sorted(os.listdir(src)):
    if not f.endswith('.png'): continue
    a = np.array(Image.open(os.path.join(src, f)).convert('RGBA')).astype(float)
    n = a.shape[0]; Y, X = np.mgrid[0:n, 0:n]
    # 主体约占 100/1024–924/1024；取距边缘 14%–20% 的一圈，大多是背景
    d = np.maximum(np.abs(X - n/2), np.abs(Y - n/2)) / n
    ring = (d > 0.30) & (d < 0.36) & (a[..., 3] > 200)
    if ring.sum() < 50: rows.append((f[:-4], None)); continue
    lum = (0.2126*a[...,0] + 0.7152*a[...,1] + 0.0722*a[...,2])[ring] / 255
    rows.append((f[:-4], float(np.median(lum))))
light = [(name, l) for name, l in rows if l is not None and l > 0.55]
odd = [name for name, l in rows if l is None]
json.dump({'light': light, 'unknown': odd, 'all': rows}, open(out + '.json', 'w'), ensure_ascii=False, indent=1)
# 对比图：深色背景上排列所有偏浅的图标，下面写应用名
cols, cell = 6, 200
names = [n for n, _ in light]
H = ((len(names) + cols - 1) // cols) * (cell + 40) + 20
sheet = Image.new('RGBA', (cols * cell + 20, max(H, 100)), (30, 30, 32, 255))
font = ImageFont.truetype('/System/Library/Fonts/Hiragino Sans GB.ttc', 18)
dr = ImageDraw.Draw(sheet)
for i, name in enumerate(names):
    x, y = 10 + (i % cols) * cell, 10 + (i // cols) * (cell + 40)
    im = Image.open(os.path.join(src, name + '.png')).convert('RGBA').resize((cell - 30, cell - 30), Image.LANCZOS)
    sheet.alpha_composite(im, (x + 15, y))
    label = name if len(name) <= 16 else name[:15] + '…'
    w = dr.textlength(label, font=font); dr.text((x + (cell - w) / 2, y + cell - 22), label, font=font, fill=(230, 230, 230))
sheet.save(out + '.png')
print('偏浅：', len(light), [n for n, _ in light]); print('无法判断：', odd)

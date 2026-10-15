# 从 Antigravity 白底图标里分离出彩色 A 图形，输出 Icon Composer 1024 画布上的图层 PNG
import sys
from PIL import Image, ImageFilter; import numpy as np
src, dst = sys.argv[1], sys.argv[2]
a = np.array(Image.open(src).convert('RGBA')).astype(float)        # 512×512
rgb = a[..., :3]
d = (255 - rgb.min(2)) / 255                                       # 偏离白色的程度
n = d.shape[0]; Y, X = np.mgrid[0:n, 0:n]
inner = (np.abs(X - n/2) < n*0.4) & (np.abs(Y - n/2) < n*0.4)      # 避开圆角方块边缘
d = d * inner * (a[..., 3] >= 250)                              # 圆角外的透明区域不算图形
# 覆盖率 = 当前偏离 / 附近图形内部的偏离；边缘像素是“图形色 + 白色”的混合
loc = np.array(Image.fromarray((d * 255).astype('uint8')).filter(ImageFilter.MaxFilter(7))).astype(float) / 255
alpha = np.where(loc > 0.12, np.clip(d / np.maximum(loc, 1e-6), 0, 1), 0)
# 还原纯色：C = 255 - (255 - 观测色) / alpha；透明度很低的像素借用附近颜色
col = 255 - (255 - rgb) / np.maximum(alpha, 1e-3)[..., None]
col = np.where((alpha > 0.35)[..., None], col, np.nan)
for _ in range(6):                                                 # 向外扩色，避免边缘发白
    filled = np.nan_to_num(col)
    w = (~np.isnan(col[..., 0])).astype(float)
    blur = lambda x: sum(np.roll(np.roll(x, i, 0), j, 1) for i in (-1, 0, 1) for j in (-1, 0, 1)) / 9
    s = np.dstack([blur(filled[..., c] * w) for c in range(3)]); ws = blur(w)[..., None]
    col = np.where(np.isnan(col), np.where(ws > 0, s / np.maximum(ws, 1e-6), np.nan), col)
col = np.nan_to_num(col, nan=128).clip(0, 255)

# 主体 47.5–464（原图标 95–928 的一半）映射到 1024 画布；放大后按放大倍数锐化透明度边缘
box = (47.5, 47.5, 464, 464); k = 1024 / (464 - 47.5)
up = lambda x: np.array(Image.fromarray(x.astype('float32'), 'F').transform((1024, 1024), Image.EXTENT, box, Image.BICUBIC))
A = np.clip((up(alpha) - 0.5) * k + 0.5, 0, 1)
C = np.dstack([up(col[..., c]) for c in range(3)]).clip(0, 255)
Image.fromarray(np.dstack([C, A * 255]).round().astype('uint8'), 'RGBA').save(dst)

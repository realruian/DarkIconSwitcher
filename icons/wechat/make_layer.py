# 从微信自带的 1024 图标里分离出白色气泡，生成 Icon Composer 1024 画布上的气泡图层（填微信绿）
# 用法：python make_layer.py <微信 1024 图标 PNG> <输出图层 PNG>
# 微信图标 PNG 可用 tools/extract_car 从 /Applications/WeChat.app/Contents/Resources/Assets.car 导出（AppIcon 的 1024 版本）
import sys
from PIL import Image
import numpy as np

src, dst = sys.argv[1], sys.argv[2]
a = np.array(Image.open(src).convert('RGBA')).astype(float)
Y, X = np.mgrid[0:1024, 0:1024]
inner = (X > 190) & (X < 845) & (Y > 190) & (Y < 845)              # 避开边缘的玻璃高光
g = np.clip((a[..., 0] - 40) / 210, 0, 1) * inner                    # 绿底 R≈2–7，白气泡 R=255
# 图标主体 100–924 映射到 Icon Composer 的 1024 画布
m = Image.fromarray((g * 255).astype('uint8')).crop((100, 100, 924, 924)).resize((1024, 1024), Image.LANCZOS)
out = np.zeros((1024, 1024, 4), 'uint8')
out[..., 0], out[..., 1], out[..., 2] = 7, 193, 96                     # 微信绿
out[..., 3] = np.array(m)
Image.fromarray(out, 'RGBA').save(dst)

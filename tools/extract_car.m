// 从应用的 Assets.car 导出所有位图资源（含图标分层素材），文件名形如 名称_序号_外观.png
// 编译：clang -fobjc-arc -o build/extract_car tools/extract_car.m -framework Foundation -framework CoreGraphics -framework ImageIO -F /System/Library/PrivateFrameworks -framework CoreUI
// 用法：build/extract_car <Assets.car> <输出目录>
// 用的是系统私有框架 CoreUI；矢量图层（SVG/PDF）取不出来。
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
@interface CUICatalog : NSObject
- (instancetype)initWithURL:(NSURL *)url error:(NSError **)e;
- (NSArray *)allImageNames;
- (NSArray *)imagesWithName:(NSString *)n;
@end
@interface CUINamedImage : NSObject
- (CGImageRef)image; - (double)scale; - (long long)appearance; - (NSString *)appearanceName;
@end
int main(int argc, char **argv) { @autoreleasepool {
  CUICatalog *c = [[NSClassFromString(@"CUICatalog") alloc] initWithURL:[NSURL fileURLWithPath:@(argv[1])] error:nil];
  NSString *out = @(argv[2]);
  for (NSString *n in [c allImageNames]) {
    int i = 0;
    for (CUINamedImage *im in [c imagesWithName:n]) {
      if (![im respondsToSelector:@selector(image)]) continue;
      CGImageRef cg = [im image]; if (!cg) continue;
      NSString *ap = [im respondsToSelector:@selector(appearanceName)] ? [im appearanceName] : @"";
      NSString *f = [NSString stringWithFormat:@"%@/%@_%d_%@.png", out, [n stringByReplacingOccurrencesOfString:@"/" withString:@"_"], i++, ap ?: @""];
      CGImageDestinationRef d = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:f], CFSTR("public.png"), 1, NULL);
      CGImageDestinationAddImage(d, cg, NULL); CGImageDestinationFinalize(d); CFRelease(d);
      printf("%s %zux%zu\n", f.lastPathComponent.UTF8String, CGImageGetWidth(cg), CGImageGetHeight(cg));
    }
  }
}}

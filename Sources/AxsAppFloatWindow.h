#pragma once

#import <UIKit/UIKit.h>
#import "AxsAppFloatSceneHost.h"

// 单个浮窗卡片：标题栏拖动 + 关闭/放大按钮 + 右下角缩放 + 贴边吸附分屏。
@interface AxsAppFloatWindow : UIView
@property (nonatomic, copy, readonly) NSString *bundleID;
@property (nonatomic, strong, readonly) AxsAppFloatSceneHost *host;
@property (nonatomic, copy) void (^onClose)(AxsAppFloatWindow *window);

- (instancetype)initWithBundleID:(NSString *)bundleID
                      displayName:(NSString *)name
                         iconImage:(UIImage *)icon;
- (void)updateChromeAlpha:(CGFloat)alpha;
@end

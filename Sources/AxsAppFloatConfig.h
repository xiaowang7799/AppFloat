#pragma once

#import <Foundation/Foundation.h>

@interface AxsAppFloatConfig : NSObject
+ (instancetype)axs_appfloat_shared;
- (BOOL)axs_appfloat_isEnabled;      // 总开关
- (BOOL)axs_appfloat_snapOn;         // 贴边吸附分屏
- (double)axs_appfloat_windowAlpha;  // 浮窗透明度
- (NSInteger)axs_appfloat_maxWindows; // 最大浮窗数（1–2）
@end

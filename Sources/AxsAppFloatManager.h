#pragma once

#import <UIKit/UIKit.h>

// 全局管理：穿透 overlay 窗口、右边缘手势呼出应用面板、浮窗生命周期。
@interface AxsAppFloatManager : NSObject
+ (instancetype)axs_appfloat_shared;
- (void)axs_appfloat_bootstrap;
@end

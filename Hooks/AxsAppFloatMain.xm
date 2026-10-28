#import <UIKit/UIKit.h>
#import "AxsAppFloatManager.h"
#import "AxsAppFloatConfig.h"

// 多重触发 + 自愈重试：不依赖 SpringBoard 生命周期方法名（iOS 26 可能变）。
static void axs_appfloat_tryBootstrap(NSTimeInterval delay) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @autoreleasepool {
            if ([AxsAppFloatConfig axs_appfloat_shared].axs_appfloat_isEnabled) {
                [[AxsAppFloatManager axs_appfloat_shared] axs_appfloat_bootstrap];
            }
        }
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    axs_appfloat_tryBootstrap(2.0);
}
%end

%ctor {
    @autoreleasepool {
        [AxsAppFloatConfig axs_appfloat_shared];
        // 兜底触发：dylib 加载后 4/7/11 秒各试一次（幂等，建过就跳过）。
        axs_appfloat_tryBootstrap(4.0);
        axs_appfloat_tryBootstrap(7.0);
        axs_appfloat_tryBootstrap(11.0);
    }
}

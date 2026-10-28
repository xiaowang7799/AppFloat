#import <UIKit/UIKit.h>
#import "AxsAppFloatManager.h"
#import "AxsAppFloatConfig.h"

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    @autoreleasepool {
        if ([AxsAppFloatConfig axs_appfloat_shared].axs_appfloat_isEnabled) {
            // 延迟 2s 等 SpringBoard 窗口就绪。
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [[AxsAppFloatManager axs_appfloat_shared] axs_appfloat_bootstrap];
            });
        }
    }
}
%end

%ctor {
    @autoreleasepool {
        [AxsAppFloatConfig axs_appfloat_shared];
    }
}

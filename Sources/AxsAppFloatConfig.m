#import "AxsAppFloatConfig.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kAxsAppFloatDomain = @"com.axs.appfloat";

@interface AxsAppFloatConfig ()
@property (nonatomic, strong) NSDictionary *snapshot;
@end

static void axs_appfloat_reload(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)name; (void)object; (void)userInfo;
    AxsAppFloatConfig *config = (__bridge AxsAppFloatConfig *)observer;
    [config axs_appfloat_reload];
}

@implementation AxsAppFloatConfig

+ (instancetype)axs_appfloat_shared {
    static AxsAppFloatConfig *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[AxsAppFloatConfig alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self axs_appfloat_reload];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        axs_appfloat_reload,
                                        CFSTR("com.axs.appfloat/preferences-changed"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)axs_appfloat_reload {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Preferences/com.axs.appfloat.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
    self.snapshot = [dict isKindOfClass:[NSDictionary class]] ? dict : @{};
}

- (id)axs_appfloat_valueForKey:(NSString *)key defaultValue:(id)fallback {
    id v = self.snapshot[key];
    return v ?: fallback;
}

- (BOOL)axs_appfloat_isEnabled {
    return [[self axs_appfloat_valueForKey:@"enabled" defaultValue:@YES] boolValue];
}
- (BOOL)axs_appfloat_snapOn {
    return [[self axs_appfloat_valueForKey:@"snap_on" defaultValue:@YES] boolValue];
}
- (double)axs_appfloat_windowAlpha {
    double d = [[self axs_appfloat_valueForKey:@"window_alpha" defaultValue:@1.0] doubleValue];
    return fmax(0.5, fmin(1.0, isfinite(d) ? d : 1.0));
}
- (NSInteger)axs_appfloat_maxWindows {
    NSInteger n = [[self axs_appfloat_valueForKey:@"max_windows" defaultValue:@2] integerValue];
    return (n == 1) ? 1 : 2;
}

@end

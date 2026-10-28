#import "AxsAppFloatAppListController.h"
#import <Preferences/PSSpecifier.h>
#import <objc/message.h>

static NSString *const kAxsAppFloatAppsDomain = @"com.axs.appfloat";

@interface AxsAppFloatAppListController ()
@end

@implementation AxsAppFloatAppListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [NSMutableArray array];
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"选择浮窗应用"];
        [group setProperty:@"打开开关 = 该 App 出现在浮窗面板里；全部关闭 = 显示所有应用。"
                    forKey:@"footerText"];
        [items addObject:group];

        // 枚举已安装应用（LSApplicationWorkspace）。
        Class wsCls = NSClassFromString(@"LSApplicationWorkspace");
        id ws = wsCls
            ? ((id (*)(id, SEL))objc_msgSend)(wsCls, NSSelectorFromString(@"defaultWorkspace"))
            : nil;
        SEL allSel = NSSelectorFromString(@"allInstalledApplications");
        NSArray *proxies = (ws && [ws respondsToSelector:allSel])
            ? ((id (*)(id, SEL))objc_msgSend)(ws, allSel) : @[];
        NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
        for (id proxy in proxies) {
            @try {
                NSString *name = [proxy valueForKey:@"localizedName"];
                NSString *bid = [proxy valueForKey:@"bundleIdentifier"];
                if (!name.length || !bid.length) continue;
                NSString *type = [proxy valueForKey:@"applicationType"]
                    ?: [proxy valueForKey:@"appType"];
                BOOL thirdParty = [type isEqualToString:@"User"] || ![bid hasPrefix:@"com.apple."];
                if (!thirdParty) continue;
                [rows addObject:@{@"name": name, @"bid": bid}];
            } @catch (__unused NSException *e) {}
        }
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"name"] localizedCompare:b[@"name"]];
        }];
        for (NSDictionary *row in rows) {
            PSSpecifier *sw = [PSSpecifier preferenceSpecifierNamed:row[@"name"]
                target:self
                set:@selector(setPreferenceValue:specifier:)
                get:@selector(readPreferenceValue:)
                detail:nil
                cell:PSSwitchCell
                edit:nil];
            [sw setProperty:[@"app:" stringByAppendingString:row[@"bid"]] forKey:@"key"];
            [sw setProperty:kAxsAppFloatAppsDomain forKey:@"defaults"];
            [sw setProperty:@NO forKey:@"default"];
            [sw setProperty:row[@"name"] forKey:@"label"];
            [items addObject:sw];
        }
        _specifiers = items;
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Preferences/com.axs.appfloat.plist"];
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    id value = prefs[[specifier propertyForKey:@"key"]];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Preferences/com.axs.appfloat.plist"];
    NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy]
        ?: [NSMutableDictionary dictionary];
    prefs[[specifier propertyForKey:@"key"]] = value;
    [prefs writeToFile:path atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.axs.appfloat/preferences-changed"), NULL, NULL, YES);
}

@end

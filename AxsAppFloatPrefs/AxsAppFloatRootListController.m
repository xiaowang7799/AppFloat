#import "AxsAppFloatRootListController.h"
#import <Preferences/PSSpecifier.h>

static NSString *const kAxsAppFloatDomain = @"com.axs.appfloat";

@interface AxsAppFloatRootListController ()
@end

@implementation AxsAppFloatRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"AxsAppFloatRoot"
                                                            target:self] mutableCopy];
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

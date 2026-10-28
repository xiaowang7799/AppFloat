#pragma once

#import <Preferences/PSListController.h>
// 浮窗应用白名单：每行一个应用开关（key = app:<bundleID>），全不勾 = 全部显示。
@interface AxsAppFloatAppListController : PSListController
@end

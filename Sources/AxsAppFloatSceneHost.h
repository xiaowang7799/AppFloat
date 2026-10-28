#pragma once

#import <UIKit/UIKit.h>

// 应用场景宿主：把后台 App 的实时画面嵌入浮窗（DualPane 同款链路：
// SBApplication.mainScene → hostManager → hostViewForRequester:）。
@interface AxsAppFloatSceneHost : NSObject
@property (nonatomic, copy, readonly) NSString *bundleID;
@property (nonatomic, strong, readonly) UIView *hostView;
@property (nonatomic, assign, readonly) BOOL live;
@property (nonatomic, copy) NSString *statusText;

- (instancetype)initWithBundleID:(NSString *)bundleID;
// 找 scene 并把宿主视图嵌入 container；失败返回 NO（显示占位）。
- (BOOL)attachToContainer:(UIView *)container;
// 宿主视图按画布缩放适配 container 尺寸。
- (void)layoutInContainer:(UIView *)container;
// 场景前台续约（防被系统挂起）。
- (void)keepAlive;
- (void)invalidate;
@end

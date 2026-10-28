#import "AxsAppFloatManager.h"
#import "AxsAppFloatWindow.h"
#import "AxsAppFloatConfig.h"
#import <objc/message.h>

// 穿透窗口：只在浮窗/面板区域吃手势，其余透传给系统。
// 右边缘 30pt 条带例外——留给边缘手势（hitTest 返回 nil 手势不会触发）。
@interface AxsAppFloatOverlayWindow : UIWindow
@end
@implementation AxsAppFloatOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) {
        if (point.x >= self.bounds.size.width - 30.0) return self;   // 边缘手势带
        return nil;                                                  // 其余穿透
    }
    return hit;
}
@end

@interface AxsAppFloatManager () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) AxsAppFloatOverlayWindow *overlay;
@property (nonatomic, strong) UIView *pickerPanel;
@property (nonatomic, strong) NSMutableArray<AxsAppFloatWindow *> *windows;
@property (nonatomic, strong) NSTimer *keepAliveTimer;
@end

@implementation AxsAppFloatManager

+ (instancetype)axs_appfloat_shared {
    static AxsAppFloatManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [[AxsAppFloatManager alloc] init]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) { _windows = [NSMutableArray array]; }
    return self;
}

#pragma mark - Bootstrap

- (void)axs_appfloat_bootstrap {
    if (self.overlay) return;
    CGRect screen = [UIScreen mainScreen].bounds;
    UIWindow *overlay = [[AxsAppFloatOverlayWindow alloc] initWithFrame:screen];
    overlay.windowLevel = UIWindowLevelStatusBar - 1.0;   // App 之上、系统弹窗之下
    overlay.backgroundColor = [UIColor clearColor];
    overlay.hidden = NO;
    self.overlay = (AxsAppFloatOverlayWindow *)overlay;

    // 右边缘滑出应用面板。
    UIScreenEdgePanGestureRecognizer *edge = [[UIScreenEdgePanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleEdge:)];
    edge.edges = UIRectEdgeRight;
    [overlay addGestureRecognizer:edge];

    // 保活定时器：场景前台续约（1.5s，几乎零开销）。
    self.keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES
        block:^(NSTimer *t) {
        (void)t;
        AxsAppFloatManager *mgr = [AxsAppFloatManager axs_appfloat_shared];
        for (AxsAppFloatWindow *w in mgr.windows) {
            [w.host keepAlive];
        }
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.keepAliveTimer forMode:NSRunLoopCommonModes];
}

- (void)handleEdge:(UIScreenEdgePanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) {
        [self presentPicker];
    }
}

#pragma mark - 应用面板

- (NSArray<NSDictionary *> *)runningApps {
    NSMutableArray *result = [NSMutableArray array];
    Class cls = NSClassFromString(@"SBApplicationController");
    if (!cls) return result;
    @try {
        id ctrl = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
        SEL sel = NSSelectorFromString(@"allApplications");
        if (![ctrl respondsToSelector:sel]) return result;
        NSArray *apps = ((id (*)(id, SEL))objc_msgSend)(ctrl, sel);
        for (id app in apps) {
            @try {
                NSString *bid = [app valueForKey:@"bundleIdentifier"];
                if (!bid.length || [bid isEqualToString:@"com.apple.springboard"]) continue;
                SEL runSel = NSSelectorFromString(@"isRunning");
                BOOL running = [app respondsToSelector:runSel]
                    ? ((BOOL (*)(id, SEL))objc_msgSend)(app, runSel) : NO;
                if (!running) continue;
                NSString *name = [app valueForKey:@"displayName"] ?: bid;
                UIImage *icon = nil;
                SEL iconSel = NSSelectorFromString(@"iconImageForFormat:");
                if ([app respondsToSelector:iconSel]) {
                    NSMethodSignature *sig = [app methodSignatureForSelector:iconSel];
                    if (sig) {
                        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                        inv.target = app;
                        inv.selector = iconSel;
                        NSInteger fmt = 0;
                        [inv setArgument:&fmt atIndex:2];
                        [inv invoke];
                        __unsafe_unretained id img = nil;
                        [inv getReturnValue:&img];
                        if ([img isKindOfClass:[UIImage class]]) icon = img;
                    }
                }
                [result addObject:@{@"bundleID": bid, @"name": name,
                                    @"icon": icon ?: [UIImage systemImageNamed:@"app.fill"]}];
            } @catch (__unused NSException *e) {}
        }
    } @catch (__unused NSException *e) {}
    return result;
}

- (void)presentPicker {
    if (self.pickerPanel) { [self dismissPicker]; return; }
    NSArray<NSDictionary *> *apps = [self runningApps];
    if (apps.count == 0) return;

    CGRect screen = self.overlay.bounds;
    CGFloat rowH = 64.0;
    CGFloat panelH = MIN(screen.size.height - 120, rowH * apps.count + 56);
    UIView *panel = [[UIView alloc] initWithFrame:
        CGRectMake(screen.size.width - 260, (screen.size.height - panelH) / 2.0, 250, panelH)];
    panel.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
    panel.layer.cornerRadius = 18;
    panel.layer.masksToBounds = YES;
    [self.overlay addSubview:panel];
    self.pickerPanel = panel;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, panelH, 32)];
    title.text = @"浮窗工坊";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [panel addSubview:title];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:
        CGRectMake(0, 48, panel.frame.size.width, panelH - 48)];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    [panel addSubview:scroll];

    CGFloat y = 0;
    for (NSDictionary *app in apps) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(8, y, panel.frame.size.width - 16, rowH - 6);
        row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        row.layer.cornerRadius = 12;
        row.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        UIImageView *iv = [[UIImageView alloc] initWithImage:app[@"icon"]];
        iv.frame = CGRectMake(12, 8, 36, 36);
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.layer.cornerRadius = 8;
        iv.layer.masksToBounds = YES;
        [row addSubview:iv];
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(60, 0, row.frame.size.width - 70, rowH - 6)];
        label.text = app[@"name"];
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:15];
        [row addSubview:label];
        NSString *bid = app[@"bundleID"];
        [row addTarget:self action:@selector(rowTapped:)
            forControlEvents:UIControlEventTouchUpInside];
        row.tag = [self tagForBundleID:bid apps:apps];
        [scroll addSubview:row];
        y += rowH;
    }
    scroll.contentSize = CGSizeMake(scroll.frame.size.width, y);

    // 点面板外关闭。
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(dismissPicker)];
    tap.cancelsTouchesInView = NO;
    [self.overlay addGestureRecognizer:tap];
}

- (NSInteger)tagForBundleID:(NSString *)bid apps:(NSArray *)apps {
    for (NSInteger i = 0; i < (NSInteger)apps.count; i++) {
        if ([apps[(NSUInteger)i][@"bundleID"] isEqualToString:bid]) return i;
    }
    return 0;
}

- (void)dismissPicker {
    [self.pickerPanel removeFromSuperview];
    self.pickerPanel = nil;
}

- (void)rowTapped:(UIButton *)row {
    NSArray *apps = [self runningApps];
    NSInteger idx = row.tag;
    if (idx >= 0 && idx < (NSInteger)apps.count) {
        [self openApp:apps[(NSUInteger)idx][@"bundleID"]
                 name:apps[(NSUInteger)idx][@"name"]
                 icon:apps[(NSUInteger)idx][@"icon"]];
    }
    [self dismissPicker];
}

#pragma mark - 浮窗管理

- (void)openApp:(NSString *)bundleID name:(NSString *)name icon:(UIImage *)icon {
    AxsAppFloatConfig *config = [AxsAppFloatConfig axs_appfloat_shared];
    // 已开则前置。
    for (AxsAppFloatWindow *w in self.windows) {
        if ([w.bundleID isEqualToString:bundleID]) {
            [self.overlay bringSubviewToFront:w];
            return;
        }
    }
    // 超上限关最旧。
    NSInteger maxN = [config axs_appfloat_maxWindows];
    while ((NSInteger)self.windows.count >= maxN) {
        AxsAppFloatWindow *oldest = self.windows.firstObject;
        [self.windows removeObjectAtIndex:0];
        [oldest.host invalidate];
        [oldest removeFromSuperview];
    }
    AxsAppFloatWindow *win = [[AxsAppFloatWindow alloc]
        initWithBundleID:bundleID displayName:name iconImage:icon];
    win.frame = [self frameForWindowIndex:self.windows.count];
    [win updateChromeAlpha:[config axs_appfloat_windowAlpha]];
    [self.overlay addSubview:win];
    [self.windows addObject:win];
    __weak AxsAppFloatManager *weakSelf = self;
    win.onClose = ^(AxsAppFloatWindow *closed) {
        [weakSelf.windows removeObject:closed];
    };
}

- (CGRect)frameForWindowIndex:(NSUInteger)index {
    CGRect screen = self.overlay.bounds;
    CGFloat w = screen.size.width * 0.62;
    CGFloat h = screen.size.height * 0.52;
    CGFloat x = (screen.size.width - w) / 2.0 + (index == 0 ? -30 : 30);
    CGFloat y = screen.size.height * 0.16 + (index == 0 ? 0 : 40);
    return CGRectMake(x, y, w, h);
}

@end

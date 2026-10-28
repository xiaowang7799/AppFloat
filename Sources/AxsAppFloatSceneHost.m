#import "AxsAppFloatSceneHost.h"
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kAxsAppFloatRequester = @"AppFloat";

@interface AxsAppFloatSceneHost ()
@property (nonatomic, copy, readwrite) NSString *bundleID;
@property (nonatomic, strong, readwrite) UIView *hostView;
@property (nonatomic, assign, readwrite) BOOL live;
@property (nonatomic, strong) id scene;          // FBScene
@property (nonatomic, strong) id sceneHandle;    // SBApplicationSceneHandle
@property (nonatomic, strong) id retainedController;
@property (nonatomic, strong) id processAssertion;
@property (nonatomic, assign) CGSize canvasSize;
@end

@implementation AxsAppFloatSceneHost

- (instancetype)initWithBundleID:(NSString *)bundleID {
    self = [super init];
    if (self) {
        _bundleID = [bundleID copy];
        _canvasSize = [UIScreen mainScreen].bounds.size;
    }
    return self;
}

#pragma mark - 定位 SBApplication / FBScene

- (id)sbApplication {
    Class cls = NSClassFromString(@"SBApplicationController");
    if (!cls) return nil;
    @try {
        id ctrl = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(@"sharedInstance"));
        if (!ctrl) return nil;
        SEL sel = NSSelectorFromString(@"applicationWithBundleIdentifier:");
        return ((id (*)(id, SEL, id))objc_msgSend)(ctrl, sel, self.bundleID);
    } @catch (__unused NSException *e) { return nil; }
}

- (id)fbSceneFromHandle:(id)handle {
    if (!handle) return nil;
    for (NSString *name in @[@"sceneIfExists", @"scene", @"fbScene", @"_scene"]) {
        @try {
            SEL sel = NSSelectorFromString(name);
            id s = nil;
            if ([handle respondsToSelector:sel]) {
                s = ((id (*)(id, SEL))objc_msgSend)(handle, sel);
            } else {
                s = [handle valueForKey:name];
            }
            if (s) return s;
        } @catch (__unused NSException *e) {}
    }
    NSString *cn = NSStringFromClass([handle class]);
    if ([cn containsString:@"FBScene"] && ![cn containsString:@"Handle"]) return handle;
    return nil;
}

- (id)findFBScene {
    id app = [self sbApplication];
    if (!app) return nil;
    // 1) SBApplication.mainScene（经典路径）。
    for (NSString *key in @[@"mainScene", @"_mainScene", @"mainSceneHandle",
                             @"sceneHandle", @"primaryScene"]) {
        @try {
            id val = nil;
            SEL sel = NSSelectorFromString(key);
            if ([app respondsToSelector:sel]) {
                val = ((id (*)(id, SEL))objc_msgSend)(app, sel);
            } else {
                val = [app valueForKey:key];
            }
            if (val) {
                self.sceneHandle = val;
                id scene = [self fbSceneFromHandle:val];
                if (scene) return scene;
            }
        } @catch (__unused NSException *e) {}
    }
    // 2) scenes 集合里找匹配 bundle 的。
    @try {
        id scenes = nil;
        SEL sel = NSSelectorFromString(@"scenes");
        if ([app respondsToSelector:sel]) {
            scenes = ((id (*)(id, SEL))objc_msgSend)(app, sel);
        } else {
            scenes = [app valueForKey:@"scenes"];
        }
        NSArray *arr = nil;
        if ([scenes isKindOfClass:[NSSet class]]) arr = [scenes allObjects];
        else if ([scenes isKindOfClass:[NSArray class]]) arr = scenes;
        for (id s in arr) {
            @try {
                NSString *bid = [[s valueForKey:@"identifier"] description];
                if ([bid containsString:self.bundleID]) {
                    id inner = [self fbSceneFromHandle:s];
                    return inner ?: s;
                }
            } @catch (__unused NSException *e) {}
        }
        if (arr.count) {
            id inner = [self fbSceneFromHandle:arr.firstObject];
            return inner ?: arr.firstObject;
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

- (id)hostManagerFromScene:(id)scene {
    if (!scene) return nil;
    for (NSString *name in @[@"hostManager", @"contextHostManager",
                             @"_hostManager", @"_contextHostManager"]) {
        @try {
            SEL sel = NSSelectorFromString(name);
            id hm = nil;
            if ([scene respondsToSelector:sel]) {
                hm = ((id (*)(id, SEL))objc_msgSend)(scene, sel);
            } else {
                hm = [scene valueForKey:name];
            }
            if (hm) return hm;
        } @catch (__unused NSException *e) {}
    }
    @try {
        SEL sel = NSSelectorFromString(@"layerManager");
        id lm = [scene respondsToSelector:sel]
            ? ((id (*)(id, SEL))objc_msgSend)(scene, sel) : [scene valueForKey:@"layerManager"];
        for (NSString *name in @[@"hostManager", @"contextHostManager", @"_hostManager"]) {
            @try { id hm = [lm valueForKey:name]; if (hm) return hm; } @catch (__unused NSException *e) {}
        }
    } @catch (__unused NSException *e) {}
    return nil;
}

#pragma mark - 宿主视图

- (void)enableHostingOnManager:(id)hostManager {
    if (!hostManager) return;
    SEL en = NSSelectorFromString(@"enableHostingForRequester:orderFront:");
    if ([hostManager respondsToSelector:en]) {
        NSMethodSignature *sig = [hostManager methodSignatureForSelector:en];
        if (sig) {
            @try {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = hostManager;
                inv.selector = en;
                NSString *req = kAxsAppFloatRequester;
                [inv setArgument:&req atIndex:2];
                BOOL order = YES;
                [inv setArgument:&order atIndex:3];
                [inv invoke];
                return;
            } @catch (__unused NSException *e) {}
        }
    }
    SEL en2 = NSSelectorFromString(@"enableAndOrderFrontForRequester:");
    if ([hostManager respondsToSelector:en2]) {
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(hostManager, en2, kAxsAppFloatRequester);
        } @catch (__unused NSException *e) {}
    }
}

- (UIView *)hostViewFromManager:(id)hostManager {
    if (!hostManager) return nil;
    [self enableHostingOnManager:hostManager];
    SEL sel = NSSelectorFromString(@"hostViewForRequester:enableAndOrderFront:");
    if ([hostManager respondsToSelector:sel]) {
        NSMethodSignature *sig = [hostManager methodSignatureForSelector:sel];
        if (sig) {
            @try {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                inv.target = hostManager;
                inv.selector = sel;
                NSString *req = kAxsAppFloatRequester;
                [inv setArgument:&req atIndex:2];
                BOOL order = YES;
                [inv setArgument:&order atIndex:3];
                [inv invoke];
                __unsafe_unretained UIView *view = nil;
                [inv getReturnValue:&view];
                if ([view isKindOfClass:[UIView class]]) return view;
            } @catch (__unused NSException *e) {}
        }
    }
    for (NSString *name in @[@"hostViewForRequester:", @"contextHostViewForRequester:",
                             @"_hostViewForRequester:"]) {
        SEL s2 = NSSelectorFromString(name);
        if (![hostManager respondsToSelector:s2]) continue;
        @try {
            UIView *v = ((id (*)(id, SEL, id))objc_msgSend)(hostManager, s2, kAxsAppFloatRequester);
            if ([v isKindOfClass:[UIView class]]) return v;
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

- (UIView *)hostViewFromHandleFallback {
    id handle = self.sceneHandle;
    if (!handle) return nil;
    CGSize s = self.canvasSize;
    for (NSString *name in @[@"newSceneViewControllerForReferenceSize:orientation:hostRequester:",
                             @"newSceneViewControllerForReferenceSize:"]) {
        SEL sel = NSSelectorFromString(name);
        if (![handle respondsToSelector:sel]) continue;
        NSMethodSignature *sig = [handle methodSignatureForSelector:sel];
        if (!sig) continue;
        @try {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            inv.target = handle;
            inv.selector = sel;
            [inv setArgument:&s atIndex:2];
            if (sig.numberOfArguments >= 4) { long long o = 1; [inv setArgument:&o atIndex:3]; }
            if (sig.numberOfArguments >= 5) {
                NSString *req = kAxsAppFloatRequester;
                [inv setArgument:&req atIndex:4];
            }
            [inv invoke];
            __unsafe_unretained id result = nil;
            [inv getReturnValue:&result];
            if ([result isKindOfClass:[UIView class]]) return result;
            if (result && [result respondsToSelector:@selector(view)]) {
                self.retainedController = result;
                UIView *v = ((UIView *(*)(id, SEL))objc_msgSend)(result, @selector(view));
                if ([v isKindOfClass:[UIView class]]) return v;
            }
        } @catch (__unused NSException *e) {}
    }
    return nil;
}

#pragma mark - 场景状态

- (void)applyForeground:(BOOL)foreground {
    id scene = self.scene;
    if (!scene) return;
    @try {
        id settings = nil;
        for (NSString *name in @[@"settings", @"mutableSettings", @"_mutableSettings"]) {
            SEL sel = NSSelectorFromString(name);
            id src = [scene respondsToSelector:sel]
                ? ((id (*)(id, SEL))objc_msgSend)(scene, sel) : [scene valueForKey:name];
            if (src) { settings = [src respondsToSelector:@selector(mutableCopy)] ? [src mutableCopy] : src; break; }
        }
        if (!settings) return;
        SEL setFg = NSSelectorFromString(@"setForeground:");
        if ([settings respondsToSelector:setFg]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(settings, setFg, foreground);
        }
        SEL setBg = NSSelectorFromString(@"setBackgrounded:");
        if ([settings respondsToSelector:setBg]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(settings, setBg, !foreground);
        }
        if (foreground) {
            SEL setReasons = NSSelectorFromString(@"setDeactivationReasons:");
            if ([settings respondsToSelector:setReasons]) {
                ((void (*)(id, SEL, unsigned long long))objc_msgSend)(settings, setReasons, 0);
            }
        }
        for (NSString *name in @[@"updateSettings:withTransitionContext:",
                                 @"updateSettings:"]) {
            SEL sel = NSSelectorFromString(name);
            if (![scene respondsToSelector:sel]) continue;
            @try {
                if ([name containsString:@"withTransitionContext"]) {
                    ((void (*)(id, SEL, id, id))objc_msgSend)(scene, sel, settings, nil);
                } else {
                    ((void (*)(id, SEL, id))objc_msgSend)(scene, sel, settings);
                }
                return;
            } @catch (__unused NSException *e) {}
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - 保活（RBSAssertion）

- (void)acquireAssertionIfNeeded {
    if (self.processAssertion) return;
    int pid = 0;
    id app = [self sbApplication];
    @try {
        SEL pidSel = NSSelectorFromString(@"pid");
        if ([app respondsToSelector:pidSel]) {
            pid = ((int (*)(id, SEL))objc_msgSend)(app, pidSel);
        }
    } @catch (__unused NSException *e) {}
    if (pid <= 0) return;
    Class targetCls = NSClassFromString(@"RBSTarget");
    Class attrCls = NSClassFromString(@"RBSLegacyAttribute");
    Class assertCls = NSClassFromString(@"RBSAssertion");
    if (!targetCls || !attrCls || !assertCls) return;
    @try {
        SEL tSel = NSSelectorFromString(@"targetWithPid:");
        id target = ((id (*)(id, SEL, int))objc_msgSend)(targetCls, tSel, pid);
        NSUInteger flags = (1 << 0) | (1 << 1) | (1 << 3) | (1 << 5);
        SEL aSel = NSSelectorFromString(@"attributeWithReason:flags:");
        id attr = ((id (*)(id, SEL, NSUInteger, NSUInteger))objc_msgSend)(attrCls, aSel, 7, flags);
        if (!target || !attr) return;
        id assertion = [assertCls alloc];
        SEL iSel = NSSelectorFromString(@"initWithExplanation:target:attributes:");
        assertion = ((id (*)(id, SEL, id, id, id))objc_msgSend)(assertion, iSel,
            @"AppFloat live host", target, @[attr]);
        SEL acq = NSSelectorFromString(@"acquireWithError:");
        NSError *error = nil;
        if (assertion && ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(assertion, acq, &error)) {
            self.processAssertion = assertion;
        }
    } @catch (__unused NSException *e) {}
}

#pragma mark - Public

- (BOOL)attachToContainer:(UIView *)container {
    if (!container) return NO;
    if (self.hostView && self.hostView.superview == container) {
        self.live = YES;
        return YES;
    }
    id scene = [self findFBScene];
    self.scene = scene;
    if (!scene) {
        self.statusText = @"应用未在后台运行（先打开一次该 App）";
        return NO;
    }
    [self applyForeground:YES];
    id hostManager = [self hostManagerFromScene:scene];
    UIView *hv = [self hostViewFromManager:hostManager] ?: [self hostViewFromHandleFallback];
    if (!hv) {
        self.statusText = [NSString stringWithFormat:@"找到场景但无宿主视图（iOS %@）",
                           [UIDevice currentDevice].systemVersion];
        return NO;
    }
    [self.hostView removeFromSuperview];
    self.hostView = hv;
    hv.autoresizingMask = UIViewAutoresizingNone;
    hv.clipsToBounds = YES;
    [container addSubview:hv];
    [self layoutInContainer:container];
    self.live = YES;
    self.statusText = @"已连接画面";
    [self acquireAssertionIfNeeded];
    return YES;
}

- (void)layoutInContainer:(UIView *)container {
    if (!self.hostView || !container) return;
    CGSize target = container.bounds.size;
    CGSize canvas = self.canvasSize;
    if (canvas.width < 2 || canvas.height < 2) canvas = [UIScreen mainScreen].bounds.size;
    if (target.width < 1 || target.height < 1) return;
    self.hostView.transform = CGAffineTransformIdentity;
    self.hostView.bounds = CGRectMake(0, 0, canvas.width, canvas.height);
    self.hostView.center = CGPointMake(target.width / 2.0, target.height / 2.0);
    self.hostView.transform = CGAffineTransformMakeScale(target.width / canvas.width,
                                                         target.height / canvas.height);
}

- (void)keepAlive {
    if (!self.live || !self.scene) return;
    [self applyForeground:YES];
    [self acquireAssertionIfNeeded];
}

- (void)invalidate {
    if (self.scene) {
        [self applyForeground:NO];
        id hostManager = [self hostManagerFromScene:self.scene];
        for (NSString *name in @[@"invalidateHostViewForRequester:",
                                 @"disableHostingForRequester:"]) {
            SEL sel = NSSelectorFromString(name);
            if (![hostManager respondsToSelector:sel]) continue;
            @try {
                ((void (*)(id, SEL, id))objc_msgSend)(hostManager, sel, kAxsAppFloatRequester);
            } @catch (__unused NSException *e) {}
        }
    }
    SEL inv = NSSelectorFromString(@"invalidate");
    if ([self.hostView respondsToSelector:inv]) {
        @try { ((void (*)(id, SEL))objc_msgSend)(self.hostView, inv); } @catch (__unused NSException *e) {}
    }
    [self.hostView removeFromSuperview];
    if (self.processAssertion) {
        SEL inv2 = NSSelectorFromString(@"invalidate");
        @try { ((void (*)(id, SEL))objc_msgSend)(self.processAssertion, inv2); } @catch (__unused NSException *e) {}
    }
    self.processAssertion = nil;
    self.retainedController = nil;
    self.hostView = nil;
    self.scene = nil;
    self.sceneHandle = nil;
    self.live = NO;
}

@end

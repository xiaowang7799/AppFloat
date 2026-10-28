//
//  MHHandle.m
//  MessageHub
//
//  Created by Will Smillie on 1/18/19.
//

#import "POHandle.h"
#import <QuartzCore/QuartzCore.h>
#import "PullOverViewController.h"

#import "POApplicationHelper.h"

#define PO_HANDLE_DEFAULT_SIZE 34.0
#define PO_HANDLE_MINIMUM_SIZE 34.0
#define PO_HANDLE_MAXIMUM_SIZE 50.0
#define PO_HANDLE_DEFAULT_NUB_HIDDEN_PERCENTAGE 67.0
#define PO_HANDLE_MAXIMUM_NUB_HIDDEN_PERCENTAGE 80.0
#define PO_HANDLE_MINIMUM_TOUCH_SIZE 52.0

@interface POHandle () <UIGestureRecognizerDelegate> {
    UILabel *messageLabel;
    UIVisualEffectView *blurView;
    UIView *butterflyCarrier;
    UIImageView *butterflyView;
    CAEmitterLayer *sparkleLayer;
    CADisplayLink *flyLink;
    CGFloat flyPhaseX, flyPhaseY;
    CGFloat flyVX, flyVY;
    CFTimeInterval butterflyRestUntil;
    NSInteger butterflyPhase;   // 0=在家 1=漫游 2=进岛 3=停靠
    BOOL butterflyShown;
    BOOL butterflyFlying;
    UITapGestureRecognizer *butterflyTap;
    UITapGestureRecognizer *_tapGestureRecognizer;
    UILongPressGestureRecognizer *quickSwitchLongPress;
    UIPanGestureRecognizer *_panelPanGestureRecognizer;
    CGPoint tapTouchStartPoint;
    BOOL hasTapTouchStartPoint;
}

-(void)applyCurrentPresentationAnimated:(BOOL)animated;

@end

// 彩虹渐变蝴蝶（手柄缩回后的形态）。
static UIImage *POButterflyImage(void) {
    static UIImage *img = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGFloat s = 84.0;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        CGFloat cx = s / 2.0, cy = s / 2.0;
        // 四片翅膀：上大下小，对称。
        for (int side = -1; side <= 1; side += 2) {
            // 上翅（洋红→橙）。
            UIBezierPath *up = [UIBezierPath bezierPath];
            [up moveToPoint:CGPointMake(cx, cy - 2)];
            [up addQuadCurveToPoint:CGPointMake(cx + side * 34, cy - 30)
                       controlPoint:CGPointMake(cx + side * 26, cy - 32)];
            [up addQuadCurveToPoint:CGPointMake(cx + side * 30, cy + 2)
                       controlPoint:CGPointMake(cx + side * 38, cy - 2)];
            [up closePath];
            CGFloat compsUp[] = {1.0, 0.30, 0.62, 0.95,  1.0, 0.62, 0.18, 0.9};
            CGFloat locs[] = {0, 1};
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGGradientRef g = CGGradientCreateWithColorComponents(space, compsUp, locs, 2);
            CGContextSaveGState(ctx);
            [up addClip];
            CGContextDrawLinearGradient(ctx, g, CGPointMake(cx, cy - 30), CGPointMake(cx, cy), 0);
            CGContextRestoreGState(ctx);
            CGGradientRelease(g);
            [[UIColor colorWithWhite:1 alpha:0.85] setStroke];
            up.lineWidth = 1.6;
            [up stroke];
            // 下翅（紫→青）。
            UIBezierPath *dn = [UIBezierPath bezierPath];
            [dn moveToPoint:CGPointMake(cx, cy + 1)];
            [dn addQuadCurveToPoint:CGPointMake(cx + side * 26, cy + 30)
                        controlPoint:CGPointMake(cx + side * 30, cy + 14)];
            [dn addQuadCurveToPoint:CGPointMake(cx + side * 8, cy + 4)
                        controlPoint:CGPointMake(cx + side * 14, cy + 12)];
            [dn closePath];
            CGFloat compsDn[] = {0.55, 0.30, 1.0, 0.95,  0.15, 0.80, 1.0, 0.9};
            CGGradientRef g2 = CGGradientCreateWithColorComponents(space, compsDn, locs, 2);
            CGContextSaveGState(ctx);
            [dn addClip];
            CGContextDrawLinearGradient(ctx, g2, CGPointMake(cx, cy + 30), CGPointMake(cx, cy), 0);
            CGContextRestoreGState(ctx);
            CGGradientRelease(g2);
            CGColorSpaceRelease(space);
            [dn stroke];
            // 翅膀亮片。
            [[UIColor colorWithWhite:1 alpha:0.9] setFill];
            for (int d = 0; d < 3; d++) {
                CGFloat dx = cx + side * (14 + d * 7);
                CGFloat dy = cy - 18 + d * 6;
                [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(dx, dy, 3.2, 3.2)] fill];
            }
        }
        // 身体 + 触角。
        [[UIColor colorWithWhite:0.12 alpha:1] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(cx - 2.2, cy - 16, 4.4, 32) cornerRadius:2.2] fill];
        [[UIColor colorWithWhite:0.12 alpha:0.9] setStroke];
        UIBezierPath *ant1 = [UIBezierPath bezierPath];
        [ant1 moveToPoint:CGPointMake(cx, cy - 15)];
        [ant1 addQuadCurveToPoint:CGPointMake(cx - 9, cy - 26) controlPoint:CGPointMake(cx - 6, cy - 22)];
        UIBezierPath *ant2 = [UIBezierPath bezierPath];
        [ant2 moveToPoint:CGPointMake(cx, cy - 15)];
        [ant2 addQuadCurveToPoint:CGPointMake(cx + 9, cy - 26) controlPoint:CGPointMake(cx + 6, cy - 22)];
        ant1.lineWidth = ant2.lineWidth = 1.6;
        [ant1 stroke];
        [ant2 stroke];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

// 四角星闪粉 sprite。
static UIImage *POStarImage(void) {
    static UIImage *img = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGFloat s = 16.0;
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), NO, 0);
        [[UIColor whiteColor] setFill];
        UIBezierPath *star = [UIBezierPath bezierPath];
        [star moveToPoint:CGPointMake(s / 2, 0)];
        [star addQuadCurveToPoint:CGPointMake(s, s / 2) controlPoint:CGPointMake(s / 2 + 1.5, s / 2 - 1.5)];
        [star addQuadCurveToPoint:CGPointMake(s / 2, s) controlPoint:CGPointMake(s / 2 + 1.5, s / 2 + 1.5)];
        [star addQuadCurveToPoint:CGPointMake(0, s / 2) controlPoint:CGPointMake(s / 2 - 1.5, s / 2 + 1.5)];
        [star addQuadCurveToPoint:CGPointMake(s / 2, 0) controlPoint:CGPointMake(s / 2 - 1.5, s / 2 - 1.5)];
        [star fill];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return img;
}

@implementation POHandle

-(CGFloat)handleSize{
    id configuredValue = [POApplicationHelper settings][@"handleSize"];
    CGFloat size = configuredValue ? [configuredValue doubleValue] : PO_HANDLE_DEFAULT_SIZE;
    if (size <= 0) {
        size = PO_HANDLE_DEFAULT_SIZE;
    }
    return MIN(MAX(size, PO_HANDLE_MINIMUM_SIZE), PO_HANDLE_MAXIMUM_SIZE);
}

-(CGFloat)nubHiddenPercentage{
    id configuredValue = [POApplicationHelper settings][@"nubHiddenPercentage"];
    CGFloat percentage = configuredValue ? [configuredValue doubleValue] : PO_HANDLE_DEFAULT_NUB_HIDDEN_PERCENTAGE;
    if (percentage < 0) {
        percentage = PO_HANDLE_DEFAULT_NUB_HIDDEN_PERCENTAGE;
    }
    return MIN(MAX(percentage, 0), PO_HANDLE_MAXIMUM_NUB_HIDDEN_PERCENTAGE);
}

-(CGFloat)fullCornerRadius{
    return CGRectGetWidth(self.bounds) * (8.0 / PO_HANDLE_DEFAULT_SIZE);
}

-(CGFloat)nubbedCornerRadius{
    return CGRectGetWidth(self.bounds) * (6.0 / PO_HANDLE_DEFAULT_SIZE);
}

-(BOOL)usesNubbedPresentation{
    return self.layoutMode == POHandleLayoutModeVerticalRail && self.isNubbed;
}

-(CGFloat)nubbedOriginX{
    CGFloat containerWidth = CGRectGetWidth(self.superview.bounds);
    if (containerWidth <= 0) {
        containerWidth = 50.0;
    }
    CGFloat visibleWidth = CGRectGetWidth(self.bounds) * (1.0 - [self nubHiddenPercentage] / 100.0);
    return containerWidth - visibleWidth;
}

-(void)applyNubbedPosition{
    CGRect frame = self.frame;
    frame.origin.x = [self nubbedOriginX];
    self.frame = frame;
}

-(void)applyCustomStyle{
    NSDictionary *settings = [POApplicationHelper settings];
    // 整体透明度。
    id opacity = settings[@"handleOpacity"];
    self.alpha = opacity ? MIN(MAX([opacity doubleValue], 0.3), 1.0) : 1.0;
    // 彩色蒙层（毛玻璃上叠色调）。
    BOOL tintOn = [settings[@"handleTintOn"] boolValue];
    if (tintOn) {
        double hue = [settings[@"handleTintHue"] doubleValue];
        double ta = MIN(MAX([settings[@"handleTintAlpha"] doubleValue], 0.0), 1.0);
        blurView.contentView.backgroundColor =
            [UIColor colorWithHue:MIN(MAX(hue, 0.0), 1.0) saturation:0.65 brightness:1.0 alpha:ta];
    } else {
        blurView.contentView.backgroundColor = [UIColor clearColor];
    }
    // 阴影开关。
    BOOL shadowOn = settings[@"handleShadowOn"] ? [settings[@"handleShadowOn"] boolValue] : YES;
    self.layer.shadowOpacity = shadowOn ? 0.32f : 0.0f;
}

-(void)applyHandleSize{
    CGFloat size = [self handleSize];
    CGRect frame = self.frame;
    frame.size = CGSizeMake(size, size);
    self.frame = frame;
    id cornerSetting = [POApplicationHelper settings][@"handleCornerScale"];
    double cornerScale = cornerSetting ? MIN(MAX([cornerSetting doubleValue], 0.2), 2.5) : 1.0;
    self.layer.cornerRadius = [self fullCornerRadius] * cornerScale;

    CGFloat iconSize = MAX(0, size - 10.0);
    self.imageView.frame = CGRectMake((CGRectGetWidth(self.bounds) - iconSize) / 2.0,
                                      (CGRectGetHeight(self.bounds) - iconSize) / 2.0,
                                      iconSize,
                                      iconSize);
    blurView.frame = self.bounds;
    blurView.layer.cornerRadius = ([self usesNubbedPresentation] ? [self nubbedCornerRadius] : [self fullCornerRadius]) * cornerScale;
    [self applyCustomStyle];
    [self updateButterflyForNubbed:[self usesNubbedPresentation]];
}

-(instancetype)initWithController:(id)hubController{
    if (self = [super initWithFrame:CGRectMake(0, 0, PO_HANDLE_DEFAULT_SIZE, PO_HANDLE_DEFAULT_SIZE)]) {
        self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.04];
        self.layer.cornerRadius = 8;
        [self.layer setShadowColor:[UIColor blackColor].CGColor];
        [self.layer setShadowOpacity:0.32];
        [self.layer setShadowRadius:3.5];
        [self.layer setShadowOffset:CGSizeMake(0, 0)];

        _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
        _tapGestureRecognizer.delegate = self;
        [self addGestureRecognizer:_tapGestureRecognizer];

        quickSwitchLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        quickSwitchLongPress.minimumPressDuration = .3f;
        quickSwitchLongPress.delegate = self;
        quickSwitchLongPress.cancelsTouchesInView = NO;
        [self addGestureRecognizer:quickSwitchLongPress];
        [_tapGestureRecognizer requireGestureRecognizerToFail:quickSwitchLongPress];
        _panelPanGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                                            action:@selector(panelPan:)];
        _panelPanGestureRecognizer.delegate = self;
        _panelPanGestureRecognizer.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:_panelPanGestureRecognizer];
        [_panelPanGestureRecognizer requireGestureRecognizerToFail:quickSwitchLongPress];
        [_tapGestureRecognizer requireGestureRecognizerToFail:_panelPanGestureRecognizer];
        
        UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
        blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
        blurView.frame = self.bounds;
        blurView.userInteractionEnabled = NO;
        blurView.layer.cornerRadius = 8;
        blurView.layer.cornerCurve = kCACornerCurveContinuous;
        blurView.clipsToBounds = YES;
        [self addSubview:blurView];
        

        self.imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        [self.imageView setBackgroundColor:[UIColor clearColor]];
        self.imageView.contentMode = UIViewContentModeScaleAspectFit;
        self.imageView.clipsToBounds = YES;
        self.imageView.tintColor = [UIColor lightGrayColor];
        [self addSubview:self.imageView];
        self.layoutMode = POHandleLayoutModeVerticalRail;
        [self applyHandleSize];
        
        [self setIsNubbed:[[NSUserDefaults standardUserDefaults] boolForKey:@"isNubbed"]];
    }
    return self;
}

-(void)setIsNubbed:(BOOL)isNubbed{
    _isNubbed = isNubbed;
    [[NSUserDefaults standardUserDefaults] setBool:isNubbed forKey:@"isNubbed"];
    [self applyCurrentPresentationAnimated:YES];
}

-(void)setLayoutMode:(POHandleLayoutMode)layoutMode{
    if (_layoutMode == layoutMode) {
        return;
    }
    _layoutMode = layoutMode;
    [self applyCurrentPresentationAnimated:NO];
}

-(void)buildButterflyIfNeeded{
    if (butterflyCarrier) return;
    butterflyCarrier = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    butterflyCarrier.backgroundColor = [UIColor clearColor];
    butterflyCarrier.userInteractionEnabled = NO;   // 回家状态：点击穿透给手柄
    butterflyView = [[UIImageView alloc] initWithImage:POButterflyImage()];
    butterflyView.frame = butterflyCarrier.bounds;
    butterflyView.contentMode = UIViewContentModeScaleAspectFit;
    [butterflyCarrier addSubview:butterflyView];
    // 翅膀扇动。
    CAKeyframeAnimation *flap = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale.x"];
    flap.values = @[@1.0, @0.68, @1.0];
    flap.duration = 1.15;
    flap.repeatCount = HUGE_VALF;
    flap.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [butterflyView.layer addAnimation:flap forKey:@"po_flap"];
    // 亮晶晶闪粉（加法混合星尘，随载体走）。
    sparkleLayer = [CAEmitterLayer layer];
    sparkleLayer.frame = butterflyCarrier.bounds;
    sparkleLayer.emitterShape = kCAEmitterLayerRectangle;
    sparkleLayer.renderMode = kCAEmitterLayerAdditive;
    sparkleLayer.emitterPosition = CGPointMake(22, 22);
    sparkleLayer.emitterSize = CGSizeMake(38, 38);
    CAEmitterCell *star = [CAEmitterCell emitterCell];
    star.contents = (__bridge id)POStarImage().CGImage;
    star.birthRate = 2.6f;
    star.lifetime = 1.15f;
    star.velocity = 12.0f;
    star.velocityRange = 9.0f;
    star.emissionRange = M_PI * 2;
    star.scale = 0.30f;
    star.scaleRange = 0.18f;
    star.alphaSpeed = -0.85f;
    star.spin = 1.2f;
    star.spinRange = 2.0f;
    sparkleLayer.emitterCells = @[star];
    sparkleLayer.opacity = 0;
    [butterflyCarrier.layer addSublayer:sparkleLayer];
    // 飞行中点击 → 回家。
    butterflyTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(butterflyTapped)];
    [butterflyCarrier addGestureRecognizer:butterflyTap];
    butterflyCarrier.hidden = YES;
    [self addSubview:butterflyCarrier];
}

// 蝴蝶在家（缩回点）的局部坐标帧。
-(CGRect)butterflyHomeFrame{
    CGFloat size = MIN(CGRectGetWidth(self.bounds) * 1.25, 42.0);
    CGFloat visible = CGRectGetWidth(self.bounds) * (1.0 - [self nubHiddenPercentage] / 100.0);
    return CGRectMake(visible - size / 2.0 - 2.0, (CGRectGetHeight(self.bounds) - size) / 2.0, size, size);
}

-(void)updateButterflyForNubbed:(BOOL)nubbed{
    [self buildButterflyIfNeeded];
    BOOL on = nubbed && [[POApplicationHelper settings][@"nubButterflyOn"] boolValue];
    BOOL flyFree = [[POApplicationHelper settings][@"butterflyFlyFree"] boolValue];
    if (on) {
        butterflyCarrier.hidden = NO;
        sparkleLayer.opacity = 1.0f;
        blurView.alpha = 0.0;
        self.imageView.alpha = 0.0;
        // 只在状态翻转时驱动飞行，避免重复调用打断回家。
        if (!butterflyShown) {
            butterflyShown = YES;
            if (flyFree) {
                [self butterflyTakeOff];
            } else {
                butterflyCarrier.transform = CGAffineTransformIdentity;
                butterflyCarrier.frame = [self butterflyHomeFrame];
                butterflyCarrier.userInteractionEnabled = NO;
            }
        } else if (!flyFree && butterflyPhase != 0) {
            [self butterflyFlyHome];
        } else if (butterflyPhase == 0) {
            butterflyCarrier.transform = CGAffineTransformIdentity;
            butterflyCarrier.frame = [self butterflyHomeFrame];
        }
    } else {
        butterflyShown = NO;
        [self stopFlight];
        butterflyCarrier.hidden = YES;
        butterflyCarrier.userInteractionEnabled = NO;
        sparkleLayer.opacity = 0.0f;
        blurView.alpha = 1.0;
        self.imageView.alpha = 1.0;
    }
}

#pragma mark - 蝴蝶飞行（0=在家 1=漫游 2=进岛 3=停靠）

// 灵动岛停靠点（岛中心近似值）。
-(CGPoint)butterflyIslandPoint{
    UIWindow *w = self.window;
    if (!w) return CGPointMake(200, 40);
    CGFloat top = w.safeAreaInsets.top;
    CGFloat y = MAX(26.0, top - 27.0);
    return CGPointMake(CGRectGetMidX(w.bounds), y);
}

-(void)butterflyTakeOff{
    if (butterflyPhase != 0 || !self.window) return;
    butterflyPhase = 1;
    // 换到窗口层。center 驱动——frame+transform 会互相打架（飞走 bug 根因）。
    CGRect start = [self convertRect:butterflyCarrier.frame toView:self.window];
    [self.window addSubview:butterflyCarrier];
    butterflyCarrier.transform = CGAffineTransformIdentity;
    butterflyCarrier.bounds = CGRectMake(0, 0, 44, 44);
    butterflyCarrier.center = CGPointMake(CGRectGetMidX(start), CGRectGetMidY(start));
    butterflyCarrier.userInteractionEnabled = YES;   // 飞行/停靠中点击=回家
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    flyPhaseX = ((CGFloat)arc4random() / UINT32_MAX) * 6.28f;
    flyPhaseY = ((CGFloat)arc4random() / UINT32_MAX) * 6.28f;
    flyVX = ((CGFloat)arc4random() / UINT32_MAX) * 2.0f - 1.0f;
    flyVY = ((CGFloat)arc4random() / UINT32_MAX) * 2.0f - 1.0f;
    double flight = MIN(MAX([[[POApplicationHelper settings] objectForKey:@"butterflyFlightTime"] doubleValue], 1), 20);
    butterflyRestUntil = CACurrentMediaTime() + flight;   // 漫游结束时刻
    if (!flyLink) {
        flyLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(butterflyFlyTick)];
        [flyLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    flyLink.paused = NO;
}

-(void)butterflyFlyTick{
    if (butterflyPhase != 1 || !butterflyCarrier.superview) { flyLink.paused = YES; return; }
    NSDictionary *settings = [POApplicationHelper settings];
    UIView *canvas = butterflyCarrier.superview;
    CGRect b = canvas.bounds;
    // 漫游时长到 → 飞向灵动岛停靠。
    if (CACurrentMediaTime() >= butterflyRestUntil) {
        [self butterflyApproachIsland];
        return;
    }
    // 正弦扰动漫游 + 速度/高度设置（高度 1–20，20=满屏）。
    flyPhaseX += 0.028f;
    flyPhaseY += 0.023f;
    flyVX += (CGFloat)(sin(flyPhaseX) * 0.09);
    flyVY += (CGFloat)(cos(flyPhaseY) * 0.09);
    double speedSetting = MIN(MAX([settings[@"butterflyFlySpeed"] doubleValue], 0.5), 3.0);
    CGFloat speed = (CGFloat)(1.6 * speedSetting);
    CGFloat mag = (CGFloat)sqrt(flyVX * flyVX + flyVY * flyVY);
    if (mag > 0.001) { flyVX = flyVX / mag * speed; flyVY = flyVY / mag * speed; }
    CGPoint c = butterflyCarrier.center;
    c.x += flyVX;
    c.y += flyVY;
    CGFloat halfW = butterflyCarrier.bounds.size.width / 2.0 + 18.0;
    CGFloat minY = 78.0;   // 状态栏下
    double height = MIN(MAX([settings[@"butterflyFlyHeight"] doubleValue], 1), 20) / 20.0;
    CGFloat maxY = minY + (CGFloat)((b.size.height - minY - 24.0) * height);
    if (c.x < halfW) { c.x = halfW; flyVX = fabs(flyVX); }
    if (c.x > b.size.width - halfW) { c.x = b.size.width - halfW; flyVX = -fabs(flyVX); }
    if (c.y < minY) { c.y = minY; flyVY = fabs(flyVY); }
    if (c.y > maxY) { c.y = maxY; flyVY = -fabs(flyVY); }
    butterflyCarrier.center = c;
    if (fabs(flyVX) > 0.05 || fabs(flyVY) > 0.05) {
        CGFloat angle = (CGFloat)atan2(flyVY, flyVX) + (CGFloat)M_PI_2;
        butterflyCarrier.transform = CGAffineTransformMakeRotation(angle);
    }
}

// 漫游结束 → 滑翔到灵动岛停靠。
-(void)butterflyApproachIsland{
    butterflyPhase = 2;
    flyLink.paused = YES;
    CGPoint island = [self butterflyIslandPoint];
    CGFloat angle = (CGFloat)atan2(island.y - butterflyCarrier.center.y,
                                   island.x - butterflyCarrier.center.x) + (CGFloat)M_PI_2;
    [UIView animateWithDuration:0.9
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self->butterflyCarrier.center = island;
        self->butterflyCarrier.transform = CGAffineTransformMakeRotation(angle);
    } completion:^(BOOL done) {
        if (!done || self->butterflyPhase != 2) return;
        self->butterflyPhase = 3;   // 停靠灵动岛
        double rest = MIN(MAX([[[POApplicationHelper settings] objectForKey:@"butterflyRestInterval"] doubleValue], 1), 20);
        [self performSelector:@selector(butterflyPerchEnd) withObject:nil afterDelay:rest];
    }];
}

-(void)butterflyPerchEnd{
    if (butterflyPhase != 3) return;
    if ([self usesNubbedPresentation] &&
        [[POApplicationHelper settings][@"nubButterflyOn"] boolValue] &&
        [[POApplicationHelper settings][@"butterflyFlyFree"] boolValue]) {
        [self butterflyTakeOff];
    }
}

// 点击蝴蝶 → 飞回缩回点。
-(void)butterflyFlyHome{
    [self stopFlight];
    CGRect target = [self butterflyHomeFrame];
    if (butterflyCarrier.superview != self) {
        CGRect start = [self convertRect:butterflyCarrier.frame fromView:butterflyCarrier.superview];
        [self addSubview:butterflyCarrier];
        butterflyCarrier.transform = CGAffineTransformIdentity;
        butterflyCarrier.frame = start;
        [UIView animateWithDuration:0.5
                              delay:0
                            options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{
            self->butterflyCarrier.transform = CGAffineTransformIdentity;
            self->butterflyCarrier.frame = target;
        } completion:nil];
    } else {
        butterflyCarrier.transform = CGAffineTransformIdentity;
        butterflyCarrier.frame = target;
    }
    butterflyCarrier.userInteractionEnabled = NO;   // 回家后点击穿透（=拉面板）
    [self scheduleButterflyRetakeoff];
}

-(void)butterflyTapped{
    if (butterflyPhase != 0) {
        [self butterflyFlyHome];
    }
}

// 飞行/停靠中命中检测（给 POXWindow 点击白名单用）。
-(UIView *)butterflyHitViewForWindowPoint:(CGPoint)point{
    if (butterflyPhase == 0 || butterflyCarrier.hidden || !butterflyCarrier.superview) return nil;
    CGPoint p = [butterflyCarrier.superview convertPoint:point fromView:nil];
    return [butterflyCarrier pointInside:[butterflyCarrier convertPoint:p fromView:butterflyCarrier.superview]
                               withEvent:nil] ? butterflyCarrier : nil;
}

// 回家后按「停歇间隔」自动再起飞。
-(void)scheduleButterflyRetakeoff{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(butterflyRetakeoffIfIdle) object:nil];
    double interval = MIN(MAX([[[POApplicationHelper settings] objectForKey:@"butterflyRestInterval"] doubleValue], 1), 20);
    [self performSelector:@selector(butterflyRetakeoffIfIdle) withObject:nil afterDelay:interval];
}
-(void)butterflyRetakeoffIfIdle{
    if (butterflyPhase != 0) return;
    if (![self usesNubbedPresentation]) return;
    if ([[POApplicationHelper settings][@"nubButterflyOn"] boolValue] &&
        [[POApplicationHelper settings][@"butterflyFlyFree"] boolValue]) {
        [self butterflyTakeOff];
    }
}

-(void)stopFlight{
    butterflyPhase = 0;
    flyLink.paused = YES;
    butterflyCarrier.transform = CGAffineTransformIdentity;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

-(void)dealloc{
    [flyLink invalidate];
    flyLink = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

-(void)applyCurrentPresentationAnimated:(BOOL)animated{
    void (^changes)(void) = ^{
        if ([self usesNubbedPresentation]) {
            [self applyNubbedPosition];
            self->blurView.layer.cornerRadius = [self nubbedCornerRadius];
        } else {
            CGRect frame = self.frame;
            frame.origin.x = self.restingOriginX;
            self.frame = frame;
            self->blurView.layer.cornerRadius = [self fullCornerRadius];
        }
        [self updateButterflyForNubbed:[self usesNubbedPresentation]];
    };
    if (animated) {
        [UIView animateWithDuration:0.3 animations:changes];
    } else {
        changes();
    }
}

-(void)refreshHandleSizeAnimated:(BOOL)animated{
    void (^changes)(void) = ^{
        [self applyHandleSize];
    };
    if (animated) {
        [UIView animateWithDuration:0.2 animations:changes];
    } else {
        changes();
    }
}

-(void)refreshNubbedPositionAnimated:(BOOL)animated{
    [self applyCurrentPresentationAnimated:animated];
}

-(void)layoutSubviews{
    [super layoutSubviews];
    blurView.frame = self.bounds;
}

-(BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event{
    if (self.layoutMode == POHandleLayoutModeLandscapeFixedBottomLeft) {
        CGFloat horizontalInset = MAX(5.0, (PO_HANDLE_MINIMUM_TOUCH_SIZE - CGRectGetWidth(self.bounds)) / 2.0);
        CGFloat verticalInset = MAX(5.0, (PO_HANDLE_MINIMUM_TOUCH_SIZE - CGRectGetHeight(self.bounds)) / 2.0);
        CGRect hitRect = CGRectInset(self.bounds, -horizontalInset, -verticalInset);
        return CGRectContainsPoint(hitRect, point);
    }

    CGFloat containerWidth = CGRectGetWidth(self.superview.bounds);
    if (containerWidth <= 0) {
        containerWidth = 50.0;
    }

    CGFloat desiredHitLeftInContainer = containerWidth - PO_HANDLE_MINIMUM_TOUCH_SIZE;
    CGFloat leadingInset = MAX(5.0, CGRectGetMinX(self.frame) - desiredHitLeftInContainer);
    CGFloat verticalInset = MAX(5.0, (PO_HANDLE_MINIMUM_TOUCH_SIZE - CGRectGetHeight(self.bounds)) / 2.0);
    CGRect hitRect = CGRectMake(-leadingInset,
                                -verticalInset,
                                CGRectGetWidth(self.bounds) + leadingInset + 5.0,
                                CGRectGetHeight(self.bounds) + verticalInset * 2.0);
    return CGRectContainsPoint(hitRect, point);
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if ([self.superview isKindOfClass:[UIScrollView class]]) {
        UIPanGestureRecognizer *railPan = ((UIScrollView *)self.superview).panGestureRecognizer;
        [railPan requireGestureRecognizerToFail:quickSwitchLongPress];
        [railPan requireGestureRecognizerToFail:_panelPanGestureRecognizer];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return NO;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == _tapGestureRecognizer && hasTapTouchStartPoint) {
        hasTapTouchStartPoint = NO;
        CGPoint endPoint = [gestureRecognizer locationInView:self];
        return hypot(endPoint.x - tapTouchStartPoint.x, endPoint.y - tapTouchStartPoint.y) <= 5.0;
    }
    if (gestureRecognizer == _panelPanGestureRecognizer) {
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self];
        CGFloat absX = fabs(velocity.x);
        CGFloat absY = fabs(velocity.y);
        if (self.layoutMode == POHandleLayoutModeLandscapeFixedBottomLeft) {
            return MAX(absX, absY) > 0.0 && fabs(absX - absY) > 0.01;
        }
        return absX > absY;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer == _tapGestureRecognizer) {
        tapTouchStartPoint = [touch locationInView:self];
        hasTapTouchStartPoint = YES;
    }
    return YES;
}


-(void)tap:(UIGestureRecognizer *)recognizer{
    [self.delegate handle:self didReceiveTap:recognizer];
}

-(void)longPress:(UIGestureRecognizer *)recognizer{
    [self.delegate handle:self didLongPress:recognizer];
}

-(void)panelPan:(UIPanGestureRecognizer *)recognizer{
    [self.delegate handle:self didPanPanel:recognizer];
}


@end

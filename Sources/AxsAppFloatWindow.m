#import "AxsAppFloatWindow.h"
#import "AxsAppFloatConfig.h"

static const CGFloat kHeaderHeight = 36.0;

@interface AxsAppFloatWindow ()
@property (nonatomic, copy, readwrite) NSString *bundleID;
@property (nonatomic, strong, readwrite) AxsAppFloatSceneHost *host;
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, assign) CGRect restoreFrame;   // 放大前的原始帧
@property (nonatomic, assign) BOOL maximized;
@property (nonatomic, assign) NSInteger retryCount;  // 自动重试计数
@end

@implementation AxsAppFloatWindow

- (instancetype)initWithBundleID:(NSString *)bundleID
                      displayName:(NSString *)name
                         iconImage:(UIImage *)icon {
    CGRect screen = [UIScreen mainScreen].bounds;
    CGFloat w = screen.size.width * 0.62;
    CGFloat h = screen.size.height * 0.52;
    CGRect frame = CGRectMake((screen.size.width - w) / 2.0,
                              screen.size.height * 0.16, w, h);
    self = [super initWithFrame:frame];
    if (self) {
        _bundleID = [bundleID copy];
        self.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
        self.layer.cornerRadius = 18.0;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.5;
        self.layer.shadowRadius = 24;
        self.layer.shadowOffset = CGSizeMake(0, 10);

        // 标题栏（拖动 + 按钮）。
        _header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, kHeaderHeight)];
        _header.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
        _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [self addSubview:_header];

        UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
        iconView.frame = CGRectMake(12, 6, 24, 24);
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.layer.cornerRadius = 6;
        iconView.layer.masksToBounds = YES;
        [_header addSubview:iconView];
        // 标题栏只显示图标（不显示应用名）。

        UIButton *maxBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        maxBtn.frame = CGRectMake(frame.size.width - 114, 0, 38, kHeaderHeight);
        maxBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [maxBtn setTitle:@"⤢" forState:UIControlStateNormal];
        maxBtn.tintColor = [UIColor whiteColor];
        [maxBtn addTarget:self action:@selector(toggleMaximize) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:maxBtn];

        UIButton *retryBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        retryBtn.frame = CGRectMake(frame.size.width - 76, 0, 38, kHeaderHeight);
        retryBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [retryBtn setTitle:@"↻" forState:UIControlStateNormal];
        retryBtn.tintColor = [UIColor whiteColor];
        [retryBtn addTarget:self action:@selector(attachScene) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:retryBtn];

        UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        closeBtn.frame = CGRectMake(frame.size.width - 38, 0, 38, kHeaderHeight);
        closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
        closeBtn.tintColor = [UIColor whiteColor];
        [closeBtn addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
        [_header addSubview:closeBtn];

        // 内容区（宿主视图容器）。
        _contentView = [[UIView alloc] initWithFrame:
            CGRectMake(0, kHeaderHeight, frame.size.width, frame.size.height - kHeaderHeight)];
        _contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _contentView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:1.0];
        _contentView.clipsToBounds = YES;
        [self addSubview:_contentView];

        _hintLabel = [[UILabel alloc] initWithFrame:
            CGRectMake(0, frame.size.height - kHeaderHeight - 34, frame.size.width, 34)];
        _hintLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        _hintLabel.textColor = [UIColor colorWithWhite:1 alpha:0.8];
        _hintLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        _hintLabel.font = [UIFont systemFontOfSize:10];
        _hintLabel.numberOfLines = 2;
        _hintLabel.textAlignment = NSTextAlignmentCenter;
        _hintLabel.text = @"正在连接应用画面…";
        [_contentView addSubview:_hintLabel];

        // 标题栏拖动。
        UIPanGestureRecognizer *move = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleMove:)];
        [_header addGestureRecognizer:move];

        // 右下角缩放。
        UIPanGestureRecognizer *resize = [[UIPanGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleResize:)];
        UIView *corner = [[UIView alloc] initWithFrame:
            CGRectMake(frame.size.width - 28, frame.size.height - 28, 28, 28)];
        corner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        corner.backgroundColor = [UIColor clearColor];
        [self addSubview:corner];
        [corner addGestureRecognizer:resize];

        // 双击标题栏最大化/还原。
        UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(toggleMaximize)];
        dbl.numberOfTapsRequired = 2;
        [_header addGestureRecognizer:dbl];

        _host = [[AxsAppFloatSceneHost alloc] initWithBundleID:bundleID];
        [self attachScene];
    }
    return self;
}

- (void)attachScene {
    BOOL ok = [self.host attachToContainer:self.contentView];
    // 状态行常驻显示（空白时可据此定位宿主路径）。
    self.hintLabel.text = [NSString stringWithFormat:@"%@\n[iOS %@]",
        self.host.statusText ?: @"", [UIDevice currentDevice].systemVersion];
    self.hintLabel.hidden = ok ? YES : NO;
    [self.contentView bringSubviewToFront:self.hintLabel];
    if (ok) {
        self.retryCount = 0;
    } else if (self.retryCount < 10) {
        // 场景建立有延迟：失败自动重试（2s×10 次），期间用户去开 App 也能接上。
        self.retryCount += 1;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (!self.host.live) [self attachScene];
        });
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self.host layoutInContainer:self.contentView];
}

- (void)updateChromeAlpha:(CGFloat)alpha {
    self.alpha = alpha;
}

#pragma mark - 手势

- (void)handleMove:(UIPanGestureRecognizer *)pan {
    UIView *parent = self.superview;
    if (!parent) return;
    CGPoint t = [pan translationInView:parent];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [pan setTranslation:CGPointZero inView:parent];
    if (pan.state == UIGestureRecognizerStateEnded && [AxsAppFloatConfig axs_appfloat_shared].axs_appfloat_snapOn) {
        CGRect pb = parent.bounds;
        CGFloat halfW = pb.size.width / 2.0;
        CGFloat h = pb.size.height;
        if (self.center.x < 90) {
            [self animateToFrame:CGRectMake(8, 0, halfW - 12, h) withDuration:0.25];
        } else if (self.center.x > pb.size.width - 90) {
            [self animateToFrame:CGRectMake(halfW + 4, 0, halfW - 12, h) withDuration:0.25];
        }
    }
}

- (void)handleResize:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self];
    [pan setTranslation:CGPointZero inView:self];
    CGRect f = self.frame;
    f.size.width = MAX(220, f.size.width + t.x);
    f.size.height = MAX(260, f.size.height + t.y);
    self.frame = f;
}

- (void)toggleMaximize {
    UIView *parent = self.superview;
    if (!parent) return;
    if (self.maximized) {
        self.maximized = NO;
        [self animateToFrame:self.restoreFrame withDuration:0.25];
    } else {
        self.restoreFrame = self.frame;
        self.maximized = YES;
        [self animateToFrame:CGRectInset(parent.bounds, 8, 0) withDuration:0.25];
    }
}

- (void)animateToFrame:(CGRect)frame withDuration:(NSTimeInterval)duration {
    [UIView animateWithDuration:duration animations:^{
        self.frame = frame;
        [self layoutIfNeeded];
        [self.host layoutInContainer:self.contentView];
    }];
}

- (void)closeTapped {
    [self.host invalidate];
    if (self.onClose) self.onClose(self);
    [self removeFromSuperview];
}

@end

#import "GMRingView.h"

@interface GMRingView ()
@property (nonatomic, strong) CAShapeLayer *bgLayer;
@property (nonatomic, strong) CAShapeLayer *fgLayer;
@property (nonatomic, strong) UILabel *label;
@end

@implementation GMRingView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _lineWidth = 3.0;
        _ringColor = UIColor.systemBlueColor;
        self.backgroundColor = UIColor.clearColor;

        _bgLayer = [CAShapeLayer layer];
        _bgLayer.fillColor = UIColor.clearColor.CGColor;
        _bgLayer.strokeColor = [UIColor.tertiarySystemFillColor CGColor];
        _bgLayer.lineWidth = _lineWidth;
        [self.layer addSublayer:_bgLayer];

        _fgLayer = [CAShapeLayer layer];
        _fgLayer.fillColor = UIColor.clearColor.CGColor;
        _fgLayer.strokeColor = _ringColor.CGColor;
        _fgLayer.lineWidth = _lineWidth;
        _fgLayer.lineCap = kCALineCapRound;
        [self.layer addSublayer:_fgLayer];

        _label = [UILabel new];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [UIFont monospacedSystemFontOfSize:8 weight:UIFontWeightMedium];
        _label.textColor = UIColor.secondaryLabelColor;
        _label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_label];
        [NSLayoutConstraint activateConstraints:@[
            [_label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat inset = _lineWidth / 2 + 1;
    CGRect r = CGRectInset(self.bounds, inset, inset);
    UIBezierPath *p = [UIBezierPath bezierPathWithArcCenter:CGPointMake(CGRectGetMidX(self.bounds),
                                                                       CGRectGetMidY(self.bounds))
                                                    radius:r.size.width / 2
                                                startAngle:-M_PI_2
                                                  endAngle:M_PI * 1.5
                                                 clockwise:YES];
    _bgLayer.path = p.CGPath;
    _fgLayer.path = p.CGPath;
    _bgLayer.frame = self.bounds;
    _fgLayer.frame = self.bounds;
    [self updateStroke];
}

- (void)setProgress:(CGFloat)progress {
    _progress = MAX(0, MIN(1, progress));
    [self updateStroke];
}

- (void)setProgress:(CGFloat)p animated:(BOOL)animated {
    _progress = MAX(0, MIN(1, p));
    if (!animated) { [self updateStroke]; return; }
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    a.fromValue = @(_fgLayer.strokeEnd);
    a.toValue = @(_progress);
    a.duration = 0.35;
    _fgLayer.strokeEnd = _progress;
    [_fgLayer addAnimation:a forKey:@"strokeEnd"];
}

- (void)updateStroke {
    _fgLayer.strokeEnd = _progress;
    _fgLayer.strokeColor = _ringColor.CGColor;
    if (self.centerText.length) {
        _label.text = self.centerText;
    } else {
        _label.text = [NSString stringWithFormat:@"%.0f%%", _progress * 100];
    }
    // 超 80% 变橙红
    if (_progress > 0.9) _fgLayer.strokeColor = UIColor.systemRedColor.CGColor;
    else if (_progress > 0.75) _fgLayer.strokeColor = UIColor.systemOrangeColor.CGColor;
    else _fgLayer.strokeColor = _ringColor.CGColor;
}

- (void)setCenterText:(NSString *)t {
    _centerText = [t copy];
    [self updateStroke];
}

- (void)setRingColor:(UIColor *)c {
    _ringColor = c;
    [self updateStroke];
}

- (void)setLineWidth:(CGFloat)w {
    _lineWidth = w;
    _bgLayer.lineWidth = w;
    _fgLayer.lineWidth = w;
    [self setNeedsLayout];
}

@end

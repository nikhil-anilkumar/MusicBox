#import "UI.h"
#import "Library.h"
#import "Player.h"
#import <objc/runtime.h>

NSString *MBFormatTime(NSTimeInterval t) {
    if (!isfinite(t) || t < 0) t = 0;
    int s = (int)t;
    return s >= 3600 ? [NSString stringWithFormat:@"%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60]
                     : [NSString stringWithFormat:@"%d:%02d", s / 60, s % 60];
}

NSString *MBFormatBytes(unsigned long long b) {
    if (b < 1024) return [NSString stringWithFormat:@"%llu B", b];
    if (b < 1024 * 1024) return [NSString stringWithFormat:@"%.0f KB", b / 1024.0];
    if (b < 1024ull * 1024 * 1024) return [NSString stringWithFormat:@"%.1f MB", b / 1048576.0];
    return [NSString stringWithFormat:@"%.2f GB", b / 1073741824.0];
}

UIColor *MBAccentColor(void) { return [UIColor colorWithRed:0.80 green:0.62 blue:0.20 alpha:1]; }   // vinyl gold

void MBShowNowPlaying(UINavigationController *nav) {
    if ([nav.topViewController isKindOfClass:[MBNowPlayingViewController class]]) return;
    [nav pushViewController:[[MBNowPlayingViewController alloc] init] animated:YES];
}

@interface MBNowPlayingButtonTarget : NSObject
@property (nonatomic, weak) UIViewController *vc;
@end
@implementation MBNowPlayingButtonTarget
- (void)tap { MBShowNowPlaying(self.vc.navigationController); }
@end

void MBUpdateNowPlayingButton(UIViewController *vc) {
    BOOL has = [MBPlayer shared].currentTrack != nil;
    if (has && !vc.navigationItem.rightBarButtonItem) {
        MBNowPlayingButtonTarget *target = [[MBNowPlayingButtonTarget alloc] init];
        target.vc = vc;
        UIBarButtonItem *b = [[UIBarButtonItem alloc] initWithTitle:@"Now Playing" style:UIBarButtonItemStyleDone
                                                             target:target action:@selector(tap)];
        b.tintColor = [UIColor colorWithRed:0.62 green:0.46 blue:0.10 alpha:1];
        objc_setAssociatedObject(b, "target", target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // keep target alive
        vc.navigationItem.rightBarButtonItem = b;
    } else if (!has) {
        vc.navigationItem.rightBarButtonItem = nil;
    }
}

UIImage *MBIconImage(MBIcon icon, CGFloat size, UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    CGContextRef c = UIGraphicsGetCurrentContext();
    [color setFill]; [color setStroke];
    CGFloat s = size;
    switch (icon) {
        case MBIconPlay:
            CGContextMoveToPoint(c, s*0.25, s*0.15); CGContextAddLineToPoint(c, s*0.85, s*0.5);
            CGContextAddLineToPoint(c, s*0.25, s*0.85); CGContextFillPath(c); break;
        case MBIconPause:
            CGContextFillRect(c, CGRectMake(s*0.22, s*0.15, s*0.2, s*0.7));
            CGContextFillRect(c, CGRectMake(s*0.58, s*0.15, s*0.2, s*0.7)); break;
        case MBIconNext:
        case MBIconPrev: {
            if (icon == MBIconPrev) { CGContextTranslateCTM(c, s, 0); CGContextScaleCTM(c, -1, 1); }
            for (int i = 0; i < 2; i++) {
                CGFloat x = s*0.1 + i*s*0.36;
                CGContextMoveToPoint(c, x, s*0.22); CGContextAddLineToPoint(c, x + s*0.38, s*0.5);
                CGContextAddLineToPoint(c, x, s*0.78); CGContextFillPath(c);
            }
            CGContextFillRect(c, CGRectMake(s*0.8, s*0.22, s*0.08, s*0.56)); break;
        }
        case MBIconShuffle: {
            CGContextSetLineWidth(c, s*0.08);
            CGContextMoveToPoint(c, s*0.1, s*0.3); CGContextAddCurveToPoint(c, s*0.5, s*0.3, s*0.4, s*0.7, s*0.8, s*0.7);
            CGContextMoveToPoint(c, s*0.1, s*0.7); CGContextAddCurveToPoint(c, s*0.5, s*0.7, s*0.4, s*0.3, s*0.8, s*0.3);
            CGContextStrokePath(c);
            for (int i = 0; i < 2; i++) {
                CGFloat y = i ? s*0.7 : s*0.3;
                CGContextMoveToPoint(c, s*0.95, y); CGContextAddLineToPoint(c, s*0.75, y - s*0.12);
                CGContextAddLineToPoint(c, s*0.75, y + s*0.12); CGContextFillPath(c);
            }
            break;
        }
        case MBIconRepeat:
        case MBIconRepeatOne: {
            CGContextSetLineWidth(c, s*0.08);
            CGContextAddPath(c, [UIBezierPath bezierPathWithRoundedRect:CGRectMake(s*0.12, s*0.28, s*0.76, s*0.44) cornerRadius:s*0.15].CGPath);
            CGContextStrokePath(c);
            CGContextMoveToPoint(c, s*0.62, s*0.14); CGContextAddLineToPoint(c, s*0.78, s*0.28);
            CGContextAddLineToPoint(c, s*0.62, s*0.42); CGContextFillPath(c);
            if (icon == MBIconRepeatOne) {
                NSString *one = @"1";
                UIFont *f = [UIFont boldSystemFontOfSize:s*0.34];
                CGSize ts = [one sizeWithFont:f];
                [one drawAtPoint:CGPointMake((s - ts.width)/2, (s - ts.height)/2) withFont:f];
            }
            break;
        }
        case MBIconNote: {
            CGContextFillEllipseInRect(c, CGRectMake(s*0.14, s*0.64, s*0.28, s*0.2));
            CGContextFillEllipseInRect(c, CGRectMake(s*0.56, s*0.56, s*0.28, s*0.2));
            CGContextFillRect(c, CGRectMake(s*0.36, s*0.2, s*0.065, s*0.54));
            CGContextFillRect(c, CGRectMake(s*0.78, s*0.12, s*0.065, s*0.54));
            CGContextMoveToPoint(c, s*0.36, s*0.2); CGContextAddLineToPoint(c, s*0.845, s*0.12);
            CGContextAddLineToPoint(c, s*0.845, s*0.25); CGContextAddLineToPoint(c, s*0.36, s*0.33); CGContextFillPath(c);
            break;
        }
        case MBIconFolder: {
            CGContextAddPath(c, [UIBezierPath bezierPathWithRoundedRect:CGRectMake(s*0.08, s*0.2, s*0.36, s*0.2) cornerRadius:s*0.05].CGPath);
            CGContextAddPath(c, [UIBezierPath bezierPathWithRoundedRect:CGRectMake(s*0.08, s*0.28, s*0.84, s*0.56) cornerRadius:s*0.07].CGPath);
            CGContextFillPath(c);
            break;
        }
        case MBIconFile: {
            CGContextMoveToPoint(c, s*0.2, s*0.08); CGContextAddLineToPoint(c, s*0.6, s*0.08);
            CGContextAddLineToPoint(c, s*0.8, s*0.28); CGContextAddLineToPoint(c, s*0.8, s*0.92);
            CGContextAddLineToPoint(c, s*0.2, s*0.92); CGContextClosePath(c); CGContextFillPath(c);
            CGContextSetBlendMode(c, kCGBlendModeClear);
            CGContextFillEllipseInRect(c, CGRectMake(s*0.3, s*0.6, s*0.18, s*0.14));
            CGContextFillRect(c, CGRectMake(s*0.43, s*0.36, s*0.05, s*0.32));
            CGContextFillRect(c, CGRectMake(s*0.43, s*0.36, s*0.2, s*0.06));
            break;
        }
        case MBIconVinyl: {
            CGContextFillEllipseInRect(c, CGRectMake(s*0.05, s*0.05, s*0.9, s*0.9));
            CGContextSetBlendMode(c, kCGBlendModeClear);
            CGContextSetLineWidth(c, MAX(1, s*0.02));
            CGContextStrokeEllipseInRect(c, CGRectMake(s*0.2, s*0.2, s*0.6, s*0.6));
            CGContextStrokeEllipseInRect(c, CGRectMake(s*0.12, s*0.12, s*0.76, s*0.76));
            CGContextFillEllipseInRect(c, CGRectMake(s*0.44, s*0.44, s*0.12, s*0.12));
            break;
        }
    }
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@implementation MBWindow
- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
    if (event.type == UIEventTypeRemoteControl) [[MBPlayer shared] handleRemoteControlEvent:event];
}
@end

#import "UI.h"
#import "Library.h"
#import "Player.h"
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>

@implementation MBNowPlayingViewController {
    UIImageView *_art;
    UILabel *_title, *_artist, *_album, *_elapsed, *_remaining, *_error, *_badge;
    UISlider *_slider;
    UIButton *_prev, *_play, *_next, *_shuffle, *_repeat;
    MPVolumeView *_volume;
    NSTimer *_timer;
    BOOL _scrubbing;
}

- (id)init {
    if ((self = [super init])) {
        self.title = @"Now Playing";
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

static UILabel *MBLabel(CGFloat size, BOOL bold, UIColor *color) {
    UILabel *l = [[UILabel alloc] init];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = color; l.backgroundColor = [UIColor clearColor];
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

- (UIButton *)button:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.showsTouchWhenHighlighted = YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *v = self.view;
    v.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];

    // (i) button: details about the current file.
    UIButton *info = [UIButton buttonWithType:UIButtonTypeInfoLight];
    info.frame = CGRectMake(0, 0, 40, 40);
    [info addTarget:self action:@selector(showInfo) forControlEvents:UIControlEventTouchUpInside];
    info.accessibilityLabel = @"Song details";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:info];

    _art = [[UIImageView alloc] init];
    _art.contentMode = UIViewContentModeScaleAspectFill;
    _art.clipsToBounds = YES;
    _art.layer.cornerRadius = 6;
    _art.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];
    _art.userInteractionEnabled = YES;
    [_art addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showInfo)]];
    [v addSubview:_art];

    _title = MBLabel(19, YES, [UIColor whiteColor]);
    _artist = MBLabel(15, NO, [UIColor colorWithWhite:0.75 alpha:1]);
    _album = MBLabel(13, NO, [UIColor colorWithWhite:0.55 alpha:1]);
    _elapsed = MBLabel(12, NO, [UIColor colorWithWhite:0.7 alpha:1]);
    _remaining = MBLabel(12, NO, [UIColor colorWithWhite:0.7 alpha:1]);
    _error = MBLabel(12, NO, [UIColor colorWithRed:1 green:0.45 blue:0.4 alpha:1]);
    _error.numberOfLines = 2;
    _badge = MBLabel(10, YES, MBAccentColor());           // e.g. "FLAC · 44.1 kHz"
    _badge.layer.borderColor = MBAccentColor().CGColor;
    _badge.layer.borderWidth = 1;
    _badge.layer.cornerRadius = 3;
    _elapsed.textAlignment = NSTextAlignmentLeft; _remaining.textAlignment = NSTextAlignmentRight;
    for (UILabel *l in @[_title, _artist, _album, _elapsed, _remaining, _error, _badge]) [v addSubview:l];

    _slider = [[UISlider alloc] init];
    _slider.minimumTrackTintColor = MBAccentColor();
    [_slider addTarget:self action:@selector(scrubStart) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(scrubEnd) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [_slider addTarget:self action:@selector(scrubMove) forControlEvents:UIControlEventValueChanged];
    [v addSubview:_slider];

    _prev = [self button:@selector(prevTapped)];
    _play = [self button:@selector(playTapped)];
    _next = [self button:@selector(nextTapped)];
    _shuffle = [self button:@selector(shuffleTapped)];
    _repeat = [self button:@selector(repeatTapped)];
    UIColor *w = [UIColor whiteColor];
    [_prev setImage:MBIconImage(MBIconPrev, 36, w) forState:UIControlStateNormal];
    [_next setImage:MBIconImage(MBIconNext, 36, w) forState:UIControlStateNormal];
    _prev.accessibilityLabel = @"Previous"; _next.accessibilityLabel = @"Next";
    _shuffle.accessibilityLabel = @"Shuffle"; _repeat.accessibilityLabel = @"Repeat";

    _volume = [[MPVolumeView alloc] init];
    for (UIView *sub in _volume.subviews)   // gold volume bar to match the progress bar
        if ([sub isKindOfClass:[UISlider class]]) ((UISlider *)sub).minimumTrackTintColor = MBAccentColor();
    [v addSubview:_volume];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(update) name:MBPlayerStateDidChangeNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    CGFloat artSize = MIN(W - 60, H - 262);
    CGFloat y = 14;
    _art.frame = CGRectMake((W - artSize) / 2, y, artSize, artSize);
    y += artSize + 8;
    CGSize bs = [_badge.text sizeWithFont:_badge.font];
    _badge.frame = CGRectMake((W - bs.width - 12) / 2, y, bs.width + 12, 16); y += 20;
    _title.frame = CGRectMake(12, y, W - 24, 24); y += 24;
    _artist.frame = CGRectMake(12, y, W - 24, 20); y += 20;
    _album.frame = CGRectMake(12, y, W - 24, 18); y += 22;
    _slider.frame = CGRectMake(20, y, W - 40, 24); y += 24;
    _elapsed.frame = CGRectMake(20, y, 80, 16);
    _remaining.frame = CGRectMake(W - 100, y, 80, 16);
    _error.frame = CGRectMake(100, y - 2, W - 200, 30);
    y += 20;
    CGFloat cy = y + 28;
    _play.frame = CGRectMake(W/2 - 32, cy - 32, 64, 64);
    _prev.frame = CGRectMake(W/2 - 32 - 84, cy - 26, 52, 52);
    _next.frame = CGRectMake(W/2 + 32 + 32, cy - 26, 52, 52);
    _shuffle.frame = CGRectMake(14, cy - 20, 40, 40);
    _repeat.frame = CGRectMake(W - 54, cy - 20, 40, 40);
    _volume.frame = CGRectMake(24, MIN(cy + 44, H - 30), W - 48, 24);
}

- (BOOL)canBecomeFirstResponder { return YES; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self update];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(tick) userInfo:nil repeats:YES];
}

- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self becomeFirstResponder]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [_timer invalidate]; _timer = nil; }
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_timer invalidate]; }

- (void)showInfo {
    MBTrack *t = [MBPlayer shared].currentTrack;
    if (t) [self.navigationController pushViewController:[[MBTrackInfoViewController alloc] initWithTrack:t] animated:YES];
}

- (void)update {
    MBPlayer *p = [MBPlayer shared];
    MBTrack *t = p.currentTrack;
    _title.text = t.title ?: @"Not Playing";
    _artist.text = t.artist;
    _album.text = t.album;
    _error.text = p.lastError;
    self.navigationItem.rightBarButtonItem.enabled = t != nil;

    NSMutableArray *badge = [NSMutableArray array];
    if (t.format && !t.mediaItem) [badge addObject:t.format];
    if (p.sampleRate > 0) [badge addObject:[NSString stringWithFormat:@"%g kHz", p.sampleRate / 1000.0]];
    _badge.text = [badge componentsJoinedByString:@" · "];
    _badge.hidden = badge.count == 0;

    UIImage *art = t.artwork;
    _art.image = art ?: MBIconImage(MBIconVinyl, 170, [MBAccentColor() colorWithAlphaComponent:0.55]);
    _art.contentMode = art ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
    UIColor *w = [UIColor whiteColor], *off = [UIColor colorWithWhite:0.45 alpha:1];
    [_play setImage:MBIconImage(p.isPlaying ? MBIconPause : MBIconPlay, 52, w) forState:UIControlStateNormal];
    _play.accessibilityLabel = p.isPlaying ? @"Pause" : @"Play";
    [_shuffle setImage:MBIconImage(MBIconShuffle, 28, p.shuffle ? MBAccentColor() : off) forState:UIControlStateNormal];
    [_repeat setImage:MBIconImage(p.repeatMode == MBRepeatOne ? MBIconRepeatOne : MBIconRepeat, 28,
                                  p.repeatMode == MBRepeatOff ? off : MBAccentColor()) forState:UIControlStateNormal];
    [self.view setNeedsLayout];
    [self tick];
}

- (void)tick {
    MBPlayer *p = [MBPlayer shared];
    NSTimeInterval dur = p.duration, cur = p.currentTime;
    _slider.maximumValue = dur > 0 ? dur : 1;
    if (!_scrubbing) _slider.value = cur;
    NSTimeInterval shown = _scrubbing ? _slider.value : cur;
    _elapsed.text = MBFormatTime(shown);
    _remaining.text = [@"-" stringByAppendingString:MBFormatTime(dur - shown)];
}

- (void)scrubStart { _scrubbing = YES; }
- (void)scrubMove { [self tick]; }
- (void)scrubEnd { [[MBPlayer shared] seekToTime:_slider.value]; _scrubbing = NO; }
- (void)playTapped { [[MBPlayer shared] togglePlayPause]; }
- (void)prevTapped { [[MBPlayer shared] previous]; }
- (void)nextTapped { [[MBPlayer shared] next]; }
- (void)shuffleTapped { MBPlayer *p = [MBPlayer shared]; p.shuffle = !p.shuffle; }
- (void)repeatTapped { MBPlayer *p = [MBPlayer shared]; p.repeatMode = (p.repeatMode + 1) % 3; }

@end

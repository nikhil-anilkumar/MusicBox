#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import "UI.h"
#import "Library.h"
#import "Player.h"
#import "AudioDecoder.h"

@interface MBAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITabBarController *tabs;
@end

#pragma mark - Self test
// Triggered by a file named "selftest" in Documents (pushed over USB). Exercises every decoder, the
// Songs filters, the details reader and playback on the device, then writes Documents/selftest-results.txt
// plus screenshots of each screen.

@interface MBSelfTest : NSObject
+ (void)runWithTabs:(UITabBarController *)tabs;
@end

@implementation MBSelfTest {
    NSMutableString *_log;
    UITabBarController *_tabs;
    UINavigationController *_nav;     // Songs tab
    MBSongsViewController *_songs;
    NSArray *_tracks;
    NSUInteger _i;
    int _passed, _failed;
}

+ (void)runWithTabs:(UITabBarController *)tabs {
    static MBSelfTest *t;   // kept alive for the duration of the run
    t = [[MBSelfTest alloc] init];
    t->_tabs = tabs;
    t->_nav = tabs.viewControllers[0];
    t->_songs = (MBSongsViewController *)t->_nav.viewControllers[0];
    [t start];
}

- (void)log:(NSString *)fmt, ... {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[MusicBox][selftest] %@", s);
    [_log appendFormat:@"%@\n", s];
}

- (void)check:(BOOL)ok what:(NSString *)what {
    if (ok) _passed++; else _failed++;
    [self log:@"%@ %@", ok ? @"PASS" : @"FAIL", what];
}

- (void)screenshot:(NSString *)name {
    UIWindow *w = _tabs.view.window;
    UIGraphicsBeginImageContextWithOptions(w.bounds.size, YES, 0);
    [w.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [UIImagePNGRepresentation(img) writeToFile:[[MBLibrary documentsPath] stringByAppendingPathComponent:name] atomically:YES];
}

- (void)after:(double)secs do:(dispatch_block_t)block {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(secs * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

- (void)start {
    _log = [NSMutableString string];
    UIDevice *d = [UIDevice currentDevice];
    [self log:@"MusicBox self-test on %@ iOS %@", d.model, d.systemVersion];
    _tracks = [MBLibrary shared].fileTracks;
    [self log:@"%lu file tracks, %lu library songs", (unsigned long)_tracks.count, (unsigned long)[MBLibrary shared].ipodTracks.count];

    // Phase 1: decode every file completely and read its details, off the main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (MBTrack *t in self->_tracks) [self decodeTest:t];
        dispatch_async(dispatch_get_main_queue(), ^{ [self filterTests]; });
    });
}

- (void)decodeTest:(MBTrack *)t {
    NSError *err = nil;
    CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
    id<MBAudioDecoder> dec = [MBDecoderFactory decoderForURL:t.url error:&err];
    if (!dec) { _failed++; [self log:@"FAIL decode %@: %@", t.url.lastPathComponent, err.localizedDescription]; return; }
    SInt16 *buf = malloc(4096 * 4);
    SInt64 total = 0; UInt32 n; int peak = 0;
    while ((n = [dec readFrames:4096 into:buf]) > 0) {
        for (UInt32 k = 0; k < n * dec.channels; k += 7) { int v = abs(buf[k]); if (v > peak) peak = v; }
        total += n;
    }
    BOOL seekOK = YES;
    if (total > 8192) seekOK = [dec seekToFrame:total / 2] && [dec readFrames:4096 into:buf] > 0;
    free(buf);
    double secs = CFAbsoluteTimeGetCurrent() - t0;
    double audioSecs = total / dec.sampleRate;
    BOOL lengthOK = dec.totalFrames <= 0 || llabs(dec.totalFrames - total) <= (SInt64)(dec.sampleRate * 0.1);
    BOOL ok = total > 0 && peak > 1000 && lengthOK && seekOK;
    if (ok) _passed++; else _failed++;
    [self log:@"%@ decode %-24@ [%@] %.0fHz %uch %.2fs audio (header %lld frames, got %lld) peak %d seek %@ in %.2fs (%.0fx realtime)",
     ok ? @"PASS" : @"FAIL", t.url.lastPathComponent, t.format, dec.sampleRate, (unsigned)dec.channels, audioSecs,
     dec.totalFrames, total, peak, seekOK ? @"ok" : @"FAILED", secs, audioSecs / MAX(secs, 0.001)];

    // Details screen data: codec must be identified and agree with the decoder's sample rate.
    NSDictionary *tech = [MBTagReader technicalInfoForFileURL:t.url];
    BOOL techOK = [tech[@"codec"] length] > 0 && fabs([tech[@"sampleRate"] doubleValue] - dec.sampleRate) < 1 && [tech[@"bitrate"] intValue] > 0;
    if (techOK) _passed++; else _failed++;
    [self log:@"%@ info   %-24@ %@ | %@ | %@ Hz | %@-bit | %@ kbps | %@%@", techOK ? @"PASS" : @"FAIL", t.url.lastPathComponent,
     tech[@"codec"], tech[@"container"] ?: @"-", tech[@"sampleRate"], tech[@"bitDepth"] ?: @"-", tech[@"bitrate"],
     tech[@"decoder"], tech[@"encoder"] ? [@" | enc " stringByAppendingString:tech[@"encoder"]] : @""];
}

// Expected counts come from the test files' names (e.g. "08-flac-16bit.flac").
- (NSUInteger)countNamesMatching:(NSArray *)words {
    NSUInteger n = 0;
    for (MBTrack *t in _tracks) for (NSString *w in words) if ([t.url.lastPathComponent rangeOfString:w].location != NSNotFound) { n++; break; }
    return n;
}

- (void)filterTests {
    MBSongsViewController *s = _songs;
    NSUInteger total = [MBLibrary shared].allTracks.count;
    [self check:s.filteredTracks.count == total what:[NSString stringWithFormat:@"songs: all %lu shown", (unsigned long)total]];
    [self screenshot:@"selftest-songs.png"];

    s.scope = 1;
    NSUInteger lossless = s.filteredTracks.count, expL = [self countNamesMatching:@[@"alac", @"wav", @"aiff", @"caf", @"flac"]];
    [self check:lossless == expL what:[NSString stringWithFormat:@"songs: Lossless scope %lu (expected %lu)", (unsigned long)lossless, (unsigned long)expL]];
    s.scope = 2;
    NSUInteger lossy = s.filteredTracks.count, expY = [self countNamesMatching:@[@"mp3", @"aac", @"ogg"]];
    [self check:lossy == expY what:[NSString stringWithFormat:@"songs: Lossy scope %lu (expected %lu)", (unsigned long)lossy, (unsigned long)expY]];
    s.scope = 0;

    s.formatFilter = @"FLAC";
    NSUInteger flac = s.filteredTracks.count, expF = [self countNamesMatching:@[@".flac"]];
    [self check:flac == expF what:[NSString stringWithFormat:@"songs: format filter FLAC %lu (expected %lu)", (unsigned long)flac, (unsigned long)expF]];
    [self screenshot:@"selftest-songs-filtered.png"];
    s.formatFilter = nil;

    s.searchText = @"mp3";
    NSUInteger mp3 = s.filteredTracks.count, expM = [self countNamesMatching:@[@"mp3"]];
    [self check:mp3 == expM what:[NSString stringWithFormat:@"songs: search \"mp3\" %lu (expected %lu)", (unsigned long)mp3, (unsigned long)expM]];
    s.searchText = nil;

    s.sortMode = MBSortDuration;
    NSArray *sorted = s.filteredTracks;
    BOOL ordered = YES;
    for (NSUInteger i = 1; i < sorted.count; i++) if (((MBTrack *)sorted[i]).duration < ((MBTrack *)sorted[i-1]).duration) ordered = NO;
    [self check:ordered what:@"songs: sort by duration is ascending"];
    s.sortMode = MBSortTitle;

    // Files tab
    _tabs.selectedIndex = 1;
    [self after:1.0 do:^{
        [self screenshot:@"selftest-files.png"];
        UITableViewController *files = (UITableViewController *)[(UINavigationController *)self->_tabs.viewControllers[1] topViewController];
        NSInteger rows = [files.tableView numberOfRowsInSection:0];
        [self check:rows >= (NSInteger)self->_tracks.count what:[NSString stringWithFormat:@"files: %ld entries listed", (long)rows]];
        self->_tabs.selectedIndex = 0;
        [self after:0.5 do:^{ self->_i = 0; [self playNext]; }];
    }];
}

// Play a few seconds of each track through the real player and check time advances.
- (void)playNext {
    if (_i >= _tracks.count) { [self finish]; return; }
    MBPlayer *p = [MBPlayer shared];
    [p playTracks:_tracks startingAt:_i];
    if (![_nav.topViewController isKindOfClass:[MBNowPlayingViewController class]])
        [_nav pushViewController:[[MBNowPlayingViewController alloc] init] animated:NO];
    [self after:0.5 do:^{
        NSTimeInterval a = p.currentTime;
        [self after:2.0 do:^{
            NSTimeInterval b = p.currentTime;
            BOOL ok = p.isPlaying && b - a > 1.5 && b - a < 2.5;
            if (ok) self->_passed++; else self->_failed++;
            [self log:@"%@ play   %-24@ advanced %.2fs in 2.0s wall (playing=%d)%@", ok ? @"PASS" : @"FAIL",
             p.currentTrack.url.lastPathComponent, b - a, p.isPlaying, p.lastError ? [@" " stringByAppendingString:p.lastError] : @""];
            if ([p.currentTrack.format isEqualToString:@"FLAC"] && ![[NSFileManager defaultManager] fileExistsAtPath:
                 [[MBLibrary documentsPath] stringByAppendingPathComponent:@"selftest-info.png"]]) {
                // Screenshot Now Playing, then open the (i) details screen for this FLAC file.
                [self screenshot:@"selftest-nowplaying.png"];
                [self->_nav pushViewController:[[MBTrackInfoViewController alloc] initWithTrack:p.currentTrack] animated:NO];
                [self after:1.5 do:^{
                    [self screenshot:@"selftest-info.png"];
                    [self->_nav popViewControllerAnimated:NO];
                    self->_i++;
                    [self playNext];
                }];
                return;
            }
            self->_i++;
            [self playNext];
        }];
    }];
}

- (void)finish {
    // Auto-advance check: seek to the last second of track 1 and expect track 2 to start.
    MBPlayer *p = [MBPlayer shared];
    if (_tracks.count >= 2) {
        [p playTracks:_tracks startingAt:0];
        [p seekToTime:MAX(0, p.duration - 1.0)];
        [self after:2.5 do:^{
            [self check:p.currentTrack == self->_tracks[1] && p.isPlaying
                   what:[NSString stringWithFormat:@"auto-advance to next track (now: %@)", p.currentTrack.url.lastPathComponent]];
            [self writeResults];
        }];
    } else {
        [self writeResults];
    }
}

- (void)writeResults {
    [[MBPlayer shared] pause];
    [_nav popToRootViewControllerAnimated:NO];
    [self log:@"RESULT: %d passed, %d failed", _passed, _failed];
    NSString *docs = [MBLibrary documentsPath];
    [_log writeToFile:[docs stringByAppendingPathComponent:@"selftest-results.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [[NSFileManager defaultManager] removeItemAtPath:[docs stringByAppendingPathComponent:@"selftest"] error:NULL];
}
@end

#pragma mark - App delegate

@implementation MBAppDelegate {
    BOOL _selfTestPending;
}

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    NSLog(@"[MusicBox] launched on iOS %@", [UIDevice currentDevice].systemVersion);
    self.window = [[MBWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    UINavigationController *songs = [[UINavigationController alloc] initWithRootViewController:[[MBSongsViewController alloc] init]];
    UINavigationController *files = [[UINavigationController alloc] initWithRootViewController:[[MBFilesViewController alloc] init]];
    for (UINavigationController *n in @[songs, files]) n.navigationBar.barStyle = UIBarStyleBlack;
    self.tabs = [[UITabBarController alloc] init];
    self.tabs.viewControllers = @[songs, files];
    self.tabs.tabBar.selectedImageTintColor = MBAccentColor();
    self.window.rootViewController = self.tabs;
    [self.window makeKeyAndVisible];

    [MBPlayer shared];   // configures the audio session
    [app beginReceivingRemoteControlEvents];

    NSString *trigger = [[MBLibrary documentsPath] stringByAppendingPathComponent:@"selftest"];
    _selfTestPending = [[NSFileManager defaultManager] fileExistsAtPath:trigger];
    if (_selfTestPending)   // fresh screenshots each run
        for (NSString *f in @[@"selftest-info.png", @"selftest-results.txt"])
            [[NSFileManager defaultManager] removeItemAtPath:[[MBLibrary documentsPath] stringByAppendingPathComponent:f] error:NULL];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(libraryLoaded)
                                                 name:MBLibraryDidChangeNotification object:nil];
    [[MBLibrary shared] reload];
    return YES;
}

- (void)libraryLoaded {
    if (!_selfTestPending) return;
    _selfTestPending = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [MBSelfTest runWithTabs:self.tabs];
    });
}

- (void)applicationWillEnterForeground:(UIApplication *)app {
    // Pick up files added through iTunes File Sharing while we were in the background.
    [[MBLibrary shared] reload];
}

// "Open in MusicBox" from Mail, Safari, etc.
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url sourceApplication:(NSString *)src annotation:(id)ann {
    if (![url isFileURL]) return NO;
    NSURL *dest = [[MBLibrary shared] importFileAtURL:url];
    NSLog(@"[MusicBox] imported %@", dest.lastPathComponent);
    [[MBLibrary shared] reload];
    return dest != nil;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([MBAppDelegate class]));
    }
}

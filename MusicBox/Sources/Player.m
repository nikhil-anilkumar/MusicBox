#import "Player.h"
#import "AudioEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSString *const MBPlayerStateDidChangeNotification = @"MBPlayerStateDidChangeNotification";

@interface MBPlayer () <MBAudioEngineDelegate>
@end

@implementation MBPlayer {
    MBAudioEngine *_engine;
    NSArray *_queue;           // tracks in original order
    NSMutableArray *_order;    // indices into _queue, in play order (shuffled or not)
    NSUInteger _position;      // index into _order
    BOOL _resumeAfterInterruption;
}

+ (MBPlayer *)shared {
    static MBPlayer *p;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ p = [[MBPlayer alloc] init]; });
    return p;
}

- (id)init {
    if ((self = [super init])) {
        _engine = [[MBAudioEngine alloc] init];
        _engine.delegate = self;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback error:NULL];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:session];
        [nc addObserver:self selector:@selector(routeChange:) name:AVAudioSessionRouteChangeNotification object:session];
    }
    return self;
}

#pragma mark Queue

- (MBTrack *)currentTrack {
    return _position < _order.count ? _queue[[_order[_position] unsignedIntegerValue]] : nil;
}

- (void)buildOrderKeeping:(NSUInteger)queueIndex {
    _order = [NSMutableArray arrayWithCapacity:_queue.count];
    for (NSUInteger i = 0; i < _queue.count; i++) [_order addObject:@(i)];
    if (_shuffle && _order.count > 1) {
        for (NSUInteger i = _order.count - 1; i > 0; i--)
            [_order exchangeObjectAtIndex:i withObjectAtIndex:arc4random_uniform((u_int32_t)i + 1)];
        // the track the user picked plays first
        NSUInteger at = [_order indexOfObject:@(queueIndex)];
        [_order exchangeObjectAtIndex:0 withObjectAtIndex:at];
        _position = 0;
    } else {
        _position = queueIndex;
    }
}

- (void)setShuffle:(BOOL)shuffle {
    _shuffle = shuffle;
    if (_queue.count) [self buildOrderKeeping:[_order[_position] unsignedIntegerValue]];
    [self changed];
}

- (void)setRepeatMode:(MBRepeatMode)repeatMode { _repeatMode = repeatMode; [self changed]; }

- (void)playTracks:(NSArray *)tracks startingAt:(NSUInteger)index {
    _queue = [tracks copy];
    [self buildOrderKeeping:index];
    [self startCurrent];
}

- (void)startCurrent {
    MBTrack *t = self.currentTrack;
    if (!t) { [_engine stop]; [self changed]; return; }
    NSError *err = nil;
    id<MBAudioDecoder> dec = [MBDecoderFactory decoderForURL:t.url error:&err];
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    if (!dec || ![_engine playDecoder:dec]) {
        _lastError = [NSString stringWithFormat:@"Can't play \"%@\": %@", t.title, err.localizedDescription ?: @"unknown error"];
        NSLog(@"[MusicBox] %@", _lastError);
        [self changed];
        return;
    }
    _lastError = nil;
    NSLog(@"[MusicBox] playing \"%@\" [%@] %.0f Hz %u ch, %.1fs", t.title, t.format, dec.sampleRate,
          (unsigned)dec.channels, _engine.duration);
    [self changed];
}

#pragma mark Transport

- (BOOL)isPlaying { return _engine.isPlaying; }
- (double)sampleRate { return _engine.sampleRate; }
- (UInt32)channels { return _engine.channels; }
- (NSTimeInterval)currentTime { return _engine.currentTime; }
- (NSTimeInterval)duration { return _engine.duration ?: self.currentTrack.duration; }

- (void)play {
    if (!self.currentTrack) return;
    [[AVAudioSession sharedInstance] setActive:YES error:NULL];
    if (_engine.duration == 0 && !_engine.isPlaying) { [self startCurrent]; return; }
    [_engine resume];
    [self changed];
}

- (void)pause { [_engine pause]; [self changed]; }

- (void)togglePlayPause { if (self.isPlaying) [self pause]; else [self play]; }

- (void)next { [self advance:YES userInitiated:YES]; }

- (void)previous {
    if (self.currentTime > 3 || _position == 0) {
        if (_position == 0 && _repeatMode == MBRepeatAll && self.currentTime <= 3 && _order.count) _position = _order.count - 1;
        else { [self seekToTime:0]; return; }
    } else {
        _position--;
    }
    [self startCurrent];
}

- (void)advance:(BOOL)forward userInitiated:(BOOL)user {
    if (!_order.count) return;
    if (!user && _repeatMode == MBRepeatOne) { [self startCurrent]; return; }
    if (_position + 1 < _order.count) {
        _position++;
    } else if (_repeatMode == MBRepeatAll || user) {
        _position = 0;
        if (!user && _shuffle) [self buildOrderKeeping:[_order[arc4random_uniform((u_int32_t)_order.count)] unsignedIntegerValue]];
    } else {
        [_engine stop];        // end of queue
        _position = 0;
        [self changed];
        return;
    }
    [self startCurrent];
}

- (void)seekToTime:(NSTimeInterval)t { [_engine seekToTime:t]; [self changed]; }

- (void)audioEngineDidFinishTrack:(MBAudioEngine *)engine { [self advance:YES userInitiated:NO]; }

#pragma mark System events

- (void)handleRemoteControlEvent:(UIEvent *)event {
    switch (event.subtype) {
        case UIEventSubtypeRemoteControlPlay: [self play]; break;
        case UIEventSubtypeRemoteControlPause: [self pause]; break;
        case UIEventSubtypeRemoteControlStop: [self pause]; break;
        case UIEventSubtypeRemoteControlTogglePlayPause: [self togglePlayPause]; break;
        case UIEventSubtypeRemoteControlNextTrack: [self next]; break;
        case UIEventSubtypeRemoteControlPreviousTrack: [self previous]; break;
        default: break;
    }
}

- (void)interruption:(NSNotification *)n {
    NSUInteger type = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        _resumeAfterInterruption = self.isPlaying;
        [_engine pause];
    } else {
        NSUInteger opts = [n.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if (_resumeAfterInterruption && (opts & AVAudioSessionInterruptionOptionShouldResume)) {
            [[AVAudioSession sharedInstance] setActive:YES error:NULL];
            [_engine resume];
        }
        _resumeAfterInterruption = NO;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self changed]; });
}

- (void)routeChange:(NSNotification *)n {
    // Headphones pulled out: pause like the built-in Music app does.
    NSUInteger reason = [n.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable)
        dispatch_async(dispatch_get_main_queue(), ^{ [self pause]; });
}

- (void)changed {
    MBTrack *t = self.currentTrack;
    if (t) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[MPMediaItemPropertyTitle] = t.title;
        if (t.artist) info[MPMediaItemPropertyArtist] = t.artist;
        if (t.album) info[MPMediaItemPropertyAlbumTitle] = t.album;
        info[MPMediaItemPropertyPlaybackDuration] = @(self.duration);
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.currentTime);
        info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.isPlaying ? 1.0 : 0.0);
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = @(_position);
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = @(_order.count);
        UIImage *art = t.artwork;
        if (art) info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithImage:art];
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
    } else {
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:MBPlayerStateDidChangeNotification object:self];
}

@end

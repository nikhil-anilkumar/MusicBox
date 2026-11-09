#import "AudioEngine.h"
#import <AudioToolbox/AudioToolbox.h>
#include <pthread.h>

#define kNumBuffers 4
#define kBufferSeconds 0.25

@interface MBAudioEngine () {
    AudioQueueRef _queue;
    AudioQueueBufferRef _buffers[kNumBuffers];
    UInt32 _framesPerBuffer;
    pthread_mutex_t _lock;          // guards _decoder while the queue thread decodes
    id<MBAudioDecoder> _decoder;
    SInt64 _baseFrame;              // frame the current queue started from (after seeks)
    BOOL _eof;
    BOOL _paused;
    BOOL _tearingDown;              // queue stop is ours, not end of track
    BOOL _started;                  // AudioQueueStart has been called on _queue
}
- (void)fillBuffer:(AudioQueueBufferRef)buf;
- (void)queueStoppedRunning;
@end

static void MBOutputCallback(void *ud, AudioQueueRef q, AudioQueueBufferRef buf) {
    [(__bridge MBAudioEngine *)ud fillBuffer:buf];
}

static void MBIsRunningCallback(void *ud, AudioQueueRef q, AudioQueuePropertyID pid) {
    UInt32 running = 0, sz = sizeof(running);
    AudioQueueGetProperty(q, kAudioQueueProperty_IsRunning, &running, &sz);
    if (!running) [(__bridge MBAudioEngine *)ud queueStoppedRunning];
}

@implementation MBAudioEngine

- (id)init {
    if ((self = [super init])) pthread_mutex_init(&_lock, NULL);
    return self;
}

- (void)dealloc { [self disposeQueue]; pthread_mutex_destroy(&_lock); }

#pragma mark Queue lifecycle

- (void)disposeQueue {
    if (!_queue) return;
    _tearingDown = YES;
    AudioQueueStop(_queue, true);
    AudioQueueDispose(_queue, true);
    _queue = NULL;
    _tearingDown = NO;
}

- (BOOL)startQueueAtFrame:(SInt64)frame {
    [self disposeQueue];
    id<MBAudioDecoder> d = _decoder;
    if (!d) return NO;

    AudioStreamBasicDescription fmt = {0};
    fmt.mSampleRate = d.sampleRate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    fmt.mBitsPerChannel = 16;
    fmt.mChannelsPerFrame = d.channels;
    fmt.mBytesPerFrame = 2 * d.channels;
    fmt.mFramesPerPacket = 1;
    fmt.mBytesPerPacket = fmt.mBytesPerFrame;

    OSStatus st = AudioQueueNewOutput(&fmt, MBOutputCallback, (__bridge void *)self, NULL, NULL, 0, &_queue);
    if (st != noErr) { NSLog(@"[MusicBox] AudioQueueNewOutput failed: %d", (int)st); _queue = NULL; return NO; }
    AudioQueueAddPropertyListener(_queue, kAudioQueueProperty_IsRunning, MBIsRunningCallback, (__bridge void *)self);

    pthread_mutex_lock(&_lock);
    if (frame > 0) [d seekToFrame:frame];
    pthread_mutex_unlock(&_lock);
    _baseFrame = frame;
    _eof = NO;
    _started = NO;

    _framesPerBuffer = (UInt32)(d.sampleRate * kBufferSeconds);
    for (int i = 0; i < kNumBuffers; i++) {
        AudioQueueAllocateBuffer(_queue, _framesPerBuffer * fmt.mBytesPerFrame, &_buffers[i]);
        [self fillBuffer:_buffers[i]];
        if (_eof) break;
    }
    if (!_paused) [self startRunning];
    return YES;
}

- (OSStatus)startRunning {
    OSStatus st = AudioQueueStart(_queue, NULL);
    if (st != noErr) { NSLog(@"[MusicBox] AudioQueueStart failed: %d", (int)st); return st; }
    if (!_started) {
        _started = YES;
        if (_eof) AudioQueueStop(_queue, false);   // whole file fit in the primed buffers
    }
    return noErr;
}

// Runs on the AudioQueue's internal thread (and on main while priming).
- (void)fillBuffer:(AudioQueueBufferRef)buf {
    if (_eof || _tearingDown) return;
    pthread_mutex_lock(&_lock);
    UInt32 n = _decoder ? [_decoder readFrames:_framesPerBuffer into:(SInt16 *)buf->mAudioData] : 0;
    UInt32 bytesPerFrame = _decoder ? 2 * _decoder.channels : 4;
    pthread_mutex_unlock(&_lock);
    if (n == 0) {
        _eof = YES;
        if (_started) AudioQueueStop(_queue, false);   // let queued audio drain, then IsRunning -> 0
        return;
    }
    buf->mAudioDataByteSize = n * bytesPerFrame;
    AudioQueueEnqueueBuffer(_queue, buf, 0, NULL);
}

- (void)queueStoppedRunning {
    if (_tearingDown || !_eof) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_eof) return;
        [self.delegate audioEngineDidFinishTrack:self];
    });
}

#pragma mark Public API

- (BOOL)playDecoder:(id<MBAudioDecoder>)decoder {
    [self disposeQueue];
    pthread_mutex_lock(&_lock);
    _decoder = decoder;
    pthread_mutex_unlock(&_lock);
    _paused = NO;
    return [self startQueueAtFrame:0];
}

- (void)pause {
    if (!_queue || _paused) return;
    _paused = YES;
    AudioQueuePause(_queue);
}

- (void)resume {
    if (!_decoder) return;
    _paused = NO;
    if (!_queue) { [self startQueueAtFrame:_baseFrame]; return; }
    OSStatus st = [self startRunning];
    if (st != noErr) {   // e.g. queue invalidated by an interruption: rebuild it where we were
        NSLog(@"[MusicBox] resume failed (%d), rebuilding queue", (int)st);
        [self startQueueAtFrame:(SInt64)(self.currentTime * _decoder.sampleRate)];
    }
}

- (void)stop {
    [self disposeQueue];
    pthread_mutex_lock(&_lock);
    _decoder = nil;
    pthread_mutex_unlock(&_lock);
    _paused = NO; _baseFrame = 0;
}

- (void)seekToTime:(NSTimeInterval)time {
    if (!_decoder) return;
    SInt64 frame = (SInt64)(MAX(0, time) * _decoder.sampleRate);
    if (_decoder.totalFrames > 0 && frame >= _decoder.totalFrames) frame = _decoder.totalFrames - 1;
    [self startQueueAtFrame:frame];
}

- (double)sampleRate { id<MBAudioDecoder> d = _decoder; return d ? d.sampleRate : 0; }
- (UInt32)channels { id<MBAudioDecoder> d = _decoder; return d ? d.channels : 0; }

- (BOOL)isPlaying { return _queue != NULL && !_paused && !_eof; }

- (NSTimeInterval)duration {
    id<MBAudioDecoder> d = _decoder;
    return (d && d.totalFrames > 0) ? d.totalFrames / d.sampleRate : 0;
}

- (NSTimeInterval)currentTime {
    id<MBAudioDecoder> d = _decoder;
    if (!d) return 0;
    Float64 played = 0;
    if (_queue) {
        AudioTimeStamp ts;
        if (AudioQueueGetCurrentTime(_queue, NULL, &ts, NULL) == noErr && (ts.mFlags & kAudioTimeStampSampleTimeValid))
            played = MAX(0, ts.mSampleTime);
    }
    NSTimeInterval t = (_baseFrame + played) / d.sampleRate;
    NSTimeInterval dur = self.duration;
    return dur > 0 ? MIN(t, dur) : t;
}

@end

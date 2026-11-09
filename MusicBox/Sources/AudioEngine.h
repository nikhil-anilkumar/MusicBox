// AudioEngine: plays any MBAudioDecoder through an AudioQueue.
#import <Foundation/Foundation.h>
#import "AudioDecoder.h"

@class MBAudioEngine;
@protocol MBAudioEngineDelegate <NSObject>
- (void)audioEngineDidFinishTrack:(MBAudioEngine *)engine;   // called on the main thread
@end

@interface MBAudioEngine : NSObject
@property (nonatomic, weak) id<MBAudioEngineDelegate> delegate;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) double sampleRate;     // of the current decoder, 0 if none
@property (nonatomic, readonly) UInt32 channels;

- (BOOL)playDecoder:(id<MBAudioDecoder>)decoder;   // replaces whatever is playing
- (void)pause;
- (void)resume;
- (void)stop;
- (void)seekToTime:(NSTimeInterval)time;
@end

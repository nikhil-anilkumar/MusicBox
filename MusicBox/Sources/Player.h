// Player: the play queue, shuffle/repeat, audio session, interruptions,
// headphone unplug, lock-screen "Now Playing" info and remote controls.
#import <UIKit/UIKit.h>
#import "Library.h"

extern NSString *const MBPlayerStateDidChangeNotification;   // play/pause/track change

typedef enum { MBRepeatOff = 0, MBRepeatAll, MBRepeatOne } MBRepeatMode;

@interface MBPlayer : NSObject
+ (MBPlayer *)shared;
@property (nonatomic, readonly) MBTrack *currentTrack;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) NSTimeInterval currentTime;
@property (nonatomic, readonly) NSTimeInterval duration;
@property (nonatomic, readonly) double sampleRate;     // output rate of the current track
@property (nonatomic, readonly) UInt32 channels;
@property (nonatomic) BOOL shuffle;
@property (nonatomic) MBRepeatMode repeatMode;
@property (nonatomic, readonly, copy) NSString *lastError;

- (void)playTracks:(NSArray *)tracks startingAt:(NSUInteger)index;
- (void)togglePlayPause;
- (void)play;
- (void)pause;
- (void)next;
- (void)previous;
- (void)seekToTime:(NSTimeInterval)t;
- (void)handleRemoteControlEvent:(UIEvent *)event;
@end

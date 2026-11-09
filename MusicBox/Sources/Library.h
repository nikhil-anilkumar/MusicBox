#import <UIKit/UIKit.h>

@interface MBTrack : NSObject
@property (nonatomic, strong) NSURL *url;              // file:// or ipod-library://
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, copy) NSString *format;          // "MP3", "FLAC", ...
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic) BOOL isFile;                     // lives in Documents (deletable)
@property (nonatomic, strong) id mediaItem;            // MPMediaItem for library tracks
@property (nonatomic) unsigned long long fileSize;
@property (nonatomic, strong) NSDate *dateAdded;
- (UIImage *)artwork;                                  // loaded lazily, may be nil
- (BOOL)isLossless;                                    // ALAC, FLAC, WAV, AIFF, CAF
- (BOOL)isLossy;                                       // MP3, AAC, OGG, AMR...
@end

extern NSString *const MBLibraryDidChangeNotification;

@interface MBLibrary : NSObject
+ (MBLibrary *)shared;
@property (nonatomic, readonly) NSArray *fileTracks;      // MBTrack, from Documents
@property (nonatomic, readonly) NSArray *ipodTracks;      // MBTrack, from the Music app library
@property (nonatomic, readonly) NSArray *allTracks;       // files + library
@property (nonatomic, readonly) BOOL loading;
+ (NSString *)documentsPath;
- (void)reload;                                           // async, posts MBLibraryDidChangeNotification
- (BOOL)deleteTrack:(MBTrack *)track;
- (MBTrack *)trackForFileURL:(NSURL *)url;                // cached track for a file (created if needed)
- (NSURL *)importFileAtURL:(NSURL *)url;                  // copies into Documents, returns new URL
@end

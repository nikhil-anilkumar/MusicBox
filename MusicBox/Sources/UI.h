#import <UIKit/UIKit.h>
@class MBTrack;

// Tab 1: every song (files + Music library) with search, quality scope, format filter and sorting.
@interface MBSongsViewController : UITableViewController
@property (nonatomic, copy) NSString *searchText;
@property (nonatomic) NSInteger scope;              // 0 all, 1 lossless, 2 lossy
@property (nonatomic, copy) NSString *formatFilter; // nil = any format
@property (nonatomic) NSInteger sortMode;           // MBSort*
- (NSArray *)filteredTracks;
@end

enum { MBSortTitle = 0, MBSortArtist, MBSortAlbum, MBSortDuration, MBSortRecent };

// Tab 2: browse the app's Documents folder like a file manager.
@interface MBFilesViewController : UITableViewController
- (id)initWithPath:(NSString *)path;
@end

@interface MBNowPlayingViewController : UIViewController
@end

// Details about a track: tags, codec, sample rate, bitrate, file info.
@interface MBTrackInfoViewController : UITableViewController
- (id)initWithTrack:(MBTrack *)track;
@end

// Window that receives lock-screen / headset remote-control events.
@interface MBWindow : UIWindow
@end

// Small vector icons drawn at runtime (crisp on Retina, no image assets needed).
typedef enum { MBIconPlay, MBIconPause, MBIconNext, MBIconPrev, MBIconShuffle, MBIconRepeat, MBIconRepeatOne,
               MBIconNote, MBIconFolder, MBIconFile, MBIconVinyl } MBIcon;
UIImage *MBIconImage(MBIcon icon, CGFloat size, UIColor *color);
NSString *MBFormatTime(NSTimeInterval t);
NSString *MBFormatBytes(unsigned long long bytes);
UIColor *MBAccentColor(void);
// Shows/hides the "Now Playing" bar button on a list screen.
void MBUpdateNowPlayingButton(UIViewController *vc);
void MBShowNowPlaying(UINavigationController *nav);

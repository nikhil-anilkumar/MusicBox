#import "UI.h"
#import "Library.h"
#import "Player.h"
#import "AudioDecoder.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

// Each section: @[title, @[ @[key, value], ... ]]
@implementation MBTrackInfoViewController {
    MBTrack *_track;
    NSArray *_sections;
}

- (id)initWithTrack:(MBTrack *)track {
    if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
        _track = track;
        self.title = @"Details";
        self.hidesBottomBarWhenPushed = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _sections = @[@[@"", @[@[@"Loading…", @""]]]];
    // Opening the file to read codec details can take a moment; do it off the main thread.
    MBTrack *t = _track;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *tech = t.isFile ? [MBTagReader technicalInfoForFileURL:t.url] : [MBTrackInfoViewController libraryTechInfo:t];
        NSArray *sections = [MBTrackInfoViewController sectionsForTrack:t tech:tech];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_sections = sections;
            [self.tableView reloadData];
            NSLog(@"[MusicBox] details for %@: %@", t.title, tech);
        });
    });
}

+ (NSDictionary *)libraryTechInfo:(MBTrack *)t {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:@"iOS AVFoundation (AVAssetReader)" forKey:@"decoder"];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:t.url options:nil];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (tracks.count) {
        AVAssetTrack *at = tracks[0];
        if (at.estimatedDataRate > 0) info[@"bitrate"] = @((NSUInteger)(at.estimatedDataRate / 1000));
        if (at.formatDescriptions.count) {
            const AudioStreamBasicDescription *d =
                CMAudioFormatDescriptionGetStreamBasicDescription((__bridge CMAudioFormatDescriptionRef)at.formatDescriptions[0]);
            if (d) {
                info[@"sampleRate"] = @(d->mSampleRate);
                info[@"channels"] = @(d->mChannelsPerFrame);
                info[@"codec"] = d->mFormatID == kAudioFormatMPEGLayer3 ? @"MPEG-1 Layer 3 (MP3)" :
                                 d->mFormatID == kAudioFormatMPEG4AAC ? @"AAC-LC" :
                                 d->mFormatID == kAudioFormatAppleLossless ? @"Apple Lossless (ALAC)" :
                                 d->mFormatID == kAudioFormatLinearPCM ? @"PCM" : @"Other";
            }
        }
    }
    return info;
}

static NSString *MBChannelsName(NSUInteger n) {
    return n == 1 ? @"Mono" : n == 2 ? @"Stereo" : [NSString stringWithFormat:@"%lu channels", (unsigned long)n];
}

+ (NSArray *)sectionsForTrack:(MBTrack *)t tech:(NSDictionary *)tech {
    NSMutableArray *sections = [NSMutableArray array];
    void (^add)(NSMutableArray *, NSString *, id) = ^(NSMutableArray *rows, NSString *k, id v) {
        NSString *s = [v description];
        if (s.length) [rows addObject:@[k, s]];
    };

    NSMutableArray *song = [NSMutableArray array];
    add(song, @"Title", t.title);
    add(song, @"Artist", t.artist);
    add(song, @"Album", t.album);
    if (t.mediaItem) add(song, @"Genre", [t.mediaItem valueForProperty:MPMediaItemPropertyGenre]);
    double dur = [tech[@"duration"] doubleValue] ?: t.duration;
    if (dur > 0) add(song, @"Duration", MBFormatTime(dur));
    add(song, @"Source", t.mediaItem ? @"Music Library" : @"Files");
    [sections addObject:@[@"Song", song]];

    NSMutableArray *audio = [NSMutableArray array];
    add(audio, @"Codec", tech[@"codec"]);
    add(audio, @"Container", tech[@"container"]);
    if (tech[@"sampleRate"]) add(audio, @"Sample Rate", [NSString stringWithFormat:@"%g kHz", [tech[@"sampleRate"] doubleValue] / 1000]);
    if ([tech[@"bitDepth"] intValue] > 0) add(audio, @"Bit Depth", [NSString stringWithFormat:@"%d-bit", [tech[@"bitDepth"] intValue]]);
    if (tech[@"channels"]) add(audio, @"Channels", MBChannelsName([tech[@"channels"] unsignedIntegerValue]));
    if ([tech[@"bitrate"] intValue] > 0) add(audio, @"Bitrate", [NSString stringWithFormat:@"%d kbps", [tech[@"bitrate"] intValue]]);
    if (t.isFile) add(audio, @"Quality", t.isLossless ? @"Lossless" : @"Lossy (compressed)");
    add(audio, @"Decoder", tech[@"decoder"]);
    add(audio, @"Encoder", tech[@"encoder"]);
    [sections addObject:@[@"Audio", audio]];

    if (t.isFile) {
        NSMutableArray *file = [NSMutableArray array];
        NSString *docs = [MBLibrary documentsPath];
        NSString *dir = [t.url.path stringByDeletingLastPathComponent];
        NSString *rel = [dir hasPrefix:docs] ? [dir substringFromIndex:docs.length] : dir;
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:t.url.path error:NULL];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.dateStyle = NSDateFormatterMediumStyle; df.timeStyle = NSDateFormatterShortStyle;
        add(file, @"Name", t.url.lastPathComponent);
        add(file, @"Folder", [@"Files" stringByAppendingString:rel]);
        add(file, @"Size", [NSString stringWithFormat:@"%@ (%@ bytes)", MBFormatBytes(attrs.fileSize),
                            [NSNumberFormatter localizedStringFromNumber:@(attrs.fileSize) numberStyle:NSNumberFormatterDecimalStyle]]);
        if (attrs.fileModificationDate) add(file, @"Modified", [df stringFromDate:attrs.fileModificationDate]);
        [sections addObject:@[@"File", file]];
    }
    if ([MBPlayer shared].currentTrack != t) [sections addObject:@[@"", @[@[@"Play This Song", @""]]]];
    return sections;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _sections.count; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return [_sections[s][1] count]; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s { return [_sections[s][0] length] ? _sections[s][0] : nil; }

// A row stacks its value under the label only when the value won't fit beside it (keeps the list uniform).
- (BOOL)isLongRow:(NSArray *)row {
    if ([row[0] isEqualToString:@"Play This Song"]) return NO;
    CGFloat keyW = [row[0] sizeWithFont:[UIFont boldSystemFontOfSize:17]].width;
    CGFloat valW = [row[1] sizeWithFont:[UIFont systemFontOfSize:17]].width;
    return keyW + valW + 40 > self.tableView.bounds.size.width - 40;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *row = _sections[ip.section][1][ip.row];
    if (![self isLongRow:row]) return 44;
    CGSize sz = [row[1] sizeWithFont:[UIFont systemFontOfSize:15] constrainedToSize:CGSizeMake(260, 200)
                       lineBreakMode:NSLineBreakByCharWrapping];
    return MAX(44, sz.height + 30);
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSArray *row = _sections[ip.section][1][ip.row];
    NSString *key = row[0], *val = row[1];
    BOOL action = [key isEqualToString:@"Play This Song"];
    BOOL longRow = !action && [self isLongRow:row];
    NSString *rid = action ? @"action" : longRow ? @"long" : @"kv";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:rid];
    if (!cell) {
        // Long values (file names, codec strings) get the full width on a second line.
        cell = [[UITableViewCell alloc] initWithStyle:longRow ? UITableViewCellStyleSubtitle : UITableViewCellStyleValue1 reuseIdentifier:rid];
        cell.selectionStyle = action ? UITableViewCellSelectionStyleBlue : UITableViewCellSelectionStyleNone;
    }
    if (action) {
        cell.textLabel.text = key;
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIColor colorWithRed:0.62 green:0.46 blue:0.10 alpha:1];
    } else if (longRow) {
        cell.textLabel.text = key;
        cell.textLabel.font = [UIFont systemFontOfSize:12];
        cell.textLabel.textColor = [UIColor grayColor];
        cell.detailTextLabel.text = val;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
        cell.detailTextLabel.textColor = [UIColor blackColor];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByCharWrapping;
    } else {
        cell.textLabel.text = key;
        cell.detailTextLabel.text = val;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (![_sections[ip.section][1][ip.row][0] isEqualToString:@"Play This Song"]) return;
    [[MBPlayer shared] playTracks:@[_track] startingAt:0];
    MBShowNowPlaying(self.navigationController);
}

@end

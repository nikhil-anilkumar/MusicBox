#import "Library.h"
#import "AudioDecoder.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

NSString *const MBLibraryDidChangeNotification = @"MBLibraryDidChangeNotification";

@implementation MBTrack {
    UIImage *_artwork;
    BOOL _artworkLoaded;
}

- (BOOL)isLossless {
    return [[NSSet setWithObjects:@"ALAC", @"FLAC", @"WAV", @"WAVE", @"AIFF", @"AIF", @"AIFC", @"CAF", nil] containsObject:self.format];
}

- (BOOL)isLossy { return !self.mediaItem && !self.isLossless; }

- (UIImage *)artwork {
    if (_artworkLoaded) return _artwork;
    _artworkLoaded = YES;
    if (self.mediaItem) {
        MPMediaItemArtwork *art = [self.mediaItem valueForProperty:MPMediaItemPropertyArtwork];
        _artwork = [art imageWithSize:CGSizeMake(320, 320)];
    } else if (self.isFile) {
        NSData *data = [MBTagReader tagsForFileURL:self.url][@"artwork"];
        if (!data) {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:self.url options:nil];
            for (AVMetadataItem *item in [AVMetadataItem metadataItemsFromArray:asset.commonMetadata
                                                                        withKey:AVMetadataCommonKeyArtwork
                                                                       keySpace:AVMetadataKeySpaceCommon]) {
                id v = item.value;
                if ([v isKindOfClass:[NSData class]]) data = v;                       // iTunes/MP4 atoms
                else if ([v isKindOfClass:[NSDictionary class]]) data = v[@"data"];   // ID3 APIC on iOS 6
                if (data) break;
            }
        }
        if (data) _artwork = [UIImage imageWithData:data];
    }
    return _artwork;
}
@end

@implementation MBLibrary {
    dispatch_queue_t _scanQueue;
    NSDictionary *_byPath;      // file path -> MBTrack
}

+ (MBLibrary *)shared {
    static MBLibrary *lib;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lib = [[MBLibrary alloc] init]; });
    return lib;
}

+ (NSString *)documentsPath {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
}

- (id)init {
    if ((self = [super init])) {
        _scanQueue = dispatch_queue_create("musicbox.scan", DISPATCH_QUEUE_SERIAL);
        _fileTracks = @[]; _ipodTracks = @[];
    }
    return self;
}

static NSString *MBStringOrNil(NSString *s) { return s.length ? s : nil; }

- (MBTrack *)trackForFile:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    MBTrack *t = [[MBTrack alloc] init];
    t.url = url; t.isFile = YES;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    t.fileSize = attrs.fileSize;
    t.dateAdded = attrs.fileModificationDate;
    NSString *ext = url.pathExtension.lowercaseString;
    t.format = [ext isEqualToString:@"oga"] ? @"OGG" : ext.uppercaseString;

    NSDictionary *tags = [MBTagReader tagsForFileURL:url];
    if (tags.count) {
        t.title = tags[@"title"]; t.artist = tags[@"artist"]; t.album = tags[@"album"];
        t.duration = [tags[@"duration"] doubleValue];
    } else {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
        for (AVMetadataItem *item in asset.commonMetadata) {
            if (![item.value isKindOfClass:[NSString class]]) continue;
            if ([item.commonKey isEqualToString:AVMetadataCommonKeyTitle]) t.title = (NSString *)item.value;
            else if ([item.commonKey isEqualToString:AVMetadataCommonKeyArtist]) t.artist = (NSString *)item.value;
            else if ([item.commonKey isEqualToString:AVMetadataCommonKeyAlbumName]) t.album = (NSString *)item.value;
        }
        Float64 secs = CMTimeGetSeconds(asset.duration);
        t.duration = isfinite(secs) ? secs : 0;
        // Formats like ALAC hide inside .m4a: name the codec rather than the container.
        NSArray *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];   // (no -firstObject on iOS 6)
        AVAssetTrack *track = audioTracks.count ? audioTracks[0] : nil;
        if (track.formatDescriptions.count) {
            CMAudioFormatDescriptionRef fd = (__bridge CMAudioFormatDescriptionRef)track.formatDescriptions[0];
            const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd);
            if (asbd && asbd->mFormatID == kAudioFormatAppleLossless) t.format = @"ALAC";
            else if (asbd && (asbd->mFormatID == kAudioFormatMPEG4AAC || asbd->mFormatID == kAudioFormatMPEG4AAC_HE)) t.format = @"AAC";
        }
    }
    t.title = MBStringOrNil(t.title) ?: [[path lastPathComponent] stringByDeletingPathExtension];
    t.artist = MBStringOrNil(t.artist) ?: @"Unknown Artist";
    return t;
}

- (NSArray *)scanDocuments {
    NSString *docs = [MBLibrary documentsPath];
    NSSet *exts = [MBDecoderFactory supportedExtensions];
    NSMutableArray *tracks = [NSMutableArray array];
    NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath:docs];
    for (NSString *rel in en) {
        if ([rel hasPrefix:@"Inbox"] || [rel hasPrefix:@"."]) continue;
        if (![exts containsObject:rel.pathExtension.lowercaseString]) continue;
        [tracks addObject:[self trackForFile:[docs stringByAppendingPathComponent:rel]]];
    }
    [tracks sortUsingComparator:^NSComparisonResult(MBTrack *a, MBTrack *b) {
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    return tracks;
}

- (NSArray *)scanIPodLibrary {
    NSMutableArray *tracks = [NSMutableArray array];
    for (MPMediaItem *item in [[MPMediaQuery songsQuery] items]) {
        NSURL *url = [item valueForProperty:MPMediaItemPropertyAssetURL];
        if (!url) continue;   // DRM-protected or cloud-only: not decodable by apps
        MBTrack *t = [[MBTrack alloc] init];
        t.url = url; t.mediaItem = item;
        t.title = MBStringOrNil([item valueForProperty:MPMediaItemPropertyTitle]) ?: @"Unknown";
        t.artist = MBStringOrNil([item valueForProperty:MPMediaItemPropertyArtist]) ?: @"Unknown Artist";
        t.album = [item valueForProperty:MPMediaItemPropertyAlbumTitle];
        t.duration = [[item valueForProperty:MPMediaItemPropertyPlaybackDuration] doubleValue];
        t.format = @"Library";
        [tracks addObject:t];
    }
    return tracks;
}

- (void)reload {
    _loading = YES;
    dispatch_async(_scanQueue, ^{
        NSArray *files = [self scanDocuments];
        NSArray *ipod = [self scanIPodLibrary];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_fileTracks = files;
            self->_ipodTracks = ipod;
            [self indexFiles];
            self->_loading = NO;
            NSLog(@"[MusicBox] library: %lu files, %lu iPod library songs", (unsigned long)files.count, (unsigned long)ipod.count);
            [[NSNotificationCenter defaultCenter] postNotificationName:MBLibraryDidChangeNotification object:self];
        });
    });
}

- (NSArray *)allTracks { return [_fileTracks arrayByAddingObjectsFromArray:_ipodTracks]; }

- (void)indexFiles {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (MBTrack *t in _fileTracks) d[t.url.path.stringByStandardizingPath] = t;
    _byPath = d;
}

- (MBTrack *)trackForFileURL:(NSURL *)url {
    NSString *key = url.path.stringByStandardizingPath;
    MBTrack *t = _byPath[key];
    if (!t) {
        t = [self trackForFile:url.path];
        NSMutableDictionary *d = [_byPath mutableCopy] ?: [NSMutableDictionary dictionary];
        d[key] = t;
        _byPath = d;
    }
    return t;
}

- (BOOL)deleteTrack:(MBTrack *)track {
    if (!track.isFile) return NO;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtURL:track.url error:NULL];
    if (ok) {
        NSMutableArray *m = [_fileTracks mutableCopy];
        [m removeObject:track];
        _fileTracks = m;
        [self indexFiles];
    }
    return ok;
}

- (NSURL *)importFileAtURL:(NSURL *)url {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *docs = [MBLibrary documentsPath];
    NSString *name = url.lastPathComponent;
    NSString *dest = [docs stringByAppendingPathComponent:name];
    for (int i = 2; [fm fileExistsAtPath:dest]; i++)
        dest = [docs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d.%@",
                [name stringByDeletingPathExtension], i, name.pathExtension]];
    NSError *err = nil;
    if (![fm moveItemAtPath:url.path toPath:dest error:&err] && ![fm copyItemAtPath:url.path toPath:dest error:&err]) {
        NSLog(@"[MusicBox] import failed: %@", err);
        return nil;
    }
    return [NSURL fileURLWithPath:dest];
}

@end

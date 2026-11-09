#import "UI.h"
#import "Library.h"
#import "Player.h"
#import "AudioDecoder.h"

@interface MBFileEntry : NSObject
@property (nonatomic, copy) NSString *name, *path;
@property (nonatomic) BOOL isDir, isAudio;
@property (nonatomic) unsigned long long size;
@property (nonatomic) NSUInteger childCount;
@end
@implementation MBFileEntry
@end

@implementation MBFilesViewController {
    NSString *_path;
    NSArray *_entries;
}

- (id)init { return [self initWithPath:[MBLibrary documentsPath]]; }

- (id)initWithPath:(NSString *)path {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _path = [path copy];
        BOOL root = [path isEqualToString:[MBLibrary documentsPath]];
        self.title = root ? @"Files" : path.lastPathComponent;
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Files" image:MBIconImage(MBIconFolder, 30, [UIColor blackColor]) tag:1];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 52;
    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = rc;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(reload) name:MBLibraryDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(playerChanged) name:MBPlayerStateDidChangeNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reload]; MBUpdateNowPlayingButton(self); }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self becomeFirstResponder]; }
- (void)refresh { [[MBLibrary shared] reload]; }
- (void)playerChanged { MBUpdateNowPlayingButton(self); [self.tableView reloadData]; }

- (void)reload {
    [self.refreshControl endRefreshing];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSSet *audio = [MBDecoderFactory supportedExtensions];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:_path error:NULL]) {
        if ([name hasPrefix:@"."]) continue;
        MBFileEntry *e = [[MBFileEntry alloc] init];
        e.name = name;
        e.path = [_path stringByAppendingPathComponent:name];
        NSDictionary *attrs = [fm attributesOfItemAtPath:e.path error:NULL];
        e.isDir = [attrs.fileType isEqualToString:NSFileTypeDirectory];
        if (e.isDir) e.childCount = [fm contentsOfDirectoryAtPath:e.path error:NULL].count;
        else e.size = attrs.fileSize;
        e.isAudio = !e.isDir && [audio containsObject:name.pathExtension.lowercaseString];
        [entries addObject:e];
    }
    [entries sortUsingComparator:^NSComparisonResult(MBFileEntry *a, MBFileEntry *b) {
        if (a.isDir != b.isDir) return a.isDir ? NSOrderedAscending : NSOrderedDescending;   // folders first
        return [a.name localizedStandardCompare:b.name];
    }];
    _entries = entries;
    [self.tableView reloadData];
    [self updateFooter];
}

- (void)updateFooter {
    unsigned long long used = 0; NSUInteger nAudio = 0;
    for (MBFileEntry *e in _entries) { used += e.size; if (e.isAudio) nAudio++; }
    NSDictionary *fs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:_path error:NULL];
    unsigned long long freeBytes = [fs[NSFileSystemFreeSize] unsignedLongLongValue];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 80)];
    l.numberOfLines = 0; l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:13]; l.textColor = [UIColor grayColor]; l.backgroundColor = [UIColor clearColor];
    l.text = _entries.count == 0
        ? @"This folder is empty.\nCopy music here with iTunes File Sharing."
        : [NSString stringWithFormat:@"%lu items · %lu playable · %@\n%@ free on device", (unsigned long)_entries.count,
           (unsigned long)nAudio, MBFormatBytes(used), MBFormatBytes(freeBytes)];
    self.tableView.tableFooterView = l;
}

- (NSArray *)audioEntries {
    return [_entries filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isAudio == YES"]];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _entries.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"file"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"file"];
    MBFileEntry *e = _entries[ip.row];
    cell.textLabel.text = e.name;
    cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
    UIColor *gray = [UIColor colorWithWhite:0.6 alpha:1];
    if (e.isDir) {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu item%@", (unsigned long)e.childCount, e.childCount == 1 ? @"" : @"s"];
        cell.imageView.image = MBIconImage(MBIconFolder, 28, MBAccentColor());
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.textColor = [UIColor blackColor];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    } else if (e.isAudio) {
        MBTrack *t = [[MBLibrary shared] trackForFileURL:[NSURL fileURLWithPath:e.path]];
        NSMutableArray *parts = [NSMutableArray arrayWithObjects:t.format, MBFormatBytes(e.size), nil];
        if (t.duration > 0) [parts addObject:MBFormatTime(t.duration)];
        cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
        BOOL current = [[MBPlayer shared].currentTrack.url.path isEqualToString:e.path];
        cell.imageView.image = current ? MBIconImage([MBPlayer shared].isPlaying ? MBIconPlay : MBIconPause, 28, MBAccentColor())
                                       : MBIconImage(MBIconFile, 28, [UIColor colorWithWhite:0.35 alpha:1]);
        cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;   // (i)-style details button
        cell.textLabel.textColor = [UIColor blackColor];
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    } else {
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · not audio", MBFormatBytes(e.size)];
        cell.imageView.image = MBIconImage(MBIconFile, 28, [UIColor colorWithWhite:0.8 alpha:1]);
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.textLabel.textColor = gray;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    MBFileEntry *e = _entries[ip.row];
    if (e.isDir) {
        [self.navigationController pushViewController:[[MBFilesViewController alloc] initWithPath:e.path] animated:YES];
    } else if (e.isAudio) {
        // Queue = the playable files in this folder, in the order shown.
        NSArray *audio = [self audioEntries];
        NSMutableArray *tracks = [NSMutableArray array];
        for (MBFileEntry *a in audio) [tracks addObject:[[MBLibrary shared] trackForFileURL:[NSURL fileURLWithPath:a.path]]];
        [[MBPlayer shared] playTracks:tracks startingAt:[audio indexOfObject:e]];
        MBShowNowPlaying(self.navigationController);
    }
}

- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    MBFileEntry *e = _entries[ip.row];
    MBTrack *t = [[MBLibrary shared] trackForFileURL:[NSURL fileURLWithPath:e.path]];
    [self.navigationController pushViewController:[[MBTrackInfoViewController alloc] initWithTrack:t] animated:YES];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)ip {
    MBFileEntry *e = _entries[ip.row];
    if ([[MBPlayer shared].currentTrack.url.path hasPrefix:e.path]) [[MBPlayer shared] pause];
    if ([[NSFileManager defaultManager] removeItemAtPath:e.path error:NULL]) {
        NSMutableArray *m = [_entries mutableCopy];
        [m removeObjectAtIndex:ip.row];
        _entries = m;
        [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self updateFooter];
        [[MBLibrary shared] reload];   // keep the Songs tab in sync
    }
}

@end

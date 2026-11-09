#import "UI.h"
#import "Library.h"
#import "Player.h"

static NSString *const kMBLibrarySource = @"Music Library";

@interface MBSongsViewController () <UISearchBarDelegate, UIActionSheetDelegate>
@end

@implementation MBSongsViewController {
    UISearchBar *_search;
    UIBarButtonItem *_sortButton;
    NSArray *_rows;
    UIActionSheet *_sortSheet, *_filterSheet;
    NSArray *_filterChoices;   // format names shown in the filter sheet (index-aligned after "All Formats")
}

- (id)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"Songs";
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Songs" image:MBIconImage(MBIconVinyl, 30, [UIColor blackColor]) tag:0];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = 56;

    _search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    _search.placeholder = @"Search songs, artists, albums";
    _search.delegate = self;
    _search.tintColor = [UIColor colorWithWhite:0.15 alpha:1];
    _search.scopeButtonTitles = @[@"All", @"Lossless", @"Lossy"];
    _search.showsScopeBar = YES;
    _search.autocorrectionType = UITextAutocorrectionTypeNo;
    [_search sizeToFit];
    self.tableView.tableHeaderView = _search;

    _sortButton = [[UIBarButtonItem alloc] initWithTitle:@"Sort" style:UIBarButtonItemStyleBordered
                                                  target:self action:@selector(showSort)];
    [self updateFilterButton];

    UIRefreshControl *rc = [[UIRefreshControl alloc] init];
    [rc addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = rc;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(libraryChanged) name:MBLibraryDidChangeNotification object:nil];
    [nc addObserver:self selector:@selector(playerChanged) name:MBPlayerStateDidChangeNotification object:nil];
    [self reloadRows];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; [self becomeFirstResponder]; }
- (void)refresh { [[MBLibrary shared] reload]; }
- (void)libraryChanged { [self.refreshControl endRefreshing]; [self reloadRows]; }
- (void)playerChanged { MBUpdateNowPlayingButton(self); [self.tableView reloadData]; }

#pragma mark Filtering

- (void)setSearchText:(NSString *)s { _searchText = [s copy]; [self reloadRows]; }
- (void)setScope:(NSInteger)scope { _scope = scope; _search.selectedScopeButtonIndex = scope; [self reloadRows]; }
- (void)setFormatFilter:(NSString *)f { _formatFilter = [f copy]; [self updateFilterButton]; [self reloadRows]; }
- (void)setSortMode:(NSInteger)m { _sortMode = m; [self reloadRows]; }

- (NSArray *)filteredTracks {
    NSString *q = [_searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *out = [NSMutableArray array];
    for (MBTrack *t in [MBLibrary shared].allTracks) {
        if (_scope == 1 && !t.isLossless) continue;
        if (_scope == 2 && !t.isLossy) continue;
        if (_formatFilter) {
            if ([_formatFilter isEqualToString:kMBLibrarySource] ? t.mediaItem == nil : ![t.format isEqualToString:_formatFilter]) continue;
        }
        if (q.length) {
            NSString *hay = [NSString stringWithFormat:@"%@\n%@\n%@\n%@", t.title, t.artist, t.album ?: @"", t.format ?: @""];
            if ([hay rangeOfString:q options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location == NSNotFound) continue;
        }
        [out addObject:t];
    }
    NSInteger mode = _sortMode;
    [out sortUsingComparator:^NSComparisonResult(MBTrack *a, MBTrack *b) {
        NSComparisonResult r = NSOrderedSame;
        switch (mode) {
            case MBSortArtist: r = [a.artist localizedCaseInsensitiveCompare:b.artist]; break;
            case MBSortAlbum: r = [(a.album ?: @"￿") localizedCaseInsensitiveCompare:(b.album ?: @"￿")]; break;
            case MBSortDuration: r = a.duration < b.duration ? NSOrderedAscending : a.duration > b.duration ? NSOrderedDescending : NSOrderedSame; break;
            case MBSortRecent: r = [(b.dateAdded ?: [NSDate distantPast]) compare:(a.dateAdded ?: [NSDate distantPast])]; break;
        }
        return r != NSOrderedSame ? r : [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    return out;
}

- (void)reloadRows {
    _rows = [self filteredTracks];
    [self.tableView reloadData];
    [self updateFooter];
}

- (void)updateFilterButton {
    NSString *title = _formatFilter ? [NSString stringWithFormat:@"%@ ✕", _formatFilter] : @"Filter";
    UIBarButtonItem *b = [[UIBarButtonItem alloc] initWithTitle:title style:UIBarButtonItemStyleBordered
                                                         target:self action:@selector(showFilter)];
    if (_formatFilter) b.tintColor = [UIColor colorWithRed:0.62 green:0.46 blue:0.10 alpha:1];
    // Sort and Filter sit on the left; Now Playing keeps the right side.
    if (_sortButton) self.navigationItem.leftBarButtonItems = @[_sortButton, b];
}

- (void)updateFooter {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 320, 80)];
    l.numberOfLines = 0; l.textAlignment = NSTextAlignmentCenter;
    l.font = [UIFont systemFontOfSize:13]; l.textColor = [UIColor grayColor]; l.backgroundColor = [UIColor clearColor];
    NSUInteger total = [MBLibrary shared].allTracks.count;
    if ([MBLibrary shared].loading && total == 0) l.text = @"Loading…";
    else if (total == 0) l.text = @"No songs yet.\nAdd music with iTunes File Sharing or \"Open in MusicBox\".";
    else if (_rows.count == total) l.text = [NSString stringWithFormat:@"%lu songs", (unsigned long)total];
    else l.text = [NSString stringWithFormat:@"Showing %lu of %lu songs", (unsigned long)_rows.count, (unsigned long)total];
    self.tableView.tableFooterView = l;
}

#pragma mark Search bar

- (void)searchBar:(UISearchBar *)bar textDidChange:(NSString *)text { self.searchText = text; }
- (void)searchBar:(UISearchBar *)bar selectedScopeButtonIndexDidChange:(NSInteger)idx { _scope = idx; [self reloadRows]; }
- (void)searchBarSearchButtonClicked:(UISearchBar *)bar { [bar resignFirstResponder]; }
- (void)searchBarTextDidBeginEditing:(UISearchBar *)bar { [bar setShowsCancelButton:YES animated:YES]; }
- (void)searchBarTextDidEndEditing:(UISearchBar *)bar { [bar setShowsCancelButton:NO animated:YES]; }
- (void)searchBarCancelButtonClicked:(UISearchBar *)bar { bar.text = @""; self.searchText = nil; [bar resignFirstResponder]; }
- (void)scrollViewWillBeginDragging:(UIScrollView *)sv { [_search resignFirstResponder]; }

#pragma mark Sort / filter sheets

- (void)showSort {
    NSArray *names = @[@"Title", @"Artist", @"Album", @"Duration", @"Recently Added"];
    _sortSheet = [[UIActionSheet alloc] initWithTitle:@"Sort songs by" delegate:self cancelButtonTitle:nil
                                destructiveButtonTitle:nil otherButtonTitles:nil];
    for (NSUInteger i = 0; i < names.count; i++)
        [_sortSheet addButtonWithTitle:i == (NSUInteger)_sortMode ? [names[i] stringByAppendingString:@"  ✓"] : names[i]];
    _sortSheet.cancelButtonIndex = [_sortSheet addButtonWithTitle:@"Cancel"];
    [_sortSheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)showFilter {
    // Offer only the formats that are actually present, with counts.
    NSCountedSet *counts = [NSCountedSet set];
    NSUInteger libCount = 0;
    for (MBTrack *t in [MBLibrary shared].allTracks) { if (t.mediaItem) libCount++; else [counts addObject:t.format]; }
    NSMutableArray *choices = [[[counts allObjects] sortedArrayUsingSelector:@selector(compare:)] mutableCopy];
    if (libCount) [choices addObject:kMBLibrarySource];
    _filterChoices = choices;

    _filterSheet = [[UIActionSheet alloc] initWithTitle:@"Show only" delegate:self cancelButtonTitle:nil
                                  destructiveButtonTitle:nil otherButtonTitles:nil];
    [_filterSheet addButtonWithTitle:_formatFilter ? @"All Formats" : @"All Formats  ✓"];
    for (NSString *f in choices) {
        NSUInteger n = [f isEqualToString:kMBLibrarySource] ? libCount : [counts countForObject:f];
        NSString *title = [NSString stringWithFormat:@"%@ (%lu)%@", f, (unsigned long)n, [f isEqualToString:_formatFilter] ? @"  ✓" : @""];
        [_filterSheet addButtonWithTitle:title];
    }
    _filterSheet.cancelButtonIndex = [_filterSheet addButtonWithTitle:@"Cancel"];
    [_filterSheet showFromTabBar:self.tabBarController.tabBar];
}

- (void)actionSheet:(UIActionSheet *)sheet clickedButtonAtIndex:(NSInteger)i {
    if (i == sheet.cancelButtonIndex || i < 0) return;
    if (sheet == _sortSheet) self.sortMode = i;
    else if (sheet == _filterSheet) self.formatFilter = i == 0 ? nil : _filterChoices[i - 1];
}

#pragma mark Table

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return _rows.count; }

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"song"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"song"];
    MBTrack *t = _rows[ip.row];
    cell.textLabel.text = t.title;
    NSMutableArray *parts = [NSMutableArray arrayWithObject:t.artist];
    if (_sortMode == MBSortAlbum && t.album.length) [parts addObject:t.album];
    if (t.format) [parts addObject:t.format];
    if (t.duration > 0) [parts addObject:MBFormatTime(t.duration)];
    cell.detailTextLabel.text = [parts componentsJoinedByString:@" · "];
    BOOL current = [MBPlayer shared].currentTrack == t;
    cell.imageView.image = current ? MBIconImage([MBPlayer shared].isPlaying ? MBIconPlay : MBIconPause, 18, MBAccentColor()) : nil;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    [_search resignFirstResponder];
    [[MBPlayer shared] playTracks:_rows startingAt:ip.row];
    MBShowNowPlaying(self.navigationController);
}

@end

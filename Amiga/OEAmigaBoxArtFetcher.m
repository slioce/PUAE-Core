// Box art and titles for Amiga games, filled in the way OpenVGDB does it for other systems (see
// OEAmigaBoxArt.h for the matching). Runs only in the OpenEmu process: once the library has loaded, and
// again whenever a save of the library's main context brings in new Amiga games (the importer saves its
// child context into main), it fills in the Amiga games without a cover. Like OpenEmu's own lookup it honours the "automaticallyGetInfo" preference, and it never
// replaces a cover or title that is already there. Covers go through OEDBGame -setBoxImageByURL: and a
// main-context save, exactly like "Add Cover Art from File…" (GameCollectionViewController.swift).

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#import <os/log.h>
#import "OEAmigaBoxArt.h"

static NSString *const box_art_server = @"https://thumbnails.libretro.com/Commodore%20-%20Amiga/Named_Boxarts/";
static NSString *const amiga_system_identifier = @"openemu.system.amiga";
static const NSTimeInterval index_max_age = 7 * 24 * 60 * 60;

@interface OEAmigaBoxArtFetcher : NSObject
@end

@implementation OEAmigaBoxArtFetcher
{
    NSManagedObjectContext *_context;  /* OpenEmu's mainThreadContext; touched on the main thread only */
    NSMutableSet<NSManagedObjectID *> *_pending;
    NSMutableSet<NSString *> *_importedNames;  /* games the writer saved, waiting for processImportedGames */
    dispatch_queue_t _queue;           /* index loading, matching and downloads */
    NSDictionary<NSString *, NSString *> *_index;
    OEAmigaBoxArtMatcher *_matcher;
    os_log_t _log;
}

static OEAmigaBoxArtFetcher *shared_fetcher;

static BOOL is_amiga_game(NSManagedObject *object)
{
    return [object.entity.name isEqualToString:@"Game"]
        && [[object valueForKeyPath:@"system.systemIdentifier"] isEqual:amiga_system_identifier];
}

/* Names of the Amiga games a writer-context save brought in (its notification's userInfo). */
NSArray<NSString *> *OEAmigaInsertedAmigaGameNames(NSDictionary *saveUserInfo)
{
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSManagedObject *object in saveUserInfo[NSInsertedObjectsKey]) {
        NSString *name = is_amiga_game(object) ? [object valueForKey:@"name"] : nil;
        if (name.length)
            [names addObject:name];
    }
    return names;
}

/*
 * The just-imported games named `names`, as main-context IDs. The library window shows main's instance of
 * each game, which still carries the importer's temporary ID; the cover has to go on that instance (an
 * instance fetched by the writer's permanent ID is a second copy the window never sees). Once the writer
 * has saved a game, main can give its instance a permanent ID without Core Data storing it twice, the same
 * way OpenEmu's own info sync does (OEDBItem.permanentID).
 */
NSArray<NSManagedObjectID *> *OEAmigaPrepareImportedGames(NSManagedObjectContext *context, NSArray<NSString *> *names)
{
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Game"];
    request.predicate = [NSPredicate predicateWithFormat:@"system.systemIdentifier == %@ AND boxImage == nil AND name IN %@",
                         amiga_system_identifier, names];
    NSArray<NSManagedObject *> *games = [context executeFetchRequest:request error:nil];
    NSArray<NSManagedObject *> *temporary = [games filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"objectID.isTemporaryID == YES"]];
    if (temporary.count)
        [context obtainPermanentIDsForObjects:temporary error:nil];
    NSMutableArray<NSManagedObjectID *> *ids = [NSMutableArray array];
    for (NSManagedObject *game in games)
        if (!game.objectID.isTemporaryID)
            [ids addObject:game.objectID];
    return ids;
}

/*
 * Amiga games without box art, by permanent ID. A freshly imported game keeps the temporary ID it got in
 * the importer's child context until the writer context has saved it; asking main for a permanent ID
 * before that makes Core Data store the game twice, so such games are left for the writer's save.
 */
NSArray<NSManagedObjectID *> *OEAmigaGamesWithoutBoxArt(NSManagedObjectContext *context)
{
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Game"];
    request.predicate = [NSPredicate predicateWithFormat:@"system.systemIdentifier == %@ AND boxImage == nil", amiga_system_identifier];
    NSArray<NSManagedObject *> *games = [context executeFetchRequest:request error:nil];
    NSMutableArray<NSManagedObjectID *> *ids = [NSMutableArray array];
    for (NSManagedObject *game in games)
        if (!game.objectID.isTemporaryID)
            [ids addObject:game.objectID];
    return ids;
}

/* OELibraryDatabase.default: exported as +defaultDatabase by OpenEmu 2.4.1, as +default by newer sources. */
id OEAmigaDefaultLibraryDatabase(Class databaseClass)
{
    for (NSString *name in @[ @"defaultDatabase", @"default" ]) {
        SEL selector = NSSelectorFromString(name);
        if ([databaseClass respondsToSelector:selector])
            return ((id (*)(id, SEL))[databaseClass methodForSelector:selector])(databaseClass, selector);
    }
    return nil;
}

+ (void)load
{
    Class database = NSClassFromString(@"OpenEmu.OELibraryDatabase");
    if (!database)
        return;  /* OpenEmuHelperApp: no library here */

    shared_fetcher = [self new];
    [NSNotificationCenter.defaultCenter addObserver:shared_fetcher selector:@selector(libraryDidLoad:)
                                               name:@"OELibraryDidLoadNotificationName" object:nil];
    /* The library usually loads before system plugins do, so its notification has already gone by. */
    dispatch_async(dispatch_get_main_queue(), ^{
        id db = OEAmigaDefaultLibraryDatabase(database);
        if (db)
            [shared_fetcher attachToDatabase:db];
        else
            os_log(shared_fetcher->_log, "Library not loaded yet, waiting for it");
    });
}

- (instancetype)init
{
    if ((self = [super init])) {
        _pending = [NSMutableSet set];
        _importedNames = [NSMutableSet set];
        _queue = dispatch_queue_create("org.openemu.Amiga.boxart", DISPATCH_QUEUE_SERIAL);
        _log = os_log_create("org.openemu.Amiga", "boxart");
    }
    return self;
}

- (void)libraryDidLoad:(NSNotification *)notification
{
    [self attachToDatabase:notification.object];
}

- (void)attachToDatabase:(id)database
{
    if (_context || !database)
        return;
    id context = [database valueForKey:@"mainThreadContext"];
    if (![context isKindOfClass:NSManagedObjectContext.class]) {
        os_log_error(_log, "Library has no main context, box art lookup disabled");
        return;
    }
    id writer = [database valueForKey:@"writerContext"];
    if (![writer isKindOfClass:NSManagedObjectContext.class]) {
        os_log_error(_log, "Library has no writer context, box art only at launch");
        writer = nil;
    }
    _context = context;
    if (writer)
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(writerDidSave:)
                                                   name:NSManagedObjectContextDidSaveNotification object:writer];
    os_log(_log, "Watching the library");
    [self fillMissingBoxArt];
}

/* Posted on the writer's queue, so its objects can be read here. An import saves once per game: gather them,
 * and give OELibraryDatabase a moment to merge the save into main. */
- (void)writerDidSave:(NSNotification *)notification
{
    NSArray<NSString *> *names = OEAmigaInsertedAmigaGameNames(notification.userInfo);
    if (names.count == 0 || ![NSUserDefaults.standardUserDefaults boolForKey:@"automaticallyGetInfo"])
        return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_importedNames addObjectsFromArray:names];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(processImportedGames) object:nil];
        [self performSelector:@selector(processImportedGames) withObject:nil afterDelay:1];
    });
}

- (void)processImportedGames
{
    NSArray<NSManagedObjectID *> *games = OEAmigaPrepareImportedGames(_context, _importedNames.allObjects);
    [_importedNames removeAllObjects];
    for (NSManagedObjectID *gameID in games)
        [self lookUpBoxArtForGameWithID:gameID];
}

- (void)fillMissingBoxArt
{
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"automaticallyGetInfo"])
        return;
    NSArray<NSManagedObjectID *> *games = OEAmigaGamesWithoutBoxArt(_context);
    os_log(_log, "%lu Amiga game(s) without box art", (unsigned long)games.count);
    for (NSManagedObjectID *gameID in games)
        [self lookUpBoxArtForGameWithID:gameID];
}

- (void)lookUpBoxArtForGameWithID:(NSManagedObjectID *)gameID
{
    NSString *name = [[_context existingObjectWithID:gameID error:nil] valueForKey:@"name"];
    if (name.length == 0 || [_pending containsObject:gameID])
        return;
    [_pending addObject:gameID];

    dispatch_async(_queue, ^{
        NSURL *imageFile = nil;
        OEAmigaBoxArtMatch *match = [[self matcher] matchForFileName:name];
        if (match)
            imageFile = [self downloadBoxArtNamed:match.boxArtName];
        else
            os_log_info(self->_log, "No box art matches \"%{public}@\"", name);

        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_pending removeObject:gameID];
            if (imageFile)
                [self applyBoxArt:imageFile title:match.title toGameWithID:gameID boxArtName:match.boxArtName];
        });
    });
}

- (void)applyBoxArt:(NSURL *)imageFile title:(NSString *)title toGameWithID:(NSManagedObjectID *)gameID boxArtName:(NSString *)boxArtName
{
    NSManagedObject *game = [_context existingObjectWithID:gameID error:nil];
    SEL setBoxImage = NSSelectorFromString(@"setBoxImageByURL:");
    if (game && ![game valueForKey:@"boxImage"] && [game respondsToSelector:setBoxImage]) {
        ((void (*)(id, SEL, NSURL *))[game methodForSelector:setBoxImage])(game, setBoxImage, imageFile);
        if (![game valueForKey:@"gameTitle"])
            [game setValue:title forKey:@"gameTitle"];
        NSError *error = nil;
        if ([_context save:&error])
            os_log(_log, "Box art \"%{public}@\" set for \"%{public}@\"", boxArtName, title);
        else
            os_log_error(_log, "Could not save box art for \"%{public}@\": %{public}@", title, error.localizedDescription);
    }
    [NSFileManager.defaultManager removeItemAtURL:imageFile error:nil];
}

#pragma mark - Index and downloads (on _queue)

static NSData *fetch(NSURL *url)
{
    __block NSData *result = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && [(NSHTTPURLResponse *)response statusCode] == 200)
            result = data;
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) != 0)
        [task cancel];
    return result;
}

/* The server's directory listing (~800 KB), cached for a week; a stale copy beats none when offline. */
- (OEAmigaBoxArtMatcher *)matcher
{
    if (_matcher)
        return _matcher;

    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [support URLByAppendingPathComponent:@"OpenEmu/Amiga" isDirectory:YES];
    NSURL *cache = [dir URLByAppendingPathComponent:@"boxart-index.html"];
    NSDate *modified = [[NSFileManager.defaultManager attributesOfItemAtPath:cache.path error:nil] fileModificationDate];

    NSData *html = nil;
    if (!modified || -modified.timeIntervalSinceNow > index_max_age) {
        html = fetch([NSURL URLWithString:box_art_server]);
        if (html) {
            [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
            [html writeToURL:cache atomically:YES];
        } else {
            os_log_error(_log, "Could not download the box art index from %{public}@", box_art_server);
        }
    }
    if (!html)
        html = [NSData dataWithContentsOfURL:cache];
    if (!html)
        return nil;

    _index = [OEAmigaBoxArtMatcher boxArtIndexFromHTML:[[NSString alloc] initWithData:html encoding:NSUTF8StringEncoding] ?: @""];
    _matcher = [[OEAmigaBoxArtMatcher alloc] initWithBoxArtNames:_index.allKeys];
    os_log_info(_log, "Box art index: %lu names", (unsigned long)_index.count);
    return _matcher;
}

- (NSURL *)downloadBoxArtNamed:(NSString *)boxArtName
{
    NSString *file = _index[boxArtName];
    NSData *png = file ? fetch([NSURL URLWithString:[box_art_server stringByAppendingString:file]]) : nil;
    if (!png) {
        os_log_error(_log, "Could not download box art \"%{public}@\"", boxArtName);
        return nil;
    }
    NSURL *temp = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]]];
    return [png writeToURL:temp atomically:YES] ? temp : nil;
}

@end

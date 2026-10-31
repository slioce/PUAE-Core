// Picking up newly imported Amiga games. OpenEmu 2.4.1's contexts: writer (store) <- main <- importer child.
// The importer saves its child, then main; OELibraryDatabase then saves the writer and merges that save into
// main. The library window shows main's instance of the game, which keeps the importer's temporary ID: the
// cover must go on that instance, or the window shows a placeholder until OpenEmu restarts. Main may only
// give it a permanent ID after the writer has saved it; earlier, Core Data would store the game twice.

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#include "test.h"

NSArray<NSString *> *OEAmigaInsertedAmigaGameNames(NSDictionary *saveUserInfo);
NSArray<NSManagedObjectID *> *OEAmigaPrepareImportedGames(NSManagedObjectContext *context, NSArray<NSString *> *names);
NSArray<NSManagedObjectID *> *OEAmigaGamesWithoutBoxArt(NSManagedObjectContext *context);

static NSAttributeDescription *string_attribute(NSString *name)
{
    NSAttributeDescription *a = [NSAttributeDescription new];
    a.name = name;
    a.attributeType = NSStringAttributeType;
    a.optional = YES;
    return a;
}

/* Just the part of OpenEmu's model the fetcher touches: Game.name, Game.system.systemIdentifier, Game.boxImage. */
static NSManagedObjectModel *model(void)
{
    NSEntityDescription *game = [NSEntityDescription new], *system = [NSEntityDescription new], *image = [NSEntityDescription new];
    game.name = @"Game";
    system.name = @"System";
    image.name = @"Image";
    NSRelationshipDescription *gameSystem = [NSRelationshipDescription new], *systemGames = [NSRelationshipDescription new];
    NSRelationshipDescription *gameBox = [NSRelationshipDescription new], *boxGame = [NSRelationshipDescription new];
    gameSystem.name = @"system"; gameSystem.destinationEntity = system; gameSystem.maxCount = 1; gameSystem.optional = YES;
    systemGames.name = @"games"; systemGames.destinationEntity = game; systemGames.maxCount = 0; systemGames.optional = YES;
    gameSystem.inverseRelationship = systemGames; systemGames.inverseRelationship = gameSystem;
    gameBox.name = @"boxImage"; gameBox.destinationEntity = image; gameBox.maxCount = 1; gameBox.optional = YES;
    boxGame.name = @"box"; boxGame.destinationEntity = game; boxGame.maxCount = 1; boxGame.optional = YES;
    gameBox.inverseRelationship = boxGame; boxGame.inverseRelationship = gameBox;
    game.properties = @[ string_attribute(@"name"), gameSystem, gameBox ];
    system.properties = @[ string_attribute(@"systemIdentifier"), systemGames ];
    image.properties = @[ string_attribute(@"relativePath"), boxGame ];
    NSManagedObjectModel *m = [NSManagedObjectModel new];
    m.entities = @[ game, system, image ];
    return m;
}

static NSManagedObject *insert(NSString *entity, NSManagedObjectContext *context)
{
    return [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:context];
}

int main(void)
{
    @autoreleasepool {
        NSPersistentStoreCoordinator *psc = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model()];
        [psc addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:nil];
        NSManagedObjectContext *writer = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        writer.persistentStoreCoordinator = psc;
        NSManagedObjectContext *mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        mainContext.parentContext = writer;

        /* The library already has the Amiga and Arcade systems and a covered Amiga game. */
        [mainContext performBlockAndWait:^{
            NSManagedObject *amiga = insert(@"System", mainContext), *arcade = insert(@"System", mainContext);
            [amiga setValue:@"openemu.system.amiga" forKey:@"systemIdentifier"];
            [arcade setValue:@"openemu.system.arcade" forKey:@"systemIdentifier"];
            NSManagedObject *covered = insert(@"Game", mainContext);
            [covered setValue:@"Lemmings_Disk1" forKey:@"name"];
            [covered setValue:amiga forKey:@"system"];
            [covered setValue:insert(@"Image", mainContext) forKey:@"boxImage"];
            [mainContext save:nil];
        }];
        [writer performBlockAndWait:^{ [writer save:nil]; }];

        /* What OELibraryDatabase does with writer saves: merge them into main. */
        __block NSArray<NSString *> *inserted = nil;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSManagedObjectContextDidSaveNotification
                                                                      object:writer queue:nil usingBlock:^(NSNotification *n) {
            inserted = OEAmigaInsertedAmigaGameNames(n.userInfo);
            [mainContext performBlockAndWait:^{ [mainContext mergeChangesFromContextDidSaveNotification:n]; }];
        }];

        /* Import: a new Amiga game and a new Arcade game in a child of main, saved like ImportOperation does. */
        NSManagedObjectContext *importer = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        importer.parentContext = mainContext;
        __block NSManagedObjectID *importedID = nil;
        [importer performBlockAndWait:^{
            NSFetchRequest *systems = [NSFetchRequest fetchRequestWithEntityName:@"System"];
            for (NSManagedObject *system in [importer executeFetchRequest:systems error:nil]) {
                NSManagedObject *game = insert(@"Game", importer);
                BOOL isAmiga = [[system valueForKey:@"systemIdentifier"] isEqual:@"openemu.system.amiga"];
                [game setValue:isAmiga ? @"Syndicate_Disk1" : @"sf2" forKey:@"name"];
                [game setValue:system forKey:@"system"];
                if (isAmiga)
                    importedID = game.objectID;
            }
            [importer save:nil];
        }];
        [mainContext performBlockAndWait:^{ [mainContext save:nil]; }];
        __block NSManagedObject *shown = nil;  /* the instance the library window displays */
        [mainContext performBlockAndWait:^{ shown = [mainContext objectRegisteredForID:importedID]; }];
        CHECK(shown != nil);

        /* Before the writer has saved, the new game has no permanent ID yet and is left for later. */
        __block NSArray<NSManagedObjectID *> *early = nil;
        [mainContext performBlockAndWait:^{ early = OEAmigaGamesWithoutBoxArt(mainContext); }];
        CHECK(early.count == 0);

        /* The writer's save names the new Amiga game (not the Arcade one); main then hands over the shown
         * instance, now with a permanent ID. */
        [writer performBlockAndWait:^{ [writer save:nil]; }];
        CHECK(inserted.count == 1 && [inserted.firstObject isEqualToString:@"Syndicate_Disk1"]);
        __block NSArray<NSManagedObjectID *> *ids = nil;
        [mainContext performBlockAndWait:^{ ids = OEAmigaPrepareImportedGames(mainContext, inserted); }];
        CHECK(ids.count == 1);
        if (ids.count == 1) {
            CHECK(!ids[0].isTemporaryID);
            __block NSManagedObject *found = nil;
            [mainContext performBlockAndWait:^{ found = [mainContext existingObjectWithID:ids[0] error:nil]; }];
            CHECK(found == shown);
        }

        /* Setting the cover (our own save, which only inserts an image) triggers nothing, leaves no game
         * without a cover and no duplicate rows. */
        inserted = nil;
        [mainContext performBlockAndWait:^{
            NSManagedObject *game = [mainContext existingObjectWithID:ids.firstObject error:nil];
            [game setValue:insert(@"Image", mainContext) forKey:@"boxImage"];
            [mainContext save:nil];
        }];
        [writer performBlockAndWait:^{ [writer save:nil]; }];
        CHECK(inserted != nil && inserted.count == 0);
        __block NSUInteger left = 99, syndicates = 99;
        [mainContext performBlockAndWait:^{ left = OEAmigaGamesWithoutBoxArt(mainContext).count; }];
        CHECK(left == 0);
        CHECK([shown valueForKey:@"boxImage"] != nil);
        [writer performBlockAndWait:^{
            NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Game"];
            request.predicate = [NSPredicate predicateWithFormat:@"name == %@", @"Syndicate_Disk1"];
            syndicates = [writer countForFetchRequest:request error:nil];
        }];
        CHECK(syndicates == 1);

        [NSNotificationCenter.defaultCenter removeObserver:observer];
        return test_report("test_box_art_library");
    }
}

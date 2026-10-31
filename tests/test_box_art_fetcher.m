// Finding OpenEmu's library database: OpenEmu 2.4.1 exposes it as +defaultDatabase, newer sources as +default.

#import <Foundation/Foundation.h>
#include "test.h"

id OEAmigaDefaultLibraryDatabase(Class databaseClass);

static NSObject *database_241, *database_new;

@interface Database241 : NSObject
@end
@implementation Database241
+ (id)defaultDatabase { return database_241; }
@end

@interface DatabaseNew : NSObject
@end
@implementation DatabaseNew
+ (id)default { return database_new; }
@end

@interface NotADatabase : NSObject
@end
@implementation NotADatabase
@end

int main(void)
{
    @autoreleasepool {
        database_241 = [NSObject new];
        database_new = [NSObject new];
        CHECK(OEAmigaDefaultLibraryDatabase(Database241.class) == database_241);
        CHECK(OEAmigaDefaultLibraryDatabase(DatabaseNew.class) == database_new);
        CHECK(OEAmigaDefaultLibraryDatabase(NotADatabase.class) == nil);
        CHECK(OEAmigaDefaultLibraryDatabase(Nil) == nil);
        return test_report("test_box_art_fetcher");
    }
}

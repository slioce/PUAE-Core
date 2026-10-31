// OEAmigaImportFix against a stand-in for OpenEmu's XADArchive (OE) category.

#import <Foundation/Foundation.h>
#include "test.h"

BOOL OEAmigaShouldBypassArchive(NSString *path);

static id sentinel;

@interface XADArchive : NSObject
+ (id)OE_archiveForFileAtPath:(NSString *)path;
+ (id)OE_archiveForFileAtURL:(NSURL *)url;
@end

@implementation XADArchive
+ (id)OE_archiveForFileAtPath:(NSString *)path
{
    return sentinel;
}

// Like the app's category: the URL variant goes through the path variant.
+ (id)OE_archiveForFileAtURL:(NSURL *)url
{
    return [self OE_archiveForFileAtPath:url.path];
}
@end

int main(void)
{
    @autoreleasepool {
        sentinel = [NSObject new];

        for (NSString *ext in @[ @"adf", @"ADF", @"hdf", @"ipf", @"lha", @"Lha" ]) {
            NSString *path = [@"/x/Game." stringByAppendingString:ext];
            CHECK([XADArchive OE_archiveForFileAtPath:path] == nil);
            CHECK([XADArchive OE_archiveForFileAtURL:[NSURL fileURLWithPath:path]] == nil);
            CHECK(OEAmigaShouldBypassArchive(path));
        }
        for (NSString *ext in @[ @"zip", @"7z", @"rar" ]) {
            NSString *path = [@"/x/Game." stringByAppendingString:ext];
            CHECK([XADArchive OE_archiveForFileAtPath:path] == sentinel);
            CHECK(!OEAmigaShouldBypassArchive(path));
        }
        CHECK(!OEAmigaShouldBypassArchive(@"/x/adf"));
        return test_report("test_import_fix");
    }
}

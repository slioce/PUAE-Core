// OpenEmu's importer opens every file with XADMaster before choosing a system, and XADMaster reads an
// AmigaDOS disk as an archive. Multi-file ADFs then get rejected when an entry's extension belongs to
// another system (e.g. ".gam", Vectrex), and single-file ADFs get "extracted" so the core receives
// the file inside instead of the disk (ImportOperation.swift, OEGameDocument.swift).
//
// This system plugin is loaded into the OpenEmu process too, so it patches the app's
// +[XADArchive OE_archiveForFileAtPath:] (XADArchive+OE.m) to report "not an archive" for Amiga
// images. The URL variant and ArchiveHelper go through it as well. Everything else is untouched.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/log.h>

static NSSet<NSString *> *amiga_extensions(void)
{
    static NSSet<NSString *> *extensions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        extensions = [NSSet setWithArray:@[ @"adf", @"hdf", @"ipf", @"lha" ]];
    });
    return extensions;
}

BOOL OEAmigaShouldBypassArchive(NSString *path)
{
    return [amiga_extensions() containsObject:path.pathExtension.lowercaseString];
}

typedef id (*archive_for_path_imp)(id, SEL, NSString *);
static archive_for_path_imp original_archive_for_path;

static id archive_for_path(id self, SEL _cmd, NSString *path)
{
    if (OEAmigaShouldBypassArchive(path))
        return nil;
    return original_archive_for_path(self, _cmd, path);
}

@interface OEAmigaImportFix : NSObject
@end

@implementation OEAmigaImportFix

+ (void)load
{
    os_log_t log = os_log_create("org.openemu.Amiga", "import");
    Class archive = NSClassFromString(@"XADArchive");
    Method method = archive ? class_getClassMethod(archive, NSSelectorFromString(@"OE_archiveForFileAtPath:")) : NULL;
    if (!method) {
        // Expected in OpenEmuHelperApp, which doesn't link XADMaster; only the app's importer matters.
        os_log_debug(log, "XADArchive OE_archiveForFileAtPath: not found, import fix not installed");
        return;
    }
    original_archive_for_path = (archive_for_path_imp)method_setImplementation(method, (IMP)archive_for_path);
    os_log(log, "Import fix installed: %{public}@ files are never treated as archives",
           [amiga_extensions().allObjects componentsJoinedByString:@", "]);
}

@end

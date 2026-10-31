// Box art for Amiga games. OpenEmu finds covers through OpenVGDB, which has no Amiga entries, so the
// Amiga plugin matches ROM file names against the libretro-thumbnails "Commodore - Amiga" set instead.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OEAmigaBoxArtMatch : NSObject
@property(nonatomic, readonly) NSString *boxArtName;  // e.g. "Lemmings (Europe)", without ".png"
@property(nonatomic, readonly) NSString *title;       // e.g. "Lemmings (Disk 1)", for OpenEmu's game title
@end

@interface OEAmigaBoxArtMatcher : NSObject

/// Box art names (file names without ".png") mapped to their URL-encoded file names, parsed from the
/// thumbnail server's directory listing.
+ (NSDictionary<NSString *, NSString *> *)boxArtIndexFromHTML:(NSString *)html;

- (instancetype)initWithBoxArtNames:(NSArray<NSString *> *)names;

/// The box art for a ROM file name (with or without its extension), or nil when no name is a confident
/// match. Disk tags, WHDLoad versions/tags, CamelCase and TOSEC-style tags are normalised away.
- (nullable OEAmigaBoxArtMatch *)matchForFileName:(NSString *)fileName;

@end

NS_ASSUME_NONNULL_END

#import "OEAmigaBoxArt.h"

/* "_Disk2", " Disk 2", "-disk2", " (Disk 2 of 4)", as in Core/PUAEDiskList.c. */
static NSString *const disk_tag_pattern = @"[ _-]?\\(?disk[ _-]?([0-9]{1,2})([ _-]?of[ _-]?[0-9]{1,2})?\\)?";
/* After a title that matches a shorter box name, these mean "a different game in the series". */
static NSString *const sequel_pattern = @"^([0-9]{1,2}(?![0-9])|ii|iii|iv|vi|vii|viii|ix|x(?![a-z]))";

static NSArray<NSString *> *rom_extensions(void)
{
    return @[ @"adf", @"adz", @"dms", @"hdf", @"hdz", @"ipf", @"lha", @"lzx", @"zip", @"7z", @"m3u" ];
}

/* "(Europe)" and friends score highest; other regions and languages are neutral; anything else (demo,
 * alt, compilation, addon...) counts against a box. */
static NSInteger tag_score(NSString *tag, BOOL wantsCD32)
{
    static NSSet<NSString *> *regions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        regions = [NSSet setWithArray:@[ @"Germany", @"France", @"Italy", @"Spain", @"Sweden", @"Netherlands", @"UK",
                                         @"Japan", @"Australia", @"Denmark", @"Finland", @"Norway", @"Poland",
                                         @"Portugal", @"Greece", @"Brazil", @"Korea", @"Canada" ]];
    });
    if ([tag isEqualToString:@"CD32"])
        return wantsCD32 ? 5 : -5;
    if ([tag containsString:@"Europe"])
        return 3;
    if ([tag isEqualToString:@"World"])
        return 2;
    if ([tag isEqualToString:@"USA"])
        return 1;
    if ([regions containsObject:tag] || [tag rangeOfString:@"^v[0-9]" options:NSRegularExpressionSearch].location != NSNotFound
        || [tag rangeOfString:@"^[A-Z][a-z](,[A-Z][a-z])+$" options:NSRegularExpressionSearch].location != NSNotFound)
        return 0;
    return -1;
}

/* Lowercase letters and digits only, without a leading or trailing article: "NewZealand Story, The"
 * and "New Zealand Story, The" both become "newzealandstory". */
static NSString *compact_key(NSString *title)
{
    NSString *s = [title stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil];
    if ([s hasSuffix:@", the"])
        s = [s substringToIndex:s.length - 5];
    if ([s hasPrefix:@"the "])
        s = [s substringFromIndex:4];
    NSMutableString *key = [NSMutableString stringWithCapacity:s.length];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
            [key appendFormat:@"%C", c];
    }
    return key;
}

/* Removes "(...)" and "[...]" groups, returning them in *tags. */
static NSString *strip_tags(NSString *name, NSMutableArray<NSString *> *tags)
{
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\s*[\\(\\[]([^\\)\\]]*)[\\)\\]]" options:0 error:nil];
    for (NSTextCheckingResult *m in [re matchesInString:name options:0 range:NSMakeRange(0, name.length)])
        [tags addObject:[name substringWithRange:[m rangeAtIndex:1]]];
    NSString *stripped = [re stringByReplacingMatchesInString:name options:0 range:NSMakeRange(0, name.length) withTemplate:@""];
    return [stripped stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

/* "SensibleWorldOfSoccer2425" -> "Sensible World Of Soccer 2425". */
static NSString *split_camel_case(NSString *s)
{
    NSString *spaced = [s stringByReplacingOccurrencesOfString:@"(?<=[a-z])(?=[A-Z])|(?<=[A-Za-z])(?=[0-9])|(?<=[0-9])(?=[A-Za-z])"
                                                    withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, s.length)];
    return spaced;
}

@interface OEAmigaBoxArtCandidate : NSObject
@property(nonatomic, copy) NSString *name, *title;
@property(nonatomic, copy) NSArray<NSString *> *tags;
@end
@implementation OEAmigaBoxArtCandidate
@end

@implementation OEAmigaBoxArtMatch
- (instancetype)initWithBoxArtName:(NSString *)name title:(NSString *)title
{
    if ((self = [super init])) {
        _boxArtName = [name copy];
        _title = [title copy];
    }
    return self;
}
@end

@implementation OEAmigaBoxArtMatcher
{
    NSDictionary<NSString *, NSArray<OEAmigaBoxArtCandidate *> *> *_candidatesByKey;
}

+ (NSDictionary<NSString *, NSString *> *)boxArtIndexFromHTML:(NSString *)html
{
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<a href=\"([^\"]+\\.png)\">([^<]+)\\.png</a>" options:0 error:nil];
    NSMutableDictionary<NSString *, NSString *> *index = [NSMutableDictionary dictionary];
    for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        NSString *name = [html substringWithRange:[m rangeAtIndex:2]];
        for (NSArray<NSString *> *entity in @[ @[ @"&lt;", @"<" ], @[ @"&gt;", @">" ], @[ @"&quot;", @"\"" ],
                                               @[ @"&#39;", @"'" ], @[ @"&amp;", @"&" ] ])
            name = [name stringByReplacingOccurrencesOfString:entity[0] withString:entity[1]];
        index[name] = [html substringWithRange:[m rangeAtIndex:1]];
    }
    return index;
}

- (instancetype)initWithBoxArtNames:(NSArray<NSString *> *)names
{
    if (!(self = [super init]))
        return nil;
    NSMutableDictionary<NSString *, NSMutableArray<OEAmigaBoxArtCandidate *> *> *byKey = [NSMutableDictionary dictionary];
    for (NSString *name in names) {
        NSMutableArray<NSString *> *tags = [NSMutableArray array];
        OEAmigaBoxArtCandidate *candidate = [OEAmigaBoxArtCandidate new];
        candidate.name = name;
        candidate.title = strip_tags(name, tags);
        candidate.tags = tags;
        NSString *key = compact_key(candidate.title);
        if (key.length == 0)
            continue;
        if (!byKey[key])
            byKey[key] = [NSMutableArray array];
        [byKey[key] addObject:candidate];
    }
    _candidatesByKey = byKey;
    return self;
}

- (OEAmigaBoxArtCandidate *)bestCandidateForKey:(NSString *)key wantsCD32:(BOOL)wantsCD32
{
    OEAmigaBoxArtCandidate *best = nil;
    NSInteger bestScore = NSIntegerMin;
    for (OEAmigaBoxArtCandidate *c in _candidatesByKey[key]) {
        NSInteger score = c.tags.count ? 0 : 1;  /* untagged: a generic box */
        for (NSString *tag in c.tags)
            score += tag_score(tag, wantsCD32);
        if (score > bestScore || (score == bestScore && (c.name.length < best.name.length
            || (c.name.length == best.name.length && [c.name compare:best.name] == NSOrderedAscending)))) {
            best = c;
            bestScore = score;
        }
    }
    return best;
}

static BOOL starts_with_sequel(NSString *remainder)
{
    return [remainder rangeOfString:sequel_pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

- (OEAmigaBoxArtMatch *)matchForFileName:(NSString *)fileName
{
    NSString *base = fileName;
    if ([rom_extensions() containsObject:fileName.pathExtension.lowercaseString])
        base = fileName.stringByDeletingPathExtension;

    NSInteger disk = 0;
    NSRegularExpression *diskRE = [NSRegularExpression regularExpressionWithPattern:disk_tag_pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *diskMatch = [diskRE firstMatchInString:base options:0 range:NSMakeRange(0, base.length)];
    if (diskMatch) {
        disk = [[base substringWithRange:[diskMatch rangeAtIndex:1]] integerValue];
        base = [base stringByReplacingCharactersInRange:diskMatch.range withString:@""];
    }

    NSString *title;
    BOOL wantsCD32 = NO;
    NSMutableArray<NSString *> *tags = [NSMutableArray array];
    if (![base containsString:@" "]) {
        /* WHDLoad style: Title_v1.2_Tag_Tag, title in CamelCase. */
        NSArray<NSString *> *parts = [base componentsSeparatedByString:@"_"];
        title = split_camel_case(parts.firstObject);
        [tags addObjectsFromArray:[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)]];
    } else {
        /* TOSEC / No-Intro / hand-named: "Title (Region) (Tags)". */
        title = [strip_tags(base, tags) stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        title = [title stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, title.length)];
    }
    for (NSString *tag in tags)
        if ([tag caseInsensitiveCompare:@"CD32"] == NSOrderedSame)
            wantsCD32 = YES;

    NSString *key = compact_key(title);
    if (key.length < 3)
        return nil;

    OEAmigaBoxArtCandidate *best = nil;
    NSString *finalTitle = title;
    if (_candidatesByKey[key]) {
        best = [self bestCandidateForKey:key wantsCD32:wantsCD32];
        /* Keep the file's own spelling ("New Zealand" beats the box's "NewZealand"), unless it has no
         * capitals at all. */
        if ([title isEqualToString:title.lowercaseString])
            finalTitle = best.title;
    } else {
        /* No exact title: a box whose title is a prefix of ours (a season or subtitle on top), or ours is
         * a prefix of its (the box title is more complete). The closest length wins. */
        NSString *bestKey = nil;
        NSUInteger bestDistance = NSUIntegerMax;
        for (NSString *candidateKey in _candidatesByKey) {
            NSString *remainder;
            if (candidateKey.length < key.length && candidateKey.length >= 4 && [key hasPrefix:candidateKey])
                remainder = [key substringFromIndex:candidateKey.length];
            else if (candidateKey.length > key.length && key.length >= 4 && [candidateKey hasPrefix:key])
                remainder = [candidateKey substringFromIndex:key.length];
            else
                continue;
            if (starts_with_sequel(remainder))
                continue;
            NSUInteger distance = remainder.length;
            if (distance < bestDistance || (distance == bestDistance && candidateKey.length < bestKey.length)) {
                bestKey = candidateKey;
                bestDistance = distance;
            }
        }
        if (!bestKey)
            return nil;
        best = [self bestCandidateForKey:bestKey wantsCD32:wantsCD32];
        if (bestKey.length > key.length)
            finalTitle = best.title;
    }
    if (!best)
        return nil;
    if (disk > 0)
        finalTitle = [finalTitle stringByAppendingFormat:@" (Disk %ld)", (long)disk];
    return [[OEAmigaBoxArtMatch alloc] initWithBoxArtName:best.name title:finalTitle];
}

@end

// Matching ROM file names to libretro-thumbnails box art names (names taken from the real index).

#import <Foundation/Foundation.h>
#import "OEAmigaBoxArt.h"
#include "test.h"

static NSArray<NSString *> *names(void)
{
    return @[
        @"'Nam 1965-1975",
        @"Cannon Fodder (Europe) (CD32)", @"Cannon Fodder", @"Cannon Fodder 2", @"Cannon Fodder Plus!",
        @"It Came from the Desert", @"It Came from the Desert II - Antheads",
        @"Lemmings (Europe) (Book Club)", @"Lemmings (Europe)", @"Lemmings (USA) (Alt 1)", @"Lemmings (USA)",
        @"Lemmings 2 - The Tribes (Europe)",
        @"NewZealand Story, The (Europe)",
        @"Sensible Soccer",
        @"Sensible World of Soccer (Europe) (v1.1)", @"Sensible World of Soccer", @"Sensible World of Soccer '96-'97",
        @"Superfrog (Europe) (CD32)", @"Superfrog",
        @"Syndicate (Europe) (En,Fr,It) (Compilation - Chaos Pack)", @"Syndicate (Europe)", @"Syndicate (Germany)",
        @"Turrican", @"Turrican II - The Final Fight",
    ];
}

static void check_match(OEAmigaBoxArtMatcher *matcher, NSString *file, NSString *boxArt, NSString *title)
{
    OEAmigaBoxArtMatch *m = [matcher matchForFileName:file];
    if (!boxArt) {
        if (m) {
            fprintf(stderr, "%s: expected no match, got \"%s\"\n", file.UTF8String, m.boxArtName.UTF8String);
            test_failures++;
        }
        return;
    }
    CHECK_STR(m.boxArtName.UTF8String, boxArt.UTF8String);
    CHECK_STR(m.title.UTF8String, title.UTF8String);
}

static void test_matches(void)
{
    OEAmigaBoxArtMatcher *matcher = [[OEAmigaBoxArtMatcher alloc] initWithBoxArtNames:names()];

    // Spacing differs ("NewZealand"), article at the end on both sides.
    check_match(matcher, @"New Zealand Story, The.adf", @"NewZealand Story, The (Europe)", @"New Zealand Story, The");
    // Disk tags: the Europe release with the fewest extra tags, disk number in the title.
    check_match(matcher, @"Lemmings_Disk1.adf", @"Lemmings (Europe)", @"Lemmings (Disk 1)");
    check_match(matcher, @"Lemmings_Disk2", @"Lemmings (Europe)", @"Lemmings (Disk 2)");
    check_match(matcher, @"Syndicate_Disk3.adf", @"Syndicate (Europe)", @"Syndicate (Disk 3)");
    check_match(matcher, @"It Came from the Desert_Disk3.adf", @"It Came from the Desert", @"It Came from the Desert (Disk 3)");
    // WHDLoad names: CamelCase, version and tags after underscores; CD32 picks the CD32 box.
    check_match(matcher, @"CannonFodder_v1.2_CD32.lha", @"Cannon Fodder (Europe) (CD32)", @"Cannon Fodder");
    check_match(matcher, @"CannonFodder_v1.2_CD32", @"Cannon Fodder (Europe) (CD32)", @"Cannon Fodder");
    check_match(matcher, @"CannonFodder_v2.0_0860.lha", @"Cannon Fodder", @"Cannon Fodder");
    check_match(matcher, @"Superfrog_v1.4.lha", @"Superfrog", @"Superfrog");
    // A season number on top of the base title is still that game.
    check_match(matcher, @"SensibleWorldOfSoccer2425_v2.3.lha", @"Sensible World of Soccer (Europe) (v1.1)",
                @"Sensible World Of Soccer 2425");
    // Shorter name than the box: the box title is more complete.
    check_match(matcher, @"Lemmings2_Disk1.adf", @"Lemmings 2 - The Tribes (Europe)", @"Lemmings 2 - The Tribes (Disk 1)");
    // TOSEC/No-Intro style tags are ignored.
    check_match(matcher, @"Lemmings 2 - The Tribes (Europe) (Demo) (Promo - The Future Entertainment Show).ipf",
                @"Lemmings 2 - The Tribes (Europe)", @"Lemmings 2 - The Tribes");
    // A subtitle after a known title still gets that title's box.
    check_match(matcher, @"Cannon Fodder 2 - Not Very Festive.adf", @"Cannon Fodder 2", @"Cannon Fodder 2 - Not Very Festive");
    check_match(matcher, @"SensibleSoccerSaveDisk.adf", @"Sensible Soccer", @"Sensible Soccer Save Disk");
    // An all-lowercase name takes the box's capitalisation.
    check_match(matcher, @"superfrog.lha", @"Superfrog", @"Superfrog");
    // Sequel numbers never fall back to the first game.
    check_match(matcher, @"Lemmings3_Disk1.adf", nil, nil);
    check_match(matcher, @"TurricanIII.lha", nil, nil);
    // Nothing recognisable: no box rather than a wrong one.
    check_match(matcher, @"swos2223.hdf", nil, nil);
}

static void test_index_parsing(void)
{
    NSString *html =
        @"<tr><td><a href=\"/Commodore%20-%20Amiga/\">Parent Directory</a></td></tr>\n"
        @"<tr><td><a href=\"'Allo%20'Allo%20-%20Cartoon%20Fun!.png\">'Allo 'Allo - Cartoon Fun!.png</a></td></tr>\n"
        @"<tr><td><a href=\"Mike%20%26%20Ike.png\">Mike &amp; Ike.png</a></td></tr>\n"
        @"<tr><td><a href=\"NewZealand%20Story,%20The%20(Europe).png\">NewZealand Story, The (Europe).png</a></td></tr>\n";
    NSDictionary<NSString *, NSString *> *index = [OEAmigaBoxArtMatcher boxArtIndexFromHTML:html];
    CHECK(index.count == 3);
    CHECK_STR(index[@"'Allo 'Allo - Cartoon Fun!"].UTF8String, "'Allo%20'Allo%20-%20Cartoon%20Fun!.png");
    CHECK_STR(index[@"Mike & Ike"].UTF8String, "Mike%20%26%20Ike.png");
    CHECK_STR(index[@"NewZealand Story, The (Europe)"].UTF8String, "NewZealand%20Story,%20The%20(Europe).png");
}

int main(void)
{
    @autoreleasepool {
        test_matches();
        test_index_parsing();
        return test_report("test_box_art");
    }
}

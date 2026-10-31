#import "PUAEGameCore.h"

#import <OpenEmuBase/OEGameCoreDisplayModes.h>
#import <OpenEmuBase/OERingBuffer.h>
#import <OpenGL/gl.h>
#import <os/log.h>
#import <stdatomic.h>

#include "PUAEBridge.h"
#include "PUAEDiskList.h"
#include "PUAEFloppySpeed.h"
#include "PUAEKeymap.h"
#include "PUAEMouse.h"
#include "PUAESystemDir.h"

static os_log_t OE_CORE_LOG;

/* Display-mode preference key; OpenEmu saves the chosen value per core and hands it back in displayModeInfo. */
static NSString *const floppy_speed_pref = @"floppySpeed";

/* OEAmigaButton -> RetroPad id. PUAE reads B as fire and A as 2nd fire (see PUAEBridge.h). */
static const unsigned amiga_button_ids[OEAmigaButtonCount] = {
    [OEAmigaJoystickUp]    = RETRO_DEVICE_ID_JOYPAD_UP,
    [OEAmigaJoystickDown]  = RETRO_DEVICE_ID_JOYPAD_DOWN,
    [OEAmigaJoystickLeft]  = RETRO_DEVICE_ID_JOYPAD_LEFT,
    [OEAmigaJoystickRight] = RETRO_DEVICE_ID_JOYPAD_RIGHT,
    [OEAmigaButtonFire]    = RETRO_DEVICE_ID_JOYPAD_B,
    [OEAmigaButtonFire2]   = RETRO_DEVICE_ID_JOYPAD_A,
};

static void core_audio(void *ctx, const int16_t *frames, size_t count)
{
    PUAEGameCore *core = (__bridge PUAEGameCore *)ctx;
    [[core audioBufferAtIndex:0] write:frames maxLength:count * 2 * sizeof(int16_t)];
}

static void core_log(void *ctx, int level, const char *message)
{
    (void)ctx;
    os_log_type_t type = level >= RETRO_LOG_ERROR ? OS_LOG_TYPE_ERROR
                       : level == RETRO_LOG_WARN  ? OS_LOG_TYPE_DEFAULT
                       : level == RETRO_LOG_INFO  ? OS_LOG_TYPE_INFO
                       :                            OS_LOG_TYPE_DEBUG;
    os_log_with_type(OE_CORE_LOG, type, "%{public}s", message);
}

static NSString *string_from_path(const char *path)
{
    return path ? [NSFileManager.defaultManager stringWithFileSystemRepresentation:path length:strlen(path)] : nil;
}

@implementation PUAEGameCore
{
    atomic_int _pendingDisc;  /* 0-based disk to insert at the next frame, -1 for none */
    puae_mouse_tracker _mouse;
    NSString *_floppySpeed;         /* puae_floppy_speed value shown as selected in the menu */
    NSString *_pendingFloppySpeed;  /* set from the menu, applied by executeFrame; guarded by self */
}

+ (void)initialize
{
    OE_CORE_LOG = os_log_create("org.openemu.PUAE", "");
}

- (id)init
{
    self = [super init];
    if (!self)
        return nil;
    atomic_init(&_pendingDisc, -1);
    return self;
}

#pragma mark - Loading

/*
 * What to hand PUAE: a hand-written "<game>.m3u" next to the file, else the game's other disks
 * (OpenEmu imports each disk on its own) as a generated playlist starting at disk 1, else the file.
 */
- (NSString *)loadPathForGame:(NSString *)path
{
    const char *game = path.fileSystemRepresentation;
    char *sidecar = puae_disk_list_sidecar_m3u(game);
    if (sidecar) {
        NSString *m3u = string_from_path(sidecar);
        free(sidecar);
        os_log_info(OE_CORE_LOG, "Using playlist %{public}@", m3u);
        return m3u;
    }

    puae_disk_list disks;
    if (puae_disk_list_find(game, &disks) != 0)
        return path;
    NSString *loadPath = path;
    if (disks.count > 1) {
        NSString *dir = [self.supportDirectoryPath stringByAppendingPathComponent:@"playlists"];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        char *name = puae_disk_list_game_name(game);
        NSString *m3u = [[dir stringByAppendingPathComponent:string_from_path(name)] stringByAppendingPathExtension:@"m3u"];
        free(name);
        if (puae_disk_list_write_m3u(&disks, m3u.fileSystemRepresentation) == 0) {
            os_log_info(OE_CORE_LOG, "Found %zu disks, using playlist %{public}@", disks.count, m3u);
            loadPath = m3u;
        }
    }
    puae_disk_list_free(&disks);
    return loadPath;
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
    NSString *systemDir = [self.supportDirectoryPath stringByAppendingPathComponent:@"system"];
    NSString *saveDir = self.batterySavesDirectoryPath;
    [NSFileManager.defaultManager createDirectoryAtPath:saveDir withIntermediateDirectories:YES attributes:nil error:nil];

    int kickstarts = puae_system_dir_link_kickstarts(self.biosDirectoryPath.fileSystemRepresentation,
                                                     systemDir.fileSystemRepresentation);
    os_log_info(OE_CORE_LOG, "Linked %d Kickstart(s) into %{public}@", kickstarts, systemDir);

    id savedSpeed = self.displayModeInfo[floppy_speed_pref];
    _floppySpeed = @(puae_floppy_speed_or_default([savedSpeed isKindOfClass:NSString.class] ? [savedSpeed UTF8String] : NULL));
    const char *options[] = { "puae_floppy_speed", _floppySpeed.UTF8String, NULL };

    puae_bridge_config config = {
        .system_dir = systemDir.fileSystemRepresentation,
        .save_dir   = saveDir.fileSystemRepresentation,
        .ctx        = (__bridge void *)self,
        .audio      = core_audio,
        .log        = core_log,
        .options    = options,
    };
    if (kickstarts < 0 || puae_bridge_init(&config) != 0 || !puae_bridge_load([self loadPathForGame:path].fileSystemRepresentation)) {
        const char *reason = puae_bridge_last_error();
        if (error) {
            *error = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadROMError userInfo:@{
                NSLocalizedDescriptionKey : @"The Amiga game could not be started.",
                NSLocalizedRecoverySuggestionErrorKey : reason ? @(reason) : @"PUAE could not load the file.",
            }];
        }
        return NO;
    }
    return YES;
}

#pragma mark - Execution

- (void)executeFrame
{
    int disc = atomic_exchange(&_pendingDisc, -1);
    if (disc >= 0 && !puae_bridge_set_disk((unsigned)disc))
        os_log_error(OE_CORE_LOG, "Could not insert disk %d", disc + 1);

    NSString *speed;
    @synchronized (self) {
        speed = _pendingFloppySpeed;
        _pendingFloppySpeed = nil;
    }
    if (speed && !puae_bridge_set_option("puae_floppy_speed", speed.UTF8String))
        os_log_error(OE_CORE_LOG, "Could not set floppy speed %{public}@", speed);

    puae_bridge_run_frame();
}

- (void)resetEmulation
{
    puae_bridge_reset();
}

- (void)stopEmulation
{
    puae_bridge_deinit();
    [super stopEmulation];
}

- (NSTimeInterval)frameInterval
{
    double fps = puae_bridge_video_info()->fps;
    return fps > 0 ? fps : 50;
}

#pragma mark - Video

- (const void *)getVideoBufferWithHint:(void *)hint
{
    return puae_bridge_video_info()->frame;
}

- (OEIntSize)bufferSize
{
    const puae_bridge_video *v = puae_bridge_video_info();
    return OEIntSizeMake(v->buffer_width, v->buffer_height);
}

- (OEIntRect)screenRect
{
    const puae_bridge_video *v = puae_bridge_video_info();
    if (!v->width || !v->height)  /* no frame yet: a PAL lores screen */
        return OEIntRectMake(0, 0, v->buffer_width / 2, v->buffer_height / 2);
    return OEIntRectMake(0, 0, v->width, v->height);
}

- (OEIntSize)aspectSize
{
    float aspect = puae_bridge_video_info()->aspect;
    return aspect > 0 ? OEIntSizeMake((int)lroundf(aspect * 1000), 1000) : OEIntSizeMake(4, 3);
}

- (GLenum)pixelFormat
{
    return GL_BGRA;
}

- (GLenum)pixelType
{
    return GL_UNSIGNED_INT_8_8_8_8_REV;
}

#pragma mark - Audio

- (double)audioSampleRate
{
    double rate = puae_bridge_video_info()->sample_rate;
    return rate > 0 ? rate : 44100;
}

- (NSUInteger)channelCount
{
    return 2;
}

#pragma mark - Display modes

/* OpenEmu's display-mode menu carries the floppy speed: Turbo by default, Normal for the rare loader that
 * needs real disk timing. */
- (NSArray<NSDictionary<NSString *, id> *> *)displayModes
{
    NSMutableArray *speeds = [NSMutableArray array];
    NSString *current;
    @synchronized (self) {
        current = _floppySpeed;
    }
    for (const puae_floppy_speed *s = puae_floppy_speeds; s->name; s++)
        [speeds addObject:OEDisplayMode_OptionWithStateValue(@(s->name), floppy_speed_pref,
                                                             @([current isEqualToString:@(s->value)]), @(s->value))];
    return @[ OEDisplayMode_Submenu(@"Floppy Speed", speeds) ];
}

- (void)changeDisplayWithMode:(NSString *)displayMode
{
    const char *value = puae_floppy_speed_value(displayMode.UTF8String);
    if (!value)
        return;
    @synchronized (self) {
        _floppySpeed = @(value);
        _pendingFloppySpeed = _floppySpeed;
    }
    os_log_info(OE_CORE_LOG, "Floppy speed: %{public}@", displayMode);
}

#pragma mark - Disks

- (NSUInteger)discCount
{
    return puae_bridge_disk_count();
}

- (void)setDisc:(NSUInteger)discNumber
{
    /* May arrive on another thread; executeFrame inserts it. */
    if (discNumber >= 1)
        atomic_store(&_pendingDisc, (int)discNumber - 1);
}

#pragma mark - Input

- (oneway void)didPushAmigaButton:(OEAmigaButton)button forPlayer:(NSUInteger)player
{
    if (button < OEAmigaButtonCount && player >= 1)
        puae_bridge_set_joypad((unsigned)player - 1, amiga_button_ids[button], true);
}

- (oneway void)didReleaseAmigaButton:(OEAmigaButton)button forPlayer:(NSUInteger)player
{
    if (button < OEAmigaButtonCount && player >= 1)
        puae_bridge_set_joypad((unsigned)player - 1, amiga_button_ids[button], false);
}

/* OpenEmu sends absolute positions in the game screen; the Amiga mouse wants relative counts. */
- (void)moveMouseToPoint:(OEIntPoint)point
{
    int dx, dy, amiga_dx, amiga_dy;
    puae_mouse_track(&_mouse, point.x, point.y, &dx, &dy);
    const puae_bridge_video *v = puae_bridge_video_info();
    puae_mouse_scale(&_mouse, dx, dy, v->width, v->height, &amiga_dx, &amiga_dy);
    if (amiga_dx || amiga_dy)
        puae_bridge_mouse_move(amiga_dx, amiga_dy);
}

- (oneway void)mouseMovedAtPoint:(OEIntPoint)point
{
    [self moveMouseToPoint:point];
}

/* Also sent repeatedly while dragging, carrying the new position. */
- (oneway void)leftMouseDownAtPoint:(OEIntPoint)point
{
    [self moveMouseToPoint:point];
    puae_bridge_set_mouse_button(RETRO_DEVICE_ID_MOUSE_LEFT, true);
}

- (oneway void)leftMouseUp
{
    puae_bridge_set_mouse_button(RETRO_DEVICE_ID_MOUSE_LEFT, false);
}

- (oneway void)rightMouseDownAtPoint:(OEIntPoint)point
{
    [self moveMouseToPoint:point];
    puae_bridge_set_mouse_button(RETRO_DEVICE_ID_MOUSE_RIGHT, true);
}

- (oneway void)rightMouseUp
{
    puae_bridge_set_mouse_button(RETRO_DEVICE_ID_MOUSE_RIGHT, false);
}

- (oneway void)keyDown:(NSUInteger)keyCode
{
    unsigned key = puae_keymap_hid_to_retrok((unsigned)keyCode);
    if (key != RETROK_UNKNOWN)
        puae_bridge_key(key, true);
}

- (oneway void)keyUp:(NSUInteger)keyCode
{
    unsigned key = puae_keymap_hid_to_retrok((unsigned)keyCode);
    if (key != RETROK_UNKNOWN)
        puae_bridge_key(key, false);
}

#pragma mark - Save states

- (NSData *)serializeStateWithError:(NSError **)outError
{
    size_t size = puae_bridge_state_size();
    NSMutableData *state = [NSMutableData dataWithLength:size];
    if (size && puae_bridge_save_state(state.mutableBytes, size))
        return state;
    if (outError) {
        *outError = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotSaveStateError userInfo:@{
            NSLocalizedDescriptionKey : @"PUAE could not save the state.",
        }];
    }
    return nil;
}

- (BOOL)deserializeState:(NSData *)state withError:(NSError **)outError
{
    if (puae_bridge_load_state(state.bytes, state.length))
        return YES;
    if (outError) {
        *outError = [NSError errorWithDomain:OEGameCoreErrorDomain code:OEGameCoreCouldNotLoadStateError userInfo:@{
            NSLocalizedDescriptionKey : @"PUAE could not load the state.",
        }];
    }
    return NO;
}

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    NSError *err = nil;
    NSData *state = [self serializeStateWithError:&err];
    BOOL res = state && [state writeToFile:fileName options:NSDataWritingAtomic error:&err];
    block(res, err);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
    NSError *err = nil;
    NSData *state = [NSData dataWithContentsOfFile:fileName options:0 error:&err];
    BOOL res = state && [self deserializeState:state withError:&err];
    block(res, err);
}

- (BOOL)supportsRewinding
{
    return NO;
}

@end

@import OpenEmuSystem;
#import "OEAmigaSystemResponderClient.h"

OE_EXPORTED_CLASS
@interface OEAmigaSystemResponder : OESystemResponder

@property(nonatomic, weak) id<OEAmigaSystemResponderClient> client;

@end

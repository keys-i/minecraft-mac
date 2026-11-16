// Exercise the patched host functions with fake Cocoa and Metal objects
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#include <os/lock.h>
#include <math.h>
#include <notify.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <uuid/uuid.h>
#include <assert.h>

@interface FixtureWindow : NSObject
@property NSRect frame;
@property NSWindowStyleMask styleMask;
@property(assign) FixtureWindow *parentWindow;
@property int changes;
@property int toggles;
@property int orders;
@property BOOL allowOrder;
@property(getter=isVisible) BOOL visible;
- (void)makeKeyAndOrderFront:(id)sender;
- (void)setFrame:(NSRect)frame display:(BOOL)display;
- (void)toggleFullScreen:(id)sender;
@end
@implementation FixtureWindow
- (void)setFrame:(NSRect)frame display:(BOOL)display { self.frame=frame;self.changes++; }
- (void)toggleFullScreen:(id)sender { self.toggles++; }
- (void)makeKeyAndOrderFront:(id)sender { self.orders++;self.visible=self.allowOrder; }
@end
@interface FixtureView : NSObject
@property NSRect bounds;
@property(retain) FixtureWindow *window;
@end
@implementation FixtureView
- (void)dealloc { [_window release];[super dealloc]; }
@end
@interface FixtureScreen : NSObject
@property NSRect frame;
@property NSRect visibleFrame;
+ (NSArray *)screens;
@end
static NSArray *fixtureScreens;
@implementation FixtureScreen
+ (NSArray *)screens { return fixtureScreens; }
@end
@interface FixtureDrawable : NSObject
@property(retain) CAMetalLayer *layer;
@end
@implementation FixtureDrawable
- (void)dealloc { [_layer release];[super dealloc]; }
@end
@interface FixtureBuffer : NSObject
@property MTLCommandBufferStatus status;
@property(retain) NSError *error;
@property(copy) MTLCommandBufferHandler handler;
@property int adds;
- (void)addCompletedHandler:(MTLCommandBufferHandler)handler;
- (void)fire;
@end
@implementation FixtureBuffer
- (void)addCompletedHandler:(MTLCommandBufferHandler)handler { self.handler=handler;self.adds++; }
- (void)fire { if(self.handler) self.handler((id<MTLCommandBuffer>)self); }
- (void)dealloc { [_error release];[_handler release];[super dealloc]; }
@end
static unsigned registrations, posted, states, cancelled;
static uint64_t published;
static uint32_t registerStatus, publishStatus, postStatus;
static uint32_t fixture_register(const char *name,int *token) { registrations++;*token=17;assert(strlen(name)==strlen("local.keys-i.minecraft.present.")+36);return registerStatus; }
static uint32_t fixture_state(int token,uint64_t state) { assert(token==17);states++;published=state;return publishStatus; }
static uint32_t fixture_post(const char *name) { posted++;return postStatus; }
static uint32_t fixture_cancel(int token) { assert(token==17);cancelled++;return 0; }
static void execute_on_main(dispatch_block_t block) { block(); }
#define NSWindow FixtureWindow
#define NSView FixtureView
#define NSScreen FixtureScreen
#define notify_register_check fixture_register
#define notify_set_state fixture_state
#define notify_post fixture_post
#define notify_cancel fixture_cancel
#define dispatch_async(queue,block) block()


#include "handoff.inc"

static FixtureBuffer *make(void) {
  FixtureBuffer *buffer=[[[FixtureBuffer alloc]init]autorelease];buffer.status=MTLCommandBufferStatusCompleted;return buffer;
}
static void present(FixtureBuffer *buffer,CAMetalLayer *layer) {
  FixtureDrawable *drawable=[[[FixtureDrawable alloc]init]autorelease];drawable.layer=layer;
  launcher_present((id<MTLCommandBuffer>)buffer,(id<CAMetalDrawable>)drawable);
}
int main(int argc,char **argv) {
  @autoreleasepool {
    assert(argc==2);const char *scenario=argv[1];
    unsetenv("BEDROCK_LAUNCH_TOKEN");unsetenv("BEDROCK_WINDOW_FRAME");unsetenv("BEDROCK_WINDOW_FULLSCREEN");
    if(strcmp(scenario,"absent")) setenv("BEDROCK_LAUNCH_TOKEN","0691A8BB-84FE-4B49-97F4-C07AC0B2BC41",1);
    if(!strcmp(scenario,"invalid-token")) setenv("BEDROCK_LAUNCH_TOKEN","../../arbitrary-notification",1);
    setenv("BEDROCK_WINDOW_FRAME","-1300 100 1000 700",1);
    if(!strcmp(scenario,"invalid-frame")) setenv("BEDROCK_WINDOW_FRAME","nan 100 1000 700",1);
    if(!strcmp(scenario,"trailing-frame")) setenv("BEDROCK_WINDOW_FRAME","-1300 100 1000 700 trailing",1);
    if(!strcmp(scenario,"offscreen")) setenv("BEDROCK_WINDOW_FRAME","90000 90000 1000 700",1);
    if(!strcmp(scenario,"huge-frame")) setenv("BEDROCK_WINDOW_FRAME","-1300 100 32769 700",1);
    if(!strcmp(scenario,"long-frame")) { char value[300];memset(value,'1',299);value[299]=0;setenv("BEDROCK_WINDOW_FRAME",value,1); }
    if(!strcmp(scenario,"fullscreen")) setenv("BEDROCK_WINDOW_FULLSCREEN","1",1);
    if(!strcmp(scenario,"register-failure")) registerStatus=NOTIFY_STATUS_FAILED;
    if(!strcmp(scenario,"publish-retry")||!strcmp(scenario,"publish-terminal")) publishStatus=NOTIFY_STATUS_FAILED;
    if(!strcmp(scenario,"post-retry")) postStatus=NOTIFY_STATUS_FAILED;
    FixtureScreen *screen=[[[FixtureScreen alloc]init]autorelease];screen.frame=NSMakeRect(0,0,1920,1080);screen.visibleFrame=NSMakeRect(0,30,1920,1025);
    FixtureScreen *second=[[[FixtureScreen alloc]init]autorelease];second.frame=NSMakeRect(-1440,0,1440,900);second.visibleFrame=NSMakeRect(-1440,25,1440,850);
    fixtureScreens=@[screen,second];
    FixtureWindow *window=[[[FixtureWindow alloc]init]autorelease];window.frame=NSMakeRect(0,0,500,300);window.allowOrder=YES;
    FixtureView *view=[[[FixtureView alloc]init]autorelease];view.window=window;view.bounds=NSMakeRect(0,0,500,300);
    if(!strcmp(scenario,"tiny-view")) view.bounds=NSMakeRect(0,0,100,100);
    if(!strcmp(scenario,"tiny-window")) window.frame=NSMakeRect(0,0,100,100);
    if(!strcmp(scenario,"child-window")) window.parentWindow=window;
    CAMetalLayer *layer=(CAMetalLayer*)[[[NSObject alloc]init]autorelease];
    launcher_view((NSView*)view,layer);
    FixtureBuffer *buffer=make();buffer.status=MTLCommandBufferStatusScheduled;present(buffer,layer);present(buffer,layer);
    assert(posted==0&&states==0&&cancelled==0);
    if(!strcmp(scenario,"absent")||!strcmp(scenario,"invalid-token")||!strcmp(scenario,"register-failure")||!strcmp(scenario,"tiny-view")||!strcmp(scenario,"tiny-window")||!strcmp(scenario,"child-window")) {
      assert(window.changes==0&&window.orders==0&&!buffer.handler&&launcher.layer==nil&&launcher.window==nil);
      assert(registrations==(!strcmp(scenario,"register-failure")?1:0));
      puts("inactive or ineligible case passed");return 0;
    }
    assert(registrations==1&&buffer.handler&&buffer.adds==1&&launcher.pending);
    if(!strcmp(scenario,"invalid-frame")||!strcmp(scenario,"trailing-frame")||!strcmp(scenario,"offscreen")||!strcmp(scenario,"huge-frame")||!strcmp(scenario,"long-frame")) assert(window.changes==0);
    else if(!strcmp(scenario,"fullscreen")) { assert(NSEqualRects(window.frame,second.frame));assert(window.toggles==1); }
    else { assert(NSEqualRects(window.frame,NSMakeRect(-1300,100,1000,700)));assert(window.toggles==0); }
    assert(window.orders==0);
    [buffer fire];assert(posted==0&&states==0&&!launcher.pending&&window.orders==0);
    FixtureBuffer *failed=make();failed.status=MTLCommandBufferStatusError;present(failed,layer);[failed fire];assert(posted==0&&states==0&&!launcher.pending);
    FixtureBuffer *invalid=make();invalid.error=[NSError errorWithDomain:@"fixture" code:1 userInfo:nil];present(invalid,layer);[invalid fire];assert(posted==0&&states==0&&!launcher.pending);
    assert(window.orders==0);
    if(!strcmp(scenario,"order-retry")||!strcmp(scenario,"order-terminal")) window.allowOrder=NO;
    FixtureBuffer *positive=make();present(positive,layer);
    if(!strcmp(scenario,"recreated")) {
      CAMetalLayer *replacement=(CAMetalLayer*)[[[NSObject alloc]init]autorelease];
      launcher_view((NSView*)view,replacement);
      FixtureBuffer *current=make();present(current,replacement);
      [positive fire];assert(posted==0&&states==0&&launcher.pending&&launcher.layer==replacement);
      [current fire];[current fire];
    } else {
      [positive fire];
      if(!strcmp(scenario,"publish-retry")||!strcmp(scenario,"post-retry")||!strcmp(scenario,"order-retry")) {
        assert(!launcher.ready&&!launcher.pending&&launcher.layer==layer&&cancelled==0);
        publishStatus=postStatus=0;window.allowOrder=YES;
        FixtureBuffer *retry=make();present(retry,layer);[retry fire];
      } else if(!strcmp(scenario,"publish-terminal")||!strcmp(scenario,"order-terminal")) {
        for(int i=0;i<2;i++) { FixtureBuffer *retry=make();present(retry,layer);[retry fire]; }
      }
      [positive fire];
    }
    unsigned expectedStates=!strcmp(scenario,"publish-terminal")?3:(!strcmp(scenario,"publish-retry")||!strcmp(scenario,"post-retry")?2:1);
    if(!strcmp(scenario,"order-terminal")) assert(states==0&&posted==0&&cancelled==1&&window.orders==3);
    else {
      assert(states==expectedStates&&cancelled==1&&published==(uint64_t)getpid());
      assert(posted==(!strcmp(scenario,"publish-terminal")?0:!strcmp(scenario,"post-retry")?2:1));
    }
    assert(launcher.layer==nil&&launcher.window==nil&&launcher.token==-1&&!launcher.pending);
    assert(launcher.ready==(strcmp(scenario,"publish-terminal")!=0&&strcmp(scenario,"order-terminal")!=0));
    FixtureBuffer *later=make();present(later,layer);assert(!later.handler);
    puts("bounded rendered-frame and frame case passed");
  }
  return 0;
}

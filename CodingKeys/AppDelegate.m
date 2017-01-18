#import "AppDelegate.h"
#import "AppService.h"
#import "HotKeyService.h"
#import "HotKey.h"
#import "LaunchService.h"
#import <Carbon/Carbon.h>
#import "ChordKey.h"

@interface AppDelegate ()

@property (weak) IBOutlet NSMenu *statusMenu;
@property (strong) NSStatusItem *statusItem;
@property (weak) IBOutlet NSMenuItem *launchAtStartupMenuItem;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [self setup];
}

- (void)setup {
    [self setupNotifications];
    [self registerHotKeys];
}

- (void)awakeFromNib {
    [self setupStatusBarItem];
}

- (void)setupStatusBarItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.menu = self.statusMenu;
    self.statusItem.image = [NSImage imageNamed:@"status_bar_icon"];
    self.statusItem.alternateImage = [NSImage imageNamed:@"status_bar_icon_alternate"];
    self.statusItem.highlightMode = YES;
    
    BOOL isLaunchedAtStartup = [[LaunchService sharedService] isLaunchedAtStartup];
    self.launchAtStartupMenuItem.state = isLaunchedAtStartup ? NSOnState : NSOffState;
}

- (void)setupNotifications {
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(didActivateApplication:)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didTriggerHotKey:)
                                                 name:HotKeyHandlerDidTriggerHotKey
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didTriggerChordKey:)
                                                 name:HotKeyHandlerDidTriggerChordKey
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didChangeConfig:)
                                                 name:AppServiceDidChangeConfig
                                               object:nil];
}

- (void)didActivateApplication:(NSNotification *)notification {
    [self registerHotKeys];
}

- (void)registerHotKeys {
    [self unregisterHotKeys];
    
    NSString *activeAppName = [self activeApplicationName];
    
    if ([[AppService sharedService] isAppRegistered:activeAppName]) {
        [self registerHotKeysForApp:activeAppName];
    }
}

- (void)registerHotKeysForApp:(NSString *)app {
    AppService *asvc = [AppService sharedService];
    HotKeyService *hsvc = [HotKeyService sharedService];

    [hsvc configureWithEnableDynamicRegistration:asvc.enableDynamicRegistration
                                enableChordTimer:asvc.enableChordTimer
                                    chordTimeout:asvc.chordTimeout
                               chordEscapeHotKey:asvc.chordEscapeHotKey
                             chordEscapeKeyCount:asvc.chordEscapeKeyCount];

    //Remveo me
    NSLog(@"APP-NAME:%@ SETTINGS - EnableDynReg:%@ EnableTimer:%@ ", app, @(asvc.enableDynamicRegistration), @(asvc.enableChordTimer));

    NSOrderedSet *hotKeys = [asvc hotKeysForAppWithName:app];
    [hsvc registerHotKeys:hotKeys
                 forAppId:[[asvc idForAppWithName:app] integerValue]];
}

- (void)unregisterHotKeys {
    [[HotKeyService sharedService] unregisterAllHotKeys];
}

- (NSString *)activeApplicationName {
    NSDictionary *activeApp = [[NSWorkspace sharedWorkspace] activeApplication];
    return (NSString *)[activeApp objectForKey:@"NSApplicationName"];
}

- (void)didTriggerHotKey:(NSNotification *)notification {
    //pass hotkey through to app
    HotKey *hotKey = notification.userInfo[@"hotKey"];
    [[HotKeyService sharedService] dispatchKeyEventsForHotKeys:@[hotKey]];
}

- (void)didTriggerChordKey:(NSNotification *)notification {
    ChordKey *chordKey = notification.userInfo[@"chordKey"];

    NSString *appName = [self activeApplicationName];
    NSArray *mappedHotKeys = [HotKey mappedHotKeysForAppWithName:appName
                                                         mapping:chordKey.mapping[appName]];
    if ([mappedHotKeys count] == 0) { return; }

    [[HotKeyService sharedService] dispatchKeyEventsForHotKeys:mappedHotKeys];
}

- (void)didChangeConfig:(NSNotification *)notification {
    [self registerHotKeys];
}

- (IBAction)toggleLaunchAtStartup:(id)sender {
    BOOL enabled = (self.launchAtStartupMenuItem.state == NSOnState);
    self.launchAtStartupMenuItem.state = enabled ? NSOffState : NSOnState;
    
    [[LaunchService sharedService] launchAtStartup:!enabled];
}

- (IBAction)keyMappingsClicked:(id)sender {
    [[AppService sharedService] openKeyMappings];
}

- (IBAction)settingsClicked:(id)sender {
    [[AppService sharedService] openSettings];
}

- (IBAction)helpClicked:(id)sender {
    [[AppService sharedService] openAboutURL];
}

- (IBAction)quitClicked:(id)sender {
    [NSApp terminate:self];
}

@end

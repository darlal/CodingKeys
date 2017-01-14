#import "HotKeyService.h"
#import <Carbon/Carbon.h>
#import "HotKey.h"
#import "ChordKey.h"

NSString * const HotKeyHandlerDidTriggerHotKey = @"HotKeyHandlerDidTriggerHotKey";
NSString * const HotKeyHandlerDidTriggerChordKey = @"HotKeyHandlerDidTriggerChordKey";

@interface HotKeyService ()

@property (nonatomic, strong) NSMutableDictionary *hotKeys;

@property (nonatomic, strong) NSTimer *trackingTimer;
@property (nonatomic, assign) BOOL isTrackingPrefix;
@property (nonatomic, strong) NSMutableOrderedSet *nextChordKeys;
@property (nonatomic, assign) NSInteger currentAppId;

@end

@implementation HotKeyService

static id this;

+ (HotKeyService *)sharedService {
    static HotKeyService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (id)init {
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    this = self;
    
    self.hotKeys = [NSMutableDictionary dictionary];
    self.nextChordKeys = [[NSMutableOrderedSet alloc] init];

    // AppIDs start with 2, so we can be sure that no app will have an ID of 1
    self.currentAppId = 1;
    
    [self installHotKeyHandler];
}

- (void)installHotKeyHandler {
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    
    InstallApplicationEventHandler(&hotKeyHandler,
                                   1,
                                   &eventType,
                                   NULL,
                                   NULL);
}


- (void)registerHotKeys:(NSOrderedSet *)hotKeys forAppId:(NSInteger)appId {
    self.currentAppId = appId;

    for (HotKey *hotKey in hotKeys) {
        [self registerHotKey:hotKey];
    }
}

- (HotKey *)registerHotKey:(HotKey *)hotKey {
    EventHotKeyID hotKeyID;
    hotKeyID.signature = 'cdk1';
    hotKeyID.id = hotKey.keyID;
    
    EventHotKeyRef hotKeyRef;
    OSStatus err = RegisterEventHotKey(hotKey.keyCode,
                                       hotKey.carbonModifiers,
                                       hotKeyID,
                                       GetApplicationEventTarget(),
                                       0,
                                       &hotKeyRef);
    
    if (err != 0) {
        return nil;
    }
    
    hotKey.value = [NSValue valueWithPointer:hotKeyRef];
    
    self.hotKeys[@(hotKey.keyID)] = hotKey;
    
    return hotKey;
}

- (HotKey *)findHotKeyByID:(int)keyID {
    return self.hotKeys[@(keyID)];
}

static OSStatus hotKeyHandler(EventHandlerCallRef nextHandler,
                              EventRef theEvent,
                              void *userData) {

    EventHotKeyID hotKeyID;
    GetEventParameter(theEvent,
                      kEventParamDirectObject,
                      typeEventHotKeyID,
                      NULL,
                      sizeof(hotKeyID),
                      NULL,
                      &hotKeyID);
    
    UInt32 keyID = hotKeyID.id;
    
    HotKey *hotKey = [this findHotKeyByID:keyID];
    
    OSStatus ret = noErr;
    BOOL handled = [this handleChordTrackingForHotKey:hotKey];
    if (!handled) {
        ret = CallNextEventHandler(nextHandler, theEvent);
        if (ret == eventNotHandledErr) {
            // Pass the hotkey through to the app
            [this performSelector:@selector(dispatchNotificationForHotKey:) withObject:hotKey afterDelay:0.2];
        }
    }
    
    return ret;
}

- (void)dispatchNotificationForHotKey:(HotKey *)hotKey {
    [self dispatchNotificationWithName:HotKeyHandlerDidTriggerHotKey
                              userInfo:@{@"hotKey" : hotKey}];
}

- (void)dispatchNotificationForChordKey:(ChordKey *)chordKey {
    [self dispatchNotificationWithName:HotKeyHandlerDidTriggerChordKey
                              userInfo:@{@"chordKey" : chordKey}];
}

- (void)dispatchNotificationWithName:(NSString *)noteName userInfo:(NSDictionary *)info {
    NSNotification *notification = [NSNotification notificationWithName:noteName
                                                                 object:nil
                                                               userInfo:info];
    
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (void)unregisterAllHotKeys {
    // AppIDs start with 2, so we can be sure that no app will have an ID of 1
    self.currentAppId = 1;

    [self cancelTracking];

    NSDictionary *hotKeys = [self.hotKeys copy];
    for (id keyID in hotKeys) {
        [self unregisterHotKey:hotKeys[keyID]];
    }
}

- (void)unregisterHotKey:(HotKey *)hotKey {
    EventHotKeyRef hotKeyRef = (EventHotKeyRef)[hotKey.value pointerValue];
    UnregisterEventHotKey(hotKeyRef);
    hotKey.value = nil;
    [self.hotKeys removeObjectForKey:@(hotKey.keyID)];
}

- (void)dispatchKeyEventsForHotKeys:(NSArray *)hotKeys {
    ProcessSerialNumber processSerialNumber;
    GetFrontProcess(&processSerialNumber);
    
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    
    for (int i = 0; i < [hotKeys count]; i++) {
        HotKey *hotKey = hotKeys[i];
        
        CGEventRef ev;
        ev = CGEventCreateKeyboardEvent(source, (CGKeyCode)hotKey.keyCode, true);
        CGEventSetFlags(ev, hotKey.modifiers);
        CGEventPostToPSN(&processSerialNumber, ev);
        CFRelease(ev);
    }
    
    CFRelease(source);
}

- (BOOL)handleChordTrackingForHotKey:(HotKey *)hotKey {
    BOOL ret = YES;

    if (self.isTrackingPrefix) {
        [self cancelTimer];

        NSMutableOrderedSet *nextChordKeys = [[NSMutableOrderedSet alloc] init];
        ChordKey *trigger = nil;

        for (ChordKey *chordKey in self.nextChordKeys) {
            if ([chordKey.hotKey isEqual:hotKey]) {
                if (chordKey.mapping && !chordKey.nextChordKey) {
                    trigger = chordKey;
                    break;
                } else if (chordKey.nextChordKey) {
                    [nextChordKeys addObject:chordKey.nextChordKey];
                }
            }
        }

        if (trigger) {
            [self dispatchNotificationForChordKey:trigger];
            [self cancelTracking];
        } else if ([nextChordKeys count]) {
            self.nextChordKeys = nextChordKeys;
            [self startTimer];
        }
    } else {
        ChordKey *trigger = nil;

        for (ChordKey *chordKey in hotKey.chordKeys) {
            if (!(chordKey.validAppIds & self.currentAppId)) { continue; }

            if (chordKey.isStandalone) {
                trigger = chordKey;
                break;
            } else if (chordKey.isPrefix && chordKey.nextChordKey) {
                [self.nextChordKeys addObject:chordKey.nextChordKey];
            }
        }

        if (trigger) {
              [self dispatchNotificationForChordKey:trigger];
        } else if ([self.nextChordKeys count]) {
            [self startTrackingPrefix];
        } else {
            ret = NO;
        }

    }

    return ret;
}

- (void)startTrackingPrefix {
    self.isTrackingPrefix = YES;
    [self startTimer];
}

- (void)cancelTracking {
    self.isTrackingPrefix = NO;
    [self.nextChordKeys removeAllObjects];

    [self cancelTimer];
}

- (void)startTimer {
    [self cancelTimer];

    self.trackingTimer = [NSTimer scheduledTimerWithTimeInterval:8.0f
                                                          target:self
                                                        selector:@selector(cancelTracking)
                                                        userInfo:nil
                                                         repeats:NO];
}

- (void)cancelTimer {
    if (self.trackingTimer) {
        [self.trackingTimer invalidate];
        self.trackingTimer = nil;
    }
}



@end

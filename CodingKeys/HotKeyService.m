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
@property (nonatomic, strong) NSOrderedSet *prefixes;

@property (nonatomic, assign) BOOL enableDynamicRegistration;
@property (nonatomic, assign) BOOL enableChordTimer;
@property (nonatomic, assign) NSTimeInterval chordTimeout;


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

    // AppIDs start with 2, so we can be sure that no app will have an ID of 1
    self.currentAppId = 1;
    
    [self installHotKeyHandler];
}

- (void)configureWithEnableDynamicRegistration:(BOOL)dynamicReg
                              enableChordTimer:(BOOL)enableChordTimer
                                  chordTimeout:(NSTimeInterval)chordTimeout {
    self.enableDynamicRegistration = dynamicReg;
    self.enableChordTimer = enableChordTimer;
    self.chordTimeout = chordTimeout;
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
    if (self.enableDynamicRegistration) { self.prefixes = hotKeys; }

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
    BOOL handled = [this handleCapturedHotKey:hotKey];
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

    self.prefixes = nil;
    [self cancelTrackingAndResetPrefixes:NO];

    NSDictionary *hotKeys = [self.hotKeys copy];
    [self unregisterHotKeys:hotKeys exclude:nil];
}

- (void)unregisterHotKeys:(NSDictionary *)hotKeys exclude:(NSOrderedSet *)excludeList {
    for (id keyID in hotKeys) {
        HotKey *hotKey = hotKeys[keyID];

        if (excludeList && [excludeList containsObject:hotKey]) { continue; }
        [self unregisterHotKey:hotKey];
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

- (BOOL)handleCapturedHotKey:(HotKey *)hotKey {
    BOOL ret = YES;

    if (self.isTrackingPrefix) {
        ret = [self handleChordTrackingForHotKey:hotKey
                       enableDynamicRegistration:self.enableDynamicRegistration];
    } else {
        ret = [self handlePrefixTrackingForHotKey:hotKey
                        enableDynamicRegistration:self.enableDynamicRegistration];
    }
    
    return ret;
}

- (BOOL)handlePrefixTrackingForHotKey:(HotKey *)hotKey
            enableDynamicRegistration:(BOOL)dynamicReg {
    BOOL ret = YES;
    ChordKey *trigger = nil;
    NSMutableOrderedSet *nextHotKeys = nil;
    NSDictionary *prevHotKeys = nil;
    NSMutableOrderedSet *nextChordKeys = [[NSMutableOrderedSet alloc] init];

    if (dynamicReg) {
        nextHotKeys = [[NSMutableOrderedSet alloc] init];
        prevHotKeys = [self.hotKeys copy];
    }

    for (ChordKey *chordKey in hotKey.chordKeys) {
        if (!(chordKey.validAppIds & self.currentAppId)) { continue; }

        if (chordKey.isStandalone) {
            trigger = chordKey;
            break;
        } else if (chordKey.isPrefix && chordKey.nextChordKey) {
            if (dynamicReg) {
                HotKey *nextKey = chordKey.nextChordKey.hotKey;
                if (!nextKey.value) { [self registerHotKey:nextKey]; }

                [nextHotKeys addObject:nextKey];
            }

            [nextChordKeys addObject:chordKey.nextChordKey];
        }
    }

    if (trigger) {
        [self dispatchNotificationForChordKey:trigger];
    } else if ([nextChordKeys count]) {

        if (dynamicReg) {
            [self unregisterHotKeys:prevHotKeys exclude:nextHotKeys];
        }

        self.nextChordKeys = nextChordKeys;
        self.isTrackingPrefix = YES;
        [self startTimer];
    } else {
        ret = NO;
    }

    return ret;
}

- (BOOL)handleChordTrackingForHotKey:(HotKey *)hotKey
           enableDynamicRegistration:(BOOL)dynamicReg {
    ChordKey *trigger = nil;
    NSMutableOrderedSet *nextHotKeys = nil;
    NSDictionary *prevHotKeys = nil;
    NSMutableOrderedSet *nextChordKeys = [[NSMutableOrderedSet alloc] init];

    if (dynamicReg) {
        nextHotKeys = [[NSMutableOrderedSet alloc] init];
        prevHotKeys = [self.hotKeys copy];
    }


    [self cancelTimer];

    for (ChordKey *chordKey in self.nextChordKeys) {
        if ([chordKey.hotKey isEqual:hotKey]) {
            if (chordKey.mapping && !chordKey.nextChordKey) {
                trigger = chordKey;
                break;
            } else if (chordKey.nextChordKey) {
                if (dynamicReg) {
                    HotKey *nextKey = chordKey.nextChordKey.hotKey;
                    if (!nextKey.value) { [self registerHotKey:nextKey]; }

                    [nextHotKeys addObject:nextKey];
                }

                [nextChordKeys addObject:chordKey.nextChordKey];
            }
        }
    }

    if (trigger) {
        [self dispatchNotificationForChordKey:trigger];
        [self cancelTrackingAndResetPrefixes:dynamicReg];
    } else if ([nextChordKeys count]) {

        if (dynamicReg) {
            [self unregisterHotKeys:prevHotKeys exclude:nextHotKeys];
        }

        self.nextChordKeys = nextChordKeys;
        [self startTimer];
    }

    return YES;
}

- (void)cancelTrackingAndResetPrefixes:(BOOL)reset {

    self.isTrackingPrefix = NO;
    self.nextChordKeys = nil;
    [self cancelTimer];

    if (self.enableDynamicRegistration && reset) {
        NSDictionary *prevHotKeys = [self.hotKeys copy];

        for (HotKey *hotKey in self.prefixes) {
            if (hotKey.value) { continue; }
            [self registerHotKey:hotKey];
        }

        [self unregisterHotKeys:prevHotKeys exclude:self.prefixes];
    }
}

- (void)startTimer {
    [self cancelTimer];

    if (self.enableChordTimer) {
        self.trackingTimer = [NSTimer scheduledTimerWithTimeInterval:self.chordTimeout
                                                              target:self
                                                            selector:@selector(timerDidRunOut)
                                                            userInfo:nil
                                                             repeats:NO];
    }
}

- (void)cancelTimer {
    if (self.trackingTimer) {
        [self.trackingTimer invalidate];
        self.trackingTimer = nil;
    }
}

- (void)timerDidRunOut {
    [self cancelTrackingAndResetPrefixes:self.enableDynamicRegistration];
}



@end

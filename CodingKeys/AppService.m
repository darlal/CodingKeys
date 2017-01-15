#import "AppService.h"
#import "HotKey.h"
#import "ChordKey.h"

static NSString * const KeysFileName = @"keys";
static NSString * const SettingsFileName = @"settings";
static NSString * const AboutURL = @"https://github.com/fe9lix/CodingKeys";

NSString * const AppServiceDidChangeConfig = @"AppServiceDidChangeConfig";

static NSInteger LastAppId = 1;

@interface AppService () <NSFilePresenter>

@property (nonatomic, strong) NSDictionary *hotKeysForAppId;
@property (nonatomic, strong) NSFileCoordinator *fileCoordinator;
@property (strong) NSURL *presentedItemURL;
@property (strong) NSOperationQueue *presentedItemOperationQueue;
@property (nonatomic, strong) NSTimer *timer;

@property (nonatomic, strong) NSDictionary *idForAppName;
@property (nonatomic, assign, readwrite) BOOL enableDynamicRegistration;
@property (nonatomic, assign, readwrite) BOOL enableChordTimer;
@property (nonatomic, assign, readwrite) NSTimeInterval chordTimeout;

@end

@implementation AppService

+ (AppService *)sharedService {
    static AppService *sharedService = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedService = [[self alloc] init];
    });
    return sharedService;
}

- (id)init {
    self = [super init];
    if (self) {
        _enableDynamicRegistration = YES;
        _enableChordTimer = NO;
        _chordTimeout = 8.0;
        
        [self setup];
    }
    return self;
}

- (void)setup {
    [self setupHotKeysForAppName];
    [self watchKeyFile];
    
    //TODO: REmove me
    NSLog(@"Done - setup");
}

- (void)setupHotKeysForAppName {
    [self readSettings];
    
    NSArray *keyMappings = [self loadJSONFile:KeysFileName];

    NSMutableDictionary *hotKeysForAppId = [NSMutableDictionary dictionary];
    NSMutableDictionary *idForAppName = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *allHotKeys = [[NSMutableDictionary alloc] init];

    for (NSDictionary *keyMapping in keyMappings) {
        NSString *chordString = [keyMapping[@"key"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![chordString length]) { continue; }

        NSDictionary *mapping = keyMapping[@"mapping"];
        NSInteger validAppIds = [self validAppIdsForMapping:mapping
                                                 appNameIds:idForAppName];

        NSOrderedSet *hotKeyList;
        hotKeyList = [self generateKeysForChordString:chordString
                                              mapping:mapping
                                          validAppIds:validAppIds
                                           allHotKeys:allHotKeys
                            enableDynamicRegistration:self.enableDynamicRegistration];

        if (![hotKeyList count]) { continue; }

        for (NSString *appName in mapping) {
            NSNumber *appId = [idForAppName objectForKey:appName];

            if (![hotKeysForAppId objectForKey:appId]) {
                [hotKeysForAppId setObject:[[NSMutableOrderedSet alloc] init] forKey:appId];
            }

            NSString *mappedKey = mapping[appName];
            if (![mappedKey isEqualToString:chordString]) {
                [[hotKeysForAppId objectForKey:appId] unionOrderedSet:hotKeyList];
            }
        }
    }

    self.hotKeysForAppId = hotKeysForAppId;
    self.idForAppName = idForAppName;
}

- (NSInteger)validAppIdsForMapping:(NSDictionary *)mapping
                        appNameIds:(NSMutableDictionary *)idForAppName {
    NSInteger validAppIds = 0;

    for (NSString *appName in mapping) {
        NSNumber *appId = [idForAppName objectForKey:appName];
        if (!appId) {
            appId = @(LastAppId *= 2);
            [idForAppName setObject:appId forKey:appName];
        }

        validAppIds |= [appId integerValue];
    }

    return validAppIds;
}

- (NSOrderedSet *)generateKeysForChordString:(NSString *)chordString
                                     mapping:(NSDictionary *)mapping
                                 validAppIds:(NSInteger)validAppIds
                                  allHotKeys:(NSMutableDictionary *)allHotKeys
                   enableDynamicRegistration:(BOOL)dynReg
{
    NSArray *chordStringkeys = [chordString componentsSeparatedByString:@"|"];
    if (![chordStringkeys count]) { return nil; }

    NSMutableOrderedSet *hotKeyList = [[NSMutableOrderedSet alloc] init];

    ChordKey *nextChordKey = nil;
    NSInteger chordStringKeysCount = [chordStringkeys count];
    BOOL isStandalone = chordStringKeysCount == 1;
    NSInteger numKeys = chordStringKeysCount - 1;

    for (NSInteger i = numKeys; i >= 0; i--) {
        NSString *stringKey = [chordStringkeys[i] stringByTrimmingCharactersInSet:
                               [NSCharacterSet whitespaceCharacterSet]];
        if (![stringKey length]) {
            [hotKeyList removeAllObjects];
            break;
        }

        HotKey *temp = [[HotKey alloc] initWithKey:stringKey];
        HotKey *hotKey = [allHotKeys objectForKey:@(temp.hash)];
        if (!hotKey) {
            hotKey = temp;
            [allHotKeys setObject:hotKey forKey:@(hotKey.hash)];
        }

        BOOL isPrefix = (i == 0) && chordStringKeysCount > 1;
        ChordKey *chordKey = [[ChordKey alloc] initWithValidAppIds:validAppIds
                                                            hotKey:hotKey
                                                          isPrefix:isPrefix
                                                      nextChordKey:nextChordKey
                                                           mapping:i == numKeys ? mapping : nil
                                                      isStandalone:isStandalone];
        if (dynReg) {
            if (isStandalone || isPrefix) { [hotKeyList addObject:hotKey]; }
        } else {
            [hotKeyList addObject:hotKey];
        }

        [hotKey.chordKeys addObject:chordKey];
        nextChordKey = chordKey;
    }

    return hotKeyList;
}

- (void)readSettings {
    //REMOVE ME
    NSLog(@"SETTINGS-FILE: %@", [self pathForFile:SettingsFileName]);

    NSArray *list = [self loadJSONFile:SettingsFileName];
    NSDictionary *settings = [list firstObject];
    if (!settings) { return; }

    id val = [settings objectForKey:@"enableDynamicRegistration"];
    if (val != nil) { self.enableDynamicRegistration = [val boolValue]; }

    val = [settings objectForKey:@"enableChordTimer"];
    if (val != nil) { self.enableChordTimer = [val boolValue]; }

    val = [settings objectForKey:@"chordTimeout"];
    if (val != nil) { self.chordTimeout = [val doubleValue]; }
}

- (NSArray *)loadJSONFile:(NSString *)file {
    NSError *error;
    NSString *jsonString = [NSString stringWithContentsOfFile:[self pathForFile:file]
                                                     encoding:NSUTF8StringEncoding
                                                        error:&error];
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];    return [NSJSONSerialization JSONObjectWithData:jsonData
                                           options:0
                                             error:nil];
}

- (NSString *)pathForFile:(NSString *)file {
    return [[NSBundle mainBundle] pathForResource:file
                                           ofType:@"json"];
}

- (void)watchKeyFile {
    self.presentedItemOperationQueue = [[NSOperationQueue alloc] init];
    self.presentedItemOperationQueue.maxConcurrentOperationCount = 1;
    
    self.presentedItemURL = [[NSBundle mainBundle] resourceURL];
    
    self.fileCoordinator = [[NSFileCoordinator alloc] initWithFilePresenter:self];
    
    [NSFileCoordinator addFilePresenter:self];
}

- (void)presentedItemDidChange {
    [self.timer invalidate];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5f
                                                      target:self
                                                    selector:@selector(configDidChange:)
                                                    userInfo:nil
                                                     repeats:NO];
    });
}

- (void)configDidChange:(id)obj {
    [self setupHotKeysForAppName];
    [self dispatchConfigDidChangeNotification];
}

- (void)dispatchConfigDidChangeNotification {
    NSNotification *notification = [NSNotification notificationWithName:AppServiceDidChangeConfig
                                                                 object:nil
                                                               userInfo:nil];
    
    [[NSNotificationCenter defaultCenter] postNotification:notification];
}

- (BOOL)isAppRegistered:(NSString *)appName {
    return [self idForAppWithName:appName] != nil;
}

- (NSOrderedSet *)hotKeysForAppWithName:(NSString *)appName {
    return self.hotKeysForAppId[[self idForAppWithName:appName]];
}

- (NSNumber *)idForAppWithName:(NSString *)appName {
    return [self.idForAppName objectForKey:appName];
}

- (void)openKeyMappings {
    [[NSWorkspace sharedWorkspace] openFile:[self pathForFile:KeysFileName]];
}

- (void)openSettings {
    [[NSWorkspace sharedWorkspace] openFile:[self pathForFile:SettingsFileName]];
}

- (void)openAboutURL {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:AboutURL]];
}

@end

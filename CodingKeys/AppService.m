#import "AppService.h"
#import "HotKey.h"
#import "ChordKey.h"

static NSString * const KeysFileName = @"keys";
static NSString * const AboutURL = @"https://github.com/fe9lix/CodingKeys";

NSString * const AppServiceDidChangeHotKeys = @"AppServiceDidChangeHotKeys";

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
    NSArray *keyMappings = [self loadKeyMappingsFile];

    NSMutableDictionary *hotKeysForAppId = [NSMutableDictionary dictionary];
    NSMutableDictionary *idForAppName = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *allHotKeys = [[NSMutableDictionary alloc] init];

    for (NSDictionary *keyMapping in keyMappings) {
        NSString *chordString = [keyMapping[@"key"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (![chordString length]) { continue; }

        NSDictionary *mapping = keyMapping[@"mapping"];
        NSInteger validAppIds = 0;

        for (NSString *appName in mapping) {
            NSNumber *appId = [idForAppName objectForKey:appName];
            if (!appId) {
                appId = @(LastAppId *= 2);
                [idForAppName setObject:appId forKey:appName];
            }

            validAppIds |= [appId integerValue];
        }

        NSArray *chordStringkeys = [chordString componentsSeparatedByString:@"|"];
        if (![chordStringkeys count]) { continue; }

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

            [hotKey.chordKeys addObject:chordKey];
            [hotKeyList addObject:hotKey];
            nextChordKey = chordKey;
        }

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

- (NSArray *)loadKeyMappingsFile {
    NSError *error;
    NSString *jsonString = [NSString stringWithContentsOfFile:[self keysFilePath]
                                                     encoding:NSUTF8StringEncoding
                                                        error:&error];
    NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    
    return [NSJSONSerialization JSONObjectWithData:jsonData
                                           options:0
                                             error:nil];
}

- (NSString *)keysFilePath {
    return [[NSBundle mainBundle] pathForResource:KeysFileName
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
                                                    selector:@selector(keysDidChange:)
                                                    userInfo:nil
                                                     repeats:NO];
    });
}

- (void)keysDidChange:(id)obj {
    [self setupHotKeysForAppName];
    [self dispatchKeysDidChangeNotification];
}

- (void)dispatchKeysDidChangeNotification {
    NSNotification *notification = [NSNotification notificationWithName:AppServiceDidChangeHotKeys
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
    [[NSWorkspace sharedWorkspace] openFile:[self keysFilePath]];
}

- (void)openAboutURL {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:AboutURL]];
}

@end

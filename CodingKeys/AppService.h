#import <Foundation/Foundation.h>

NSString * const AppServiceDidChangeHotKeys;

@interface AppService : NSObject

@property (nonatomic, assign, readonly) BOOL enableDynamicRegistration;
@property (nonatomic, assign, readonly) BOOL enableChordTimer;
@property (nonatomic, assign, readonly) NSTimeInterval chordTimeout;

+ (instancetype)sharedService;

- (BOOL)isAppRegistered:(NSString *)appName;
- (NSNumber *)idForAppWithName:(NSString *)appName;
- (NSOrderedSet *)hotKeysForAppWithName:(NSString *)appName;
- (void)openKeyMappings;
- (void)openAboutURL;

@end

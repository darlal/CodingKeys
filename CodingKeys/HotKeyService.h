#import <Foundation/Foundation.h>

extern NSString * const HotKeyHandlerDidTriggerHotKey;
extern NSString * const HotKeyHandlerDidTriggerChordKey;

@class HotKey;

@interface HotKeyService : NSObject

+ (instancetype)sharedService;

- (void)configureWithEnableDynamicRegistration:(BOOL)dynamicReg
                              enableChordTimer:(BOOL)enableChordTimer
                                  chordTimeout:(NSTimeInterval)chordTimeout;
- (void)registerHotKeys:(NSOrderedSet *)hotKeys forAppId:(NSInteger)appId;
- (HotKey *)registerHotKey:(HotKey *)hotKey;
- (void)unregisterAllHotKeys;
- (void)dispatchKeyEventsForHotKeys:(NSArray *)hotKeys;

@end

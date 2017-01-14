#import <Foundation/Foundation.h>

@interface HotKey : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, readonly) int keyCode;
@property (nonatomic, readonly) int modifiers;
@property (nonatomic, readonly) int carbonModifiers;
@property (nonatomic, readonly) UInt32 keyID;
@property (nonatomic, strong) NSValue *value;

@property (nonatomic, strong, readonly) NSMutableOrderedSet *chordKeys;

- (id)initWithKey:(NSString *)key;

+ (NSArray *)mappedHotKeysForAppWithName:(NSString *)appName mapping:(NSString *)mapping;

@end

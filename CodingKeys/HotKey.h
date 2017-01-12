#import <Foundation/Foundation.h>

@interface HotKey : NSObject

@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, readonly) int keyCode;
@property (nonatomic, readonly) int modifiers;
@property (nonatomic, readonly) int carbonModifiers;
@property (nonatomic) int keyID;
@property (nonatomic, strong) NSValue *value;

@property (nonatomic, strong, readonly) NSMutableOrderedSet *chordKeys;

- (id)initWithKey:(NSString *)key;

@end
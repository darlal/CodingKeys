#import "HotKey.h"
#import "KeyCodeConverter.h"
#import <Carbon/Carbon.h>

@interface HotKey ()

@property (nonatomic, copy, readwrite) NSString *key;
@property (nonatomic, readwrite) int keyCode;
@property (nonatomic, readwrite) int modifiers;
@property (nonatomic, readwrite) int carbonModifiers;

@property (nonatomic, strong, readwrite) NSMutableOrderedSet *chordKeys;

@end

@implementation HotKey

- (id)initWithKey:(NSString *)key {
    self = [super init];
    if (self) {
        _key = key;
        _chordKeys = [[NSMutableOrderedSet alloc] init];

        [self setup];
    }
    return self;
}

- (void)setup {
    [self parseKey];
}

- (void)parseKey {
    NSDictionary *fixKeys = [KeyCodeConverter fixKeys];
    
    NSArray *components = [self.key componentsSeparatedByString:@" "];
    
    int modifiers = 0;
    int carbonModifiers = 0;
    
    for (NSString *component in components) {
        int keyCode = [fixKeys[component] intValue];
        
        switch (keyCode) {
            case kVK_Shift:
                modifiers |= kCGEventFlagMaskShift;
                carbonModifiers |= shiftKey;
                break;
            case kVK_Control:
                modifiers |= kCGEventFlagMaskControl;
                carbonModifiers |= controlKey;
                break;
            case kVK_Option:
                modifiers |= kCGEventFlagMaskAlternate;
                carbonModifiers |= optionKey;
                break;
            case kVK_Command:
                modifiers |= kCGEventFlagMaskCommand;
                carbonModifiers |= cmdKey;
                break;
            default:
                if (fixKeys[component]) {
                    self.keyCode = keyCode;
                } else {
                    self.keyCode = [KeyCodeConverter toKeyCode:component];
                }
                break;
        }
    }
    
    self.modifiers = modifiers;
    self.carbonModifiers = carbonModifiers;
}

- (NSArray *)mappedHotKeysForAppWithName:(NSString *)appName {
    NSString *mapping = self.mapping[appName];
    NSArray *mappingComponents = [mapping componentsSeparatedByString:@"|"];
    NSMutableArray *mappedKeys = [NSMutableArray array];
    
    for (NSString *mappingComponent in mappingComponents) {
        NSString *trimmedComponent = [mappingComponent stringByTrimmingCharactersInSet:
                                      [NSCharacterSet whitespaceCharacterSet]];

        if (![trimmedComponent length]) {
            [mappedKeys removeAllObjects];
            break;
        }

        HotKey *hotKey = [[HotKey alloc] initWithKey:trimmedComponent
                                             mapping:nil];
        [mappedKeys addObject:hotKey];
    }
    
    return mappedKeys;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"key: %@, keyCode: %d, modifiers: %d",
            self.key, self.keyCode, self.modifiers];
}

- (NSUInteger)hash {
    return self.keyCode ^ self.modifiers;
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    }
    BOOL equal = NO;
    if ([object isKindOfClass:[HotKey class]]) {
        HotKey *hotKey = (HotKey *)object;
        equal = (hotKey.keyCode == self.keyCode);
        equal &= (hotKey.modifiers == self.modifiers);
    }
    return equal;
}

@end

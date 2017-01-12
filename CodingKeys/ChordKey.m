//
//  HotKeyNode.m
//  CodingKeys
//
//  Created by Darla Louis on 1/5/17.
//
//


#import "HotKey.h"
#import "ChordKey.h"

@interface ChordKey()

@property (nonatomic, assign, readwrite) NSInteger validAppIds;
@property (nonatomic, strong, readwrite) HotKey *hotKey;
@property (nonatomic, strong, readwrite) ChordKey *nextChordKey;
@property (nonatomic, assign, readwrite) BOOL isPrefix;
@property (nonatomic, strong, readwrite) NSDictionary *mapping;
@property (nonatomic, assign, readwrite) BOOL isStandalone;

@end

@implementation ChordKey

- (id)initWithValidAppIds:(NSInteger)validAppIds
                   hotKey:(HotKey *)hotKey
                 isPrefix:(BOOL)isPrefix
             nextChordKey:(ChordKey *)nextChordKey
                  mapping:(NSDictionary *)mapping
             isStandalone:(BOOL)isStandalone {
    self = [super init];
    if (self) {
        _validAppIds = validAppIds;
        _hotKey = hotKey;
        _nextChordKey = nextChordKey;
        _isPrefix = isPrefix;
        _mapping = mapping;
        _isStandalone = isStandalone;
    }
    return self;
}

@end

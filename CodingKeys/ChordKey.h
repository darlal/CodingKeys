//
//  HotKeyNode.h
//  CodingKeys
//
//  Created by Darla Louis on 1/5/17.
//
//

#import <Foundation/Foundation.h>

@class HotKey;


@interface ChordKey : NSObject 

@property (nonatomic, assign, readonly) NSInteger validAppIds;
@property (nonatomic, strong, readonly) HotKey *hotKey;
@property (nonatomic, strong, readonly) ChordKey *nextChordKey;
@property (nonatomic, assign, readonly) BOOL isPrefix;
@property (nonatomic, strong, readonly) NSDictionary *mapping;
@property (nonatomic, assign, readonly) BOOL isStandalone;

- (id)initWithValidAppIds:(NSInteger)validAppIds
                   hotKey:(HotKey *)hotKey
                 isPrefix:(BOOL)isPrefix
             nextChordKey:(ChordKey *)nextChordKey
                  mapping:(NSDictionary *)mapping
             isStandalone:(BOOL)isStandalone;


@end

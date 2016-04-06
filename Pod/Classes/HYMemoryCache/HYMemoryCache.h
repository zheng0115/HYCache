//
//  HYMemoryCache.h
//  Pods
//
//  Created by fangyuxi on 16/4/5.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HYMemoryCache;

typedef void (^HYMemoryCacheBlock) (HYMemoryCache *cache);
typedef void (^HYMemoryCacheObjectBlock) (HYMemoryCache *cache, NSString *key, id __nullable object);


@interface HYMemoryCache : NSObject

+ (instancetype)sharedCache;

@property (nonatomic, assign, readonly) NSUInteger totalCostNow;
@property (nonatomic, assign) NSUInteger costLimit;

@property (nonatomic, assign) NSTimeInterval maxAge;

@property(nonatomic, assign) BOOL removeObjectWhenAppReceiveMemoryWarning;
@property(nonatomic, assign) BOOL removeObjectWhenAppEnterBackground;

- (void)setObject:(id)object
           forKey:(id)key
        withBlock:(__nullable HYMemoryCacheObjectBlock)block;

- (void)setObject:(id)object
           forKey:(id)key;

- (void)setObject:(id)object
           forKey:(id)key
         withCost:(NSUInteger)cost
        withBlock:(__nullable HYMemoryCacheObjectBlock)block;

- (void)setObject:(id)object
           forKey:(id)key
         withCost:(NSUInteger)cost;

- (id __nullable )objectForKey:(NSString *)key;

- (void)objectForKey:(id)key
           withBlock:(HYMemoryCacheObjectBlock)block;

- (void)removeObjectForKey:(id)key
                 withBlock:(__nullable HYMemoryCacheObjectBlock)block;

- (void)removeObjectForKey:(id)key;

- (void)removeAllObjectWithBlock:(__nullable HYMemoryCacheBlock)block;

- (void)removeAllObject;

- (BOOL)containsObjectForKey:(id)key;


@end

NS_ASSUME_NONNULL_END
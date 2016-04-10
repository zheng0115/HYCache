//
//  HYDiskCache.h
//  Pods
//
//  Created by fangyuxi on 16/4/5.
//
//

#import <Foundation/Foundation.h>

///benckMark

// SmallValue 1000 key-value  value = NSNumber

// Write 8909.52 ms
// replace 6105.77 ms
// remove 128.00 ms


NS_ASSUME_NONNULL_BEGIN

@class HYDiskCache;

typedef void (^HYDiskCacheBlock) (HYDiskCache *cache);
typedef void (^HYDiskCacheObjectBlock) (HYDiskCache *cache, NSString *key, id __nullable object);

@interface HYDiskCache : NSObject // all method & proterty thread-safe

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;

- (instancetype)initWithName:(NSString *)name;

- (instancetype)initWithName:(NSString *)name
            andDirectoryPath:(NSString *)directoryPath NS_DESIGNATED_INITIALIZER;

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *directoryPath;
@property (nonatomic, copy, readonly) NSString *cachePath;

/**
 *  当前的cost，当超过byteCostLimit的时候，移除策略为LRU
 */
@property (nonatomic, assign, readonly) NSUInteger totalByteCostNow;

/**
 *  设置最大cost
 */
@property (nonatomic, assign) NSUInteger byteCostLimit;

/**
 *  设置存储对象的最大生命周期，如果为0，则永远存在，默认0
 */
@property (nonatomic, assign) NSTimeInterval maxAge;

/**
 *  如果maxAge不为0，那么cache会定时移除生命周期已经大于maxAge以及customAge的对象
    如果maxAge为0，则忽略这个属性
 */
@property (nonatomic, assign) NSTimeInterval trimToMaxAgeInterval;

/**
 *  对于没有遵循NSCoding协议的一类对象，可以在这个block中定义自己的archive逻辑
 */
@property (nullable, copy) NSData *(^customArchiveBlock)(id object);

@property (nullable, copy) id (^customUnarchiveBlock)(NSData *data);

/**
 *  可以自定义一类对象的maxAge，如果一类对象自定义了maxAge，那么会覆盖上面cache 的 maxAge
 */
@property (nonatomic, copy) NSTimeInterval (^customMaxAge)(id object);

/**
 *  异步存储对象，该方法会立即返回，添加完毕之后block会在内部的concurrent queue中回调
    block
 *
 *  @param object 存储的对象，如果为空，则不会插入，block对象会回调
 *  @param key    存储对象的键，如果为空，则不会插入，block对象会回调
 *  @param block  存储结束的回调，在concurrent queue中执行
 */
- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key
        withBlock:(__nullable HYDiskCacheObjectBlock)block;

/**
 *  同步移除对象
 *
 *  @param object 存储的对象，如果为空，则不会插入
 *  @param key    存储对象的键，如果为空，则不会插入
 */
- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key;

/**
 *  异步获取对象，该方法会立即返回，获取完毕之后block会在内部的concurrent queue中回调
 *
 *  @param key   存储对象的键，不能为空
 *  @param block 返回值 key object  cache object
 */
- (void)objectForKey:(id)key
           withBlock:(HYDiskCacheObjectBlock)block;

/**
 *  同步获取对象，该方法会阻塞调用的线程，直到获取完成
 *
 *  @param key 存储对象的键，不能为空
 *
 *  @return 如果没找到相应object则返回空
 */
- (id __nullable )objectForKey:(NSString *)key;

/**
 *  异步移除对象，移除完毕之后block会在内部的concurrent queue中回调
 *
 *  @param key   存储对象的键，不能为空
 *  @param block 返回值 cache object
 */
- (void)removeObjectForKey:(NSString *)key
                 withBlock:(__nullable HYDiskCacheBlock)block;

/**
 *  同步移除对象
 *
 *  @param key 存储对象的键，不能为空
 */
- (void)removeObjectForKey:(NSString *)key;

/**
 *  异步移除一组对象，移除完毕之后block会在内部的concurrent queue中回调
 *
 *  @param key   存储对象的键，不能为空
 *  @param block 返回值 cache object
 */
- (void)removeObjectForKeys:(NSArray<NSString *> *)keys
                  withBlock:(__nullable HYDiskCacheBlock)block;

/**
 *  异步移除所有对象，移除完毕之后block会在内部的concurrent queue中回调
 *
 *  @param block 返回值 cache object
 */
- (void)removeAllObjectWithBlock:(__nullable HYDiskCacheBlock)block;

/**
 *  同步移除所有对象
 */
- (void)removeAllObject;

/**
 *  查询是否包含这个key value
 *
 *  @param key 存储对象的键，不能为空
 *
 *  @return 如果有，那么block中的object对象不为空
 */
- (void)containsObjectForKey:(id)key
                       block:(nullable HYDiskCacheObjectBlock)block;

/**
 *  移除对象，直到totalCostNow <= cost
 *
 *  @param cost  cost
 *  @param block 移除完毕之后block会在内部的concurrent queue中回调
 */
- (void)trimToCost:(NSUInteger)cost
             block:(nullable HYDiskCacheBlock)block;

/**
 *  移除对象，直到totalCostNow <= costLimit
 *
 *  @param block 移除完毕之后block会在内部的concurrent queue中回调
 */
- (void)trimToCostLimitWithBlock:(nullable HYDiskCacheBlock)block;

@end

NS_ASSUME_NONNULL_END













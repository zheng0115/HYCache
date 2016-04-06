//
//  HYMemoryCache.m
//  Pods
//
//  Created by fangyuxi on 16/4/5.
//
//

#import "HYMemoryCache.h"
#import <pthread.h>
#import <libkern/OSAtomic.h>

static NSString *const queueNamePrefix = @"com.HYCache.";
static OSSpinLock mutexLock;

#pragma mark lock

static inline void lock()
{
    OSSpinLockLock(&mutexLock);
}

static inline void unLock()
{
    OSSpinLockUnlock(&mutexLock);
}

#pragma mark _HYMemoryCacheItem

@interface _HYMemoryCacheItem : NSObject
{
    @package //need access in this framework
    id _key;
    id _object;
    NSUInteger _cost;
    NSTimeInterval _age;
}

@end

@implementation _HYMemoryCacheItem
@end

#pragma mark HYMemoryCache

@interface HYMemoryCache ()
{
    CFMutableDictionaryRef _objectDic;
}

@property (nonatomic, strong) dispatch_queue_t concurrentQueue;
@property (nonatomic, copy, readwrite) NSString *name;
@end

@implementation HYMemoryCache

@synthesize totalCostNow = _totalCostNow;
@synthesize costLimit = _costLimit;
@synthesize maxAge = _maxAge;

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    CFRelease(_objectDic);
}

- (instancetype)init
{
    return [self initWithName:@"HYMemoryCache"];
}

- (instancetype)initWithName:(NSString *)name
{
    self = [super init];
    if (self)
    {
        mutexLock = OS_SPINLOCK_INIT;
        self.name = name;
        _concurrentQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@%@", queueNamePrefix, name] UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        _objectDic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0,&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
        _removeObjectWhenAppEnterBackground = YES;
        _removeObjectWhenAppReceiveMemoryWarning = YES;
        _totalCostNow = 0;
        _costLimit = 0;
        _maxAge = 0.0;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveEnterBackgroundNotification:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveMemoryWarningNotification:)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];
        
        return self;
    }
    return nil;
}



#pragma mark notification

- (void)didReceiveMemoryWarningNotification:(NSNotification *)notification
{
    if (self.removeObjectWhenAppReceiveMemoryWarning)
    {
        [self removeAllObjectWithBlock:^(HYMemoryCache * _Nonnull cache) {
            
        }];
    }
}

- (void)didReceiveEnterBackgroundNotification:(NSNotification *)notification
{
    if (self.removeObjectWhenAppEnterBackground)
    {
        [self removeAllObjectWithBlock:^(HYMemoryCache * _Nonnull cache) {
            
        }];
    }
}

#pragma mark store

- (void)setObject:(id)object
           forKey:(id)key
        withBlock:(__nullable HYMemoryCacheObjectBlock)block
{
    __weak HYMemoryCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        
        HYMemoryCache *stronglySelf = weakSelf;
        
        [self setObject:object forKey:key];
        
        if (block)
        {
            block(stronglySelf, key, object);
        }
    });
}

- (void)setObject:(id)object
           forKey:(id)key
         withCost:(NSUInteger)cost
        withBlock:(__nullable HYMemoryCacheObjectBlock)block
{
    __weak HYMemoryCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
       
        HYMemoryCache *stronglySelf = weakSelf;
        
        [self setObject:object forKey:key withCost:cost];
        
        if (block)
        {
            block(stronglySelf, key, object);
        }
    });
}

- (void)setObject:(id)object
           forKey:(id)key
{
    [self setObject:object forKey:key withCost:0];
}

- (void)setObject:(id)object
           forKey:(id)key
         withCost:(NSUInteger)cost
{
    if (!object || !key) return;
    
    _HYMemoryCacheItem *item = [self objectForKey:key];
    lock();
    if (item)
    {
        item->_object = object;
        item->_key = key;
        item->_cost = cost;
        item->_age = CACurrentMediaTime();
        _totalCostNow = cost > item->_cost ? cost - item->_cost : item->_cost - cost;
    }
    else
    {
        _HYMemoryCacheItem *item = [_HYMemoryCacheItem new];
        item->_object = object;
        item->_key = key;
        item->_cost = cost;
        item->_age = CACurrentMediaTime();
        _totalCostNow += cost;
        CFDictionarySetValue(_objectDic, (__bridge const void *)key, (__bridge const void *)item);
    }
    unLock();
}

#pragma mark get value

- (id __nullable )objectForKey:(id)key
{
    if (!key) return nil;
    
    lock();
    _HYMemoryCacheItem *item = CFDictionaryGetValue(_objectDic, (__bridge const void *)key);
    unLock();
    
    if (item) return item->_object;
    return nil;
}

- (void)objectForKey:(NSString *)key
           withBlock:(HYMemoryCacheObjectBlock)block
{
    __weak HYMemoryCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        
        HYMemoryCache *stronglySelf = weakSelf;
        
        id object = [self objectForKey:key];
        
        if (block)
        {
            block(stronglySelf, key, object);
        }
    });
}

#pragma mark remove value

- (void)removeObjectForKey:(NSString *)key
                 withBlock:(__nullable HYMemoryCacheObjectBlock)block
{
    __weak HYMemoryCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        
        HYMemoryCache *stronglySelf = weakSelf;
        
        _HYMemoryCacheItem *item = [self objectForKey:key];
        [self removeObjectForKey:key];
        
        if (block)
        {
            block(stronglySelf, key, item);
        }
    });
}

- (void)removeObjectForKey:(id)key
{
    if(!key) return;
    
    lock();
    _HYMemoryCacheItem *item = CFDictionaryGetValue(_objectDic, (__bridge const void *)key);
    if (item)
    {
        _totalCostNow -= item->_cost;
        CFDictionaryRemoveValue(_objectDic, (__bridge const void *)key);
    }
    unLock();
}


- (void)removeAllObjectWithBlock:(__nullable HYMemoryCacheBlock)block
{
    __weak HYMemoryCache *weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        
        HYMemoryCache *stronglySelf = weakSelf;
        
        [self removeAllObject];
        
        if (block)
        {
            block(stronglySelf);
        }
    });
}

- (void)removeAllObject
{
    lock();
    _totalCostNow = 0;
    CFDictionaryRemoveAllValues(_objectDic);
    unLock();
}

- (BOOL)containsObjectForKey:(id)key
{
    if (!key) return NO;
    
    lock();
    _HYMemoryCacheItem *item = CFDictionaryGetValue(_objectDic, (__bridge const void *)key);
    unLock();
    
    return item != nil;
}

#pragma mark getter setter

- (NSUInteger)totalCostNow
{
    lock();
    NSUInteger cost = _totalCostNow;
    unLock();
    return cost;
}

- (NSUInteger)costLimit
{
    lock();
    NSUInteger cost = _costLimit;
    unLock();
    return cost;
}

- (void)setCostLimit:(NSUInteger)costLimit
{
    lock();
    _costLimit = costLimit;
    unLock();
}

- (void)setMaxAge:(NSTimeInterval)maxAge
{
    lock();
    _maxAge = maxAge;
    unLock();
}

- (NSTimeInterval)maxAge
{
    lock();
    NSTimeInterval age = _maxAge;
    unLock();
    return age;
}

@end






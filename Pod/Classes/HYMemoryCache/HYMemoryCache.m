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

static NSString *const queueName = @"com.hy.memcache.queueName";
static OSSpinLock mutexLock;

static inline void lock()
{
    OSSpinLockLock(&mutexLock);
}

static inline void unLock()
{
    OSSpinLockUnlock(&mutexLock);
}


@interface HYMemoryCache ()
{
    CFMutableDictionaryRef _objectDic;
    CFMutableDictionaryRef _datesDic;
    CFMutableDictionaryRef _costsDic;
}

@property (nonatomic, strong) dispatch_queue_t concurrentQueue;
//@property(nonatomic, unsafe_unretained) __attribute__((NSObject)) CFMutableDictionaryRef costsDic;

@end

@implementation HYMemoryCache

@synthesize totalCostNow = _totalCostNow;
@synthesize costLimit = _costLimit;
@synthesize maxAge = _maxAge;

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)sharedCache
{
    static id cache;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        cache = [[self alloc] init];
    });
    
    return cache;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        mutexLock = OS_SPINLOCK_INIT;
        _concurrentQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        _objectDic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0,&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        _datesDic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0,&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        _costsDic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0,&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        
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

- (void)didReceiveEnterBackgroundNotification:(NSNotification *)notification
{
    
}

- (void)didReceiveMemoryWarningNotification:(NSNotification *)notification
{
    
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
    
    lock();
    _totalCostNow += cost;
    CFDictionarySetValue(_objectDic, (__bridge const void *)key, (__bridge const void *)object);
    CFDictionarySetValue(_datesDic, (__bridge const void *)key, (__bridge const void *)[NSDate new]);
    CFDictionarySetValue(_costsDic, (__bridge const void *)key, (__bridge const void *)@(cost));
    unLock();
}

#pragma mark get value

- (id __nullable )objectForKey:(id)key
{
    if (!key) return nil;
    
    lock();
    id object = CFDictionaryGetValue(_objectDic, (__bridge const void *)key);
    unLock();
    
    return object;
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

}

- (void)removeObjectForKey:(id)key
{
    
}


- (void)removeAllObjectWithBlock:(__nullable HYMemoryCacheBlock)block
{
    
}

- (void)removeAllObject
{
    
}

- (BOOL)containsObjectForKey:(id)key
{
    return YES;
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






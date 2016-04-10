//
//  HYDiskCache.m
//  Pods
//
//  Created by fangyuxi on 16/4/5.
//
//

#import "HYDiskCache.h"

static NSString *const dataQueueNamePrefix = @"com.HYDiskCache.ConcurrentQueue.";

static NSString *const dataPath = @"data";
static NSString *const trushPath = @"trush";


///////////////////////////////////////////////////////////////////////////////
#pragma mark HYCacheBackgourndTask
///////////////////////////////////////////////////////////////////////////////
@interface _HYCacheBackgourndTask : NSObject

@property (nonatomic, assign) UIBackgroundTaskIdentifier taskId;

+ (instancetype)_startBackgroundTask;
- (void)_endTask;

@end

@implementation _HYCacheBackgourndTask

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        self.taskId = UIBackgroundTaskInvalid;
        self.taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            
            UIBackgroundTaskIdentifier taskId = self.taskId;
            self.taskId = UIBackgroundTaskInvalid;
            
            [[UIApplication sharedApplication] endBackgroundTask:taskId];
        }];
        return self;
    }
    return nil;
}

+ (instancetype)_startBackgroundTask
{
    return [[self alloc] init];
}

- (void)_endTask
{
    UIBackgroundTaskIdentifier taskId = self.taskId;
    self.taskId = UIBackgroundTaskInvalid;
    
    [[UIApplication sharedApplication] endBackgroundTask:taskId];
}

@end

#pragma mark lock

dispatch_semaphore_t semaphoreLock;

static inline void lock()
{
    dispatch_semaphore_wait(semaphoreLock, DISPATCH_TIME_FOREVER);
}

static inline void unLock()
{
    dispatch_semaphore_signal(semaphoreLock);
}

///////////////////////////////////////////////////////////////////////////////
#pragma mark linked map used for LRU
///////////////////////////////////////////////////////////////////////////////
@interface _HYDiskCacheItem : NSObject // not thread-safe
{
    @package
    NSString *key;
    NSData *value; //tmp may be nil
    NSUInteger byteCost;
    NSDate *inCacheDate;
    NSDate *lastAccessDate;
    NSString *fileName;
    
    __unsafe_unretained _HYDiskCacheItem *preItem;
    __unsafe_unretained _HYDiskCacheItem *nextItem;
}

- (NSComparisonResult)compare:(_HYDiskCacheItem *)cacheItem;

@end

@implementation _HYDiskCacheItem

- (NSComparisonResult)compare:(_HYDiskCacheItem *)cacheItem
{
    if (!cacheItem) return NSOrderedSame;
    NSTimeInterval me = [lastAccessDate timeIntervalSince1970];
    NSTimeInterval you = [cacheItem->lastAccessDate timeIntervalSince1970];
    if (me < you)
    {
        return NSOrderedAscending;
    }
    else if (me > you)
    {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"key:%@ inCachedate:%@ lastAccessDate %@",key,inCacheDate, lastAccessDate];
}

@end

@interface _HYDiskCacheItemLinkMap : NSObject //not thread-safe
{
    @package
    __unsafe_unretained _HYDiskCacheItem *_head;
    __unsafe_unretained _HYDiskCacheItem *_tail;
    
    CFMutableDictionaryRef _itemsDic;
    NSUInteger _totalByteCost;
}

- (void)_insertItemAtHead:(_HYDiskCacheItem *)item;

- (void)_bringItemToHead:(_HYDiskCacheItem *)item;

- (void)_removeItem:(_HYDiskCacheItem *)item;

- (_HYDiskCacheItem *)_removeTailItem;

- (void)_removeAllItem;

@end

@implementation _HYDiskCacheItemLinkMap

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _itemsDic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0,&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        _totalByteCost = 0;
        _head = nil;
        _tail = nil;
        
        return self;
    }
    return nil;
}

- (void)_insertItemAtHead:(_HYDiskCacheItem *)item
{
    CFDictionarySetValue(_itemsDic, (__bridge const void *)item->key, (__bridge const void *)item);
    _totalByteCost = _totalByteCost + item->byteCost;
    if (_head)
    {
        _head->preItem = item;
        item->nextItem = _head;
        item->preItem = nil;
        _head = item;
    }
    else
    {
        _head = item;
        _tail = item;
        _head = _tail;
    }
}

- (void)_bringItemToHead:(_HYDiskCacheItem *)item
{
    if (_head == item) return;
    
    if (_tail == item)
    {
        _tail = item->preItem;
        _tail->nextItem = nil;
    }
    else
    {
        item->nextItem->preItem = item->preItem;
        item->preItem->nextItem = item->nextItem;
    }
    
    item->nextItem = _head;
    item->preItem = nil;
    _head->preItem = item;
    _head = item;
}

- (void)_removeItem:(_HYDiskCacheItem *)item
{
    if (item->nextItem)
        item->nextItem->preItem = item->preItem;
    if (item->preItem)
        item->preItem->nextItem = item->nextItem;
    
    if (_head == item)
        _head = item->preItem;
    if (_tail == item)
        _tail = item->preItem;
    
    CFDictionaryRemoveValue(_itemsDic, (__bridge const void *)item->key);
    _totalByteCost = _totalByteCost - item->byteCost;
}

- (_HYDiskCacheItem *)_removeTailItem
{
    _HYDiskCacheItem *item = _tail;
    if (_head == _tail)
    {
        _head = _tail = nil;
    }
    else
    {
        _tail = _tail->preItem;
        _tail->nextItem = nil;
    }
    
    CFDictionaryRemoveValue(_itemsDic, (__bridge const void *)_tail->key);
    _totalByteCost = _totalByteCost - _tail->byteCost;
    return item;
}

- (void)_removeAllItem
{
    _head = nil;
    _tail = nil;
    CFDictionaryRemoveAllValues(_itemsDic);
    _totalByteCost = 0;
}

@end

///////////////////////////////////////////////////////////////////////////////
#pragma mark HYDiskStorage
///////////////////////////////////////////////////////////////////////////////

@interface _HYDiskFileStorage : NSObject //not thread-safe
{
    @package
    //CFMutableDictionaryRef _itemsDic;
    _HYDiskCacheItemLinkMap *_lruMap;
    NSString *_dataPath;
    NSString *_trashPath;
}

- (instancetype)initWithPath:(NSString *)path
                   trashPath:(NSString *)trashPath NS_DESIGNATED_INITIALIZER;

- (BOOL)_saveCacheValue:(NSData *)value key:(NSString *)key;

- (NSData *)_cacheValueForKey:(NSString *)key;

- (BOOL)_removeValueForKey:(NSString *)key;
- (BOOL)_removeValueForKeys:(NSArray<NSString *> *)keys;
- (BOOL)_removeAllValues;

inline _HYDiskCacheItem *_p_itemForKey(NSString *key, _HYDiskCacheItemLinkMap *map);
inline void _p_removeItem(NSString *key, _HYDiskCacheItemLinkMap *map, _HYDiskCacheItem *item);

@end

@implementation _HYDiskFileStorage

- (void)dealloc
{
    
}

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"_HYDiskFileStorage Must Have A Path" reason:@"Call initWithPath: instead." userInfo:nil];
    return [self initWithPath:nil trashPath:nil];
}

- (instancetype)initWithPath:(NSString *)path trashPath:(NSString *)trashPath
{
    self = [super init];
    if (self)
    {
        _dataPath = path;
        _trashPath = trashPath;
        _lruMap = [_HYDiskCacheItemLinkMap new];
        [self _p_initializeFileCacheRecord];
        return self;
    }
    return nil;
}

- (BOOL)_saveCacheValue:(NSData *)value key:(NSString *)key
{
    if (key.length == 0)
        return NO;
    if (!value || ![value isKindOfClass:[NSData class]])
        return NO;
    
    BOOL alreadyHas = YES;
    _HYDiskCacheItem *item = CFDictionaryGetValue(_lruMap->_itemsDic, (__bridge const void*)key);
    if (!item)
    {
        alreadyHas = NO;
        item = [[_HYDiskCacheItem alloc] init];
    }
    
    item->key = key;
    item->fileName = [self _p_fileNameForKey:item->key];
    item->byteCost = value.length;
    item->inCacheDate = [NSDate date];
    item->lastAccessDate = [NSDate distantFuture];//暂无访问
    item->fileName = [self _p_fileNameForKey:item->key];
    
    BOOL writeResult = [self _p_fileWriteWithName:item->fileName data:value];
    BOOL setTimeResult = [self _p_setFileAccessDate:item->lastAccessDate forFileName:item->fileName];
    if (!setTimeResult)//访问时间插入失败，删除刚刚写入的文件
    {
        [self _p_fileDeleteWithName:item->fileName];
    }
    else
    {
        if (!alreadyHas)
            [_lruMap _insertItemAtHead:item];
        else
            [_lruMap _bringItemToHead:item];
    }
    
    return writeResult && setTimeResult;
}

- (NSData *)_cacheValueForKey:(NSString *)key
{
    if (key.length == 0 || ![key isKindOfClass:[NSString class]])
        return nil;
    _HYDiskCacheItem *item = _p_itemForKey(key, _lruMap);
    if (!item)
        return nil;
    NSData *data = [self _p_fileReadWithName:item->fileName];
    if (data)
    {
        [self _p_setFileAccessDate:[NSDate date] forFileName:item->fileName];
        item->lastAccessDate = [NSDate date];
        [_lruMap _bringItemToHead:item];
        return data;
    }
    return nil;
}

- (BOOL)_removeValueForKey:(NSString *)key
{
    if (key.length == 0 || ![key isKindOfClass:[NSString class]])
        return nil;
    
    _HYDiskCacheItem *item = _p_itemForKey(key, _lruMap);
    if (!item)
        return nil;
    
    _p_removeItem(key, _lruMap, item);
    return [self _p_fileDeleteWithName:item->fileName];
}

- (BOOL)_removeValueForKeys:(NSArray<NSString *> *)keys
{
    if (keys.count == 0) return NO;
    
    for (NSString *key in keys)
    {
        [self _removeValueForKey:key];
    }
    
    return YES;
}

- (BOOL)_removeAllValues
{
    if ([self _p_fileMoveAllToTrash])
    {
        [_lruMap _removeAllItem];
        [self _p_removeAllTrashFileInBackground];
        return YES;
    }
    return NO;
}
//初始化
- (void)_p_initializeFileCacheRecord
{
    NSArray *urlkeys = @[ NSURLContentModificationDateKey,
                       NSURLTotalFileAllocatedSizeKey,
                       NSURLCreationDateKey];
    
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:_dataPath]
                                                   includingPropertiesForKeys:urlkeys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:&error];
    if(error)
        NSLog(@"%@", error);
    else
    {
        CFMutableDictionaryRef items =  CFDictionaryCreateMutable(CFAllocatorGetDefault(), [files count],&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        for (NSURL *fileURL in files)
        {
            _HYDiskCacheItem *item = [[_HYDiskCacheItem alloc] init];
            
            //key
            NSString *key = [self _p_keyForEncodedFilePath:[fileURL absoluteString]];
            item->key = key;
            item->fileName = [fileURL lastPathComponent];
            
            error = nil;
            NSDictionary *dictionary = [fileURL resourceValuesForKeys:urlkeys error:&error];
            if(error) NSLog(@"%@", error);
            
            //进入缓存的时间
            NSDate *creationDate = [dictionary objectForKey:NSURLCreationDateKey];
            if (creationDate) item->inCacheDate = creationDate;
            
            //最后访问时间
            NSDate *lastAccessDate = [dictionary objectForKey:NSURLContentModificationDateKey];
            if (lastAccessDate)
                item->lastAccessDate = lastAccessDate;
            else
                item->lastAccessDate = creationDate;
            
            //cost
            NSNumber *fileSize = [dictionary objectForKey:NSURLTotalFileAllocatedSizeKey];
            if (fileSize) item->byteCost = [fileSize unsignedIntegerValue];
            
            CFDictionarySetValue(items, (__bridge const void*)key, (__bridge const void*)item);
        }
        
        NSMutableDictionary *dic = (__bridge NSMutableDictionary *)items;
        NSArray *keys = [dic keysSortedByValueUsingSelector:@selector(compare:)];
        for (NSString *key in keys)
        {
            _HYDiskCacheItem *item = CFDictionaryGetValue(items, (__bridge const void *)key);
            if (item)
                [_lruMap _insertItemAtHead:item];
        }
        CFRelease(items);
        items = nil;
    }
}

// file url 转 key
- (NSString *)_p_keyForEncodedFilePath:(NSString *)url
{
    NSString *fileName = [url lastPathComponent];
    if (!fileName) return nil;
    return [self _p_keyForFileName:fileName];
}

- (NSString *)_p_keyForFileName:(NSString *)string
{
    if (![string length]) return @"";
    return [string stringByRemovingPercentEncoding];
}

//key 转 file url
- (NSString *)_p_fileNameForKey:(NSString *)key
{
    if (![key length]) return @"";
    return [key stringByAddingPercentEncodingWithAllowedCharacters:[[NSCharacterSet characterSetWithCharactersInString:@".:/%"] invertedSet]];
}

- (BOOL)_p_setFileAccessDate:(NSDate *)date forFileName:(NSString *)fileName
{
    if (!date || !fileName) return NO;
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: date}
                                                    ofItemAtPath: [_dataPath stringByAppendingPathComponent:fileName]
                                                           error:&error];
    if(error) NSLog(@"%@", error);
    return success;
}

_HYDiskCacheItem * _p_itemForKey(NSString *key, _HYDiskCacheItemLinkMap *map)
{
    if (key)
        return CFDictionaryGetValue(map->_itemsDic, (__bridge const void*)key);
    return nil;
}

void _p_removeItem(NSString *key, _HYDiskCacheItemLinkMap *map, _HYDiskCacheItem *item)
{
    if (item && map && key)
        [map _removeItem:item];
}

- (BOOL)_p_fileWriteWithName:(NSString *)fileName data:(NSData *)data
{
    NSString *path = [_dataPath stringByAppendingPathComponent:fileName];
    return [data writeToFile:path atomically:NO];
}

- (NSData *)_p_fileReadWithName:(NSString *)fileName
{
    NSString *path = [_dataPath stringByAppendingPathComponent:fileName];
    return [NSData dataWithContentsOfFile:path];
}

- (BOOL)_p_fileDeleteWithName:(NSString *)fileName
{
    NSString *path = [_dataPath stringByAppendingPathComponent:fileName];
    return [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (BOOL)_p_fileMoveAllToTrash
{
    CFUUIDRef uuidRef = CFUUIDCreate(NULL);
    CFStringRef uuid = CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    
    NSString *tmpPath = [_trashPath stringByAppendingPathComponent:(__bridge NSString *)(uuid)];
    BOOL suc = [[NSFileManager defaultManager] moveItemAtPath:_dataPath toPath:tmpPath error:nil];
    if (suc)
        suc = [[NSFileManager defaultManager] createDirectoryAtPath:_dataPath withIntermediateDirectories:YES attributes:nil error:NULL];
    CFRelease(uuid);
    return suc;
}

- (void)_p_removeAllTrashFileInBackground
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *manager = [NSFileManager defaultManager];
        NSArray *directoryContents = [manager contentsOfDirectoryAtPath:_trashPath error:NULL];
        for (NSString *path in directoryContents)
        {
            NSString *fullPath = [_trashPath stringByAppendingPathComponent:path];
            [manager removeItemAtPath:fullPath error:NULL];
        }
    });
}

@end


///////////////////////////////////////////////////////////////////////////////
#pragma mark HYDiskCache
///////////////////////////////////////////////////////////////////////////////

@interface HYDiskCache () // yeah all method & proterty thread-safe
{
    dispatch_queue_t _dataQueue;
    _HYDiskFileStorage *_storage;
}

@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *directoryPath;
@property (nonatomic, copy, readwrite) NSString *cachePath;
@property (nonatomic, copy, readwrite) NSString *cacheDataPath;
@property (nonatomic, copy, readwrite) NSString *cacheTrushPath;

@end

@implementation HYDiskCache

@synthesize byteCostLimit = _byteCostLimit;
@synthesize totalByteCostNow = _totalByteCostNow;
@synthesize maxAge = _maxAge;
@synthesize trimToMaxAgeInterval = _trimToMaxAgeInterval;
@synthesize customArchiveBlock = _customArchiveBlock;
@synthesize customUnarchiveBlock = _customUnarchiveBlock;
@synthesize customMaxAge = _customMaxAge;

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"HYDiskCache Must Have A Name" reason:@"Call initWithName: instead." userInfo:nil];
    
    return [self initWithName:@"" andDirectoryPath:@""];
}

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name andDirectoryPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0]];
}

- (instancetype)initWithName:(NSString *)name
            andDirectoryPath:(NSString *)directoryPath
{
    if (!name || name.length == 0 || !directoryPath || directoryPath.length == 0 ||
        ![name isKindOfClass:[NSString class]] || ![directoryPath isKindOfClass:[NSString class]])
    {
        @throw [NSException exceptionWithName:@"HYDiskCache Must Have A Name" reason:@"The Name and DirectoryPath Could Not Be NIL Or Empty" userInfo:nil];
        return nil;
    }
    
    self = [super init];
    if (self)
    {
        _name = [name copy];
        _directoryPath = [directoryPath copy];
        
        _byteCostLimit = 0;
        _totalByteCostNow = 0;
        _maxAge = 0.0f;
        _trimToMaxAgeInterval = 0.0f;
        
        semaphoreLock = dispatch_semaphore_create(1);
        _dataQueue = dispatch_queue_create([dataQueueNamePrefix UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        //创建路径
        if (![self p_createPath])
        {
            NSLog(@"HYDiskCache Create Path Failed");
            return nil;
        }
        
        //由于加了锁，所以不影响初始化后对cache的存储操作
        lock();
        dispatch_async(_dataQueue, ^{
           
            _storage = [[_HYDiskFileStorage alloc] initWithPath:_cacheDataPath trashPath:_cacheTrushPath];
            unLock();
        });
        
        lock();
        _HYDiskFileStorage *storage = _storage;
        unLock();
        
        if(!storage) return nil;
        
        return self;
    }
    return nil;
}

#pragma mark private method

- (BOOL)p_createPath
{
    _cachePath = [[_directoryPath stringByAppendingPathComponent:_name] copy];
    _cacheDataPath = [[_cachePath stringByAppendingPathComponent:dataPath] copy];
    _cacheTrushPath = [[_cachePath stringByAppendingPathComponent:trushPath] copy];
    
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_cacheDataPath
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil] ||
        ![[NSFileManager defaultManager] createDirectoryAtPath:_cacheTrushPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil])
    {
        return NO;
    }
    return YES;
}

#pragma mark store object

- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key
        withBlock:(__nullable HYDiskCacheObjectBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
       
        __strong HYDiskCache *stronglySelf = weakSelf;
        [stronglySelf setObject:object forKey:key];
        
        if (block)
        {
            block(stronglySelf, key, object);
        }
    });
}

- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key
{
    if (!object || !key || ![key isKindOfClass:[NSString class]] || key.length == 0)
        return;
    
    _HYCacheBackgourndTask *task = [_HYCacheBackgourndTask _startBackgroundTask];
    
    NSData *data;
    if (self.customArchiveBlock)
        data = self.customArchiveBlock(object);
    else
        data = [NSKeyedArchiver archivedDataWithRootObject:object];
    
    lock();
    [_storage _saveCacheValue:data key:key];
    unLock();
    
    [task _endTask];
}

- (void)objectForKey:(id)key
           withBlock:(HYDiskCacheObjectBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
        NSObject *object = [stronglySelf objectForKey:key];
        if (block)
        {
            block(stronglySelf, key, object);
        }
    });
}

- (id __nullable )objectForKey:(NSString *)key
{
    if (key.length == 0 || ![key isKindOfClass:[NSString class]])
        return nil;
    NSData *data;
    lock();
    data = [_storage _cacheValueForKey:key];
    unLock();
    
    id object;
    if (self.customUnarchiveBlock)
        object = self.customUnarchiveBlock(data);
    else
        object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    
    return object;
}

- (void)removeObjectForKey:(NSString *)key
                 withBlock:(__nullable HYDiskCacheBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
        [self removeObjectForKey:key];
        if (block)
        {
            block(stronglySelf);
        }
    });
}

- (void)removeObjectForKey:(NSString *)key
{
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return;
    
    lock();
    [_storage _removeValueForKey:key];
    unLock();
}

- (void)removeObjectForKeys:(NSArray<NSString *> *)keys
                  withBlock:(__nullable HYDiskCacheBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
        [self removeObjectForKeys:keys];
        if (block)
        {
            block(stronglySelf);
        }
    });
}

- (void)removeObjectForKeys:(NSArray<NSString *> *)keys
{
    if(![keys isKindOfClass:[NSArray class]] || keys.count == 0) return;
    
    lock();
    [_storage _removeValueForKeys:keys];
    unLock();
}

- (void)removeAllObjectWithBlock:(__nullable HYDiskCacheBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
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
    [_storage _removeAllValues];
    unLock();
}

- (void)containsObjectForKey:(id)key
                       block:(nullable HYDiskCacheObjectBlock)block
{
    if (!key) return ;
    [self objectForKey:key withBlock:block];
}

- (void)trimToCost:(NSUInteger)cost
             block:(nullable HYDiskCacheBlock)block;
{
    if (cost == 0)
    {
        [self removeAllObjectWithBlock:block];
    }
    else if (cost < self.totalByteCostNow)
    {
        __weak HYDiskCache *weakSelf = self;
        dispatch_async(_dataQueue, ^{
           
            __strong HYDiskCache *stronglySelf = weakSelf;
            lock();
            //do not use self.totalByteCostNow  avoid deadlock
            while (cost <= _storage->_lruMap->_totalByteCost)
            {
                _HYDiskCacheItem *item = _storage->_lruMap->_tail;
                if (item)
                {
                    [_storage _removeValueForKey:item->key];
                }
            }
            unLock();
            
            if (block)
                block(stronglySelf);
        });
    }
    return;
}

- (void)trimToCostLimitWithBlock:(nullable HYDiskCacheBlock)block
{
    [self trimToCost:self.byteCostLimit block:block];
}

#pragma mark getter setter for thread-safe

- (NSUInteger)totalByteCostNow
{
    lock();
    NSUInteger cost = _storage->_lruMap->_totalByteCost;
    unLock();
    return cost;
}

- (NSUInteger)byteCostLimit
{
    lock();
    NSUInteger cost = _byteCostLimit;
    unLock();
    
    return cost;
}

- (void)setByteCostLimit:(NSUInteger)byteCostLimit
{
    lock();
    _byteCostLimit = byteCostLimit;
    unLock();
}

- (NSTimeInterval)maxAge
{
    lock();
    NSTimeInterval age = _maxAge;
    unLock();
    return age;
}

- (void)setMaxAge:(NSTimeInterval)maxAge
{
    lock();
    _maxAge = maxAge;
    unLock();
}

- (void)setTrimToMaxAgeInterval:(NSTimeInterval)trimToMaxAgeInterval
{
    lock();
    _trimToMaxAgeInterval = trimToMaxAgeInterval;
    unLock();
}

- (NSTimeInterval)trimToMaxAgeInterval
{
    lock();
    NSTimeInterval age = _trimToMaxAgeInterval;
    unLock();
    
    return age;
}

- (void)setCustomArchiveBlock:(NSData * _Nonnull (^)(id _Nonnull))customArchiveBlock
{
    lock();
    _customArchiveBlock = [customArchiveBlock copy];
    unLock();
}

- (NSData * _Nonnull(^)(id _Nonnull))customArchiveBlock
{
    lock();
    NSData *(^block)(id)  = _customArchiveBlock;
    unLock();
    return block;
}

- (void)setCustomUnarchiveBlock:(id  _Nonnull (^)(NSData * _Nonnull))customUnarchiveBlock
{
    lock();
    _customUnarchiveBlock = [customUnarchiveBlock copy];
    unLock();
}

- (id (^)(NSData *))customUnarchiveBlock
{
    lock();
    id (^block)(NSData *) = _customUnarchiveBlock;
    unLock();
    return block;
}

- (void)setCustomMaxAge:(NSTimeInterval (^)(id _Nonnull))customMaxAge
{
    lock();
    _customMaxAge = [customMaxAge copy];
    unLock();
}

- (NSTimeInterval (^)(id))customMaxAge
{
    lock();
    NSTimeInterval (^block)(id) = _customMaxAge;
    unLock();
    return block;
}

@end










//
//  HYDiskCache.m
//  Pods
//
//  Created by fangyuxi on 16/4/5.
//
//

#import "HYDiskCache.h"

static NSString *const dataQueueNamePrefix = @"com.HYDiskCache.ConcurrentQueue.";
static NSString *const trushQueueNamePrefix = @"com.HYDiskCache.TrushQueue.";

static NSString *const dataPath = @"data";
static NSString *const trushPath = @"trush";

dispatch_semaphore_t semaphoreLock;

#pragma mark lock

static inline void lock()
{
    dispatch_semaphore_wait(semaphoreLock, DISPATCH_TIME_FOREVER);
}

static inline void unLock()
{
    dispatch_semaphore_signal(semaphoreLock);
}

///////////////////////////////////////////////////////////////////////////////
#pragma mark HYDiskCacheItem
///////////////////////////////////////////////////////////////////////////////
@interface _HYDiskCacheItem : NSObject
{
    @package
    NSString *key;
    NSData *object; //tmp may be nil
    NSUInteger byteCost;
    NSDate *inCacheDate;
    NSDate *lastAccessDate;
    NSString *fileName;
}

@end

@implementation _HYDiskCacheItem

@end

///////////////////////////////////////////////////////////////////////////////
#pragma mark HYDiskStorage
///////////////////////////////////////////////////////////////////////////////

@interface _HYDiskFileStorage : NSObject
{
    @package
    CFMutableDictionaryRef _itemsDic;
    NSURL *_path;
}

- (BOOL)_saveItem:(_HYDiskCacheItem *)item;
- (BOOL)_saveObject:(NSData *)object key:(NSString *)key;
- (BOOL)_removeItemForKey:(NSString *)key;
- (BOOL)_removeItemForKeys:(NSArray<NSString *> *)keys;
- (BOOL)_removeAllObjects;

- (instancetype)initWithPath:(NSURL *)path NS_DESIGNATED_INITIALIZER;

@end

@implementation _HYDiskFileStorage

- (void)dealloc
{
    CFRelease(_itemsDic);
}

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"_HYDiskFileStorage Must Have A Path" reason:@"Call initWithPath: instead." userInfo:nil];
    return [self initWithPath:nil];
}

- (instancetype)initWithPath:(NSURL *)path
{
    self = [super init];
    if (self)
    {
        _path = path;
        _itemsDic = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0,&kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        [self _p_initializeFileCacheRecord];
        return self;
    }
    return nil;
}

- (BOOL)_saveItem:(_HYDiskCacheItem *)item
{
    if (!item || ![item isKindOfClass:[_HYDiskCacheItem class]]) return NO;
    if (item->object.length == 0) return NO;
    if (item->key.length == 0) return NO;
    
    if (item->fileName.length == 0)
        item->fileName = [self _p_fileNameForKey:item->key];
    if (item->byteCost == 0)
        item->byteCost = item->object.length;

    item->inCacheDate = [NSDate date];
    item->lastAccessDate = [NSDate distantFuture];//暂无访问
    
    CFDictionarySetValue(_itemsDic, (__bridge const void*)item->key, (__bridge const void*)item);
    BOOL result = [self _p_fileWriteWithName:item->fileName data:item->object];
    [self _p_setFileAccessDate:item->lastAccessDate forFileName:item->fileName];
    return result;
}
- (BOOL)_saveObject:(NSData *)object key:(NSString *)key
{
    if (key.length == 0) return NO;
    if (!object || ![object isKindOfClass:[NSData class]]) return NO;
    
    
    BOOL alreadyHas = YES;
    _HYDiskCacheItem *item = CFDictionaryGetValue(_itemsDic, (__bridge const void*)key);
    if (!item)
    {
        alreadyHas = NO;
        item = [[_HYDiskCacheItem alloc] init];
    }
    
    item->key = key;
    item->fileName = [self _p_fileNameForKey:item->key];
    item->byteCost = object.length;
    item->inCacheDate = [NSDate date];
    item->lastAccessDate = [NSDate distantFuture];//暂无访问
    item->fileName = [self _p_fileNameForKey:item->key];
    
    if (!alreadyHas)
        CFDictionarySetValue(_itemsDic, (__bridge const void*)item->key, (__bridge const void*)item);
    BOOL result = [self _p_fileWriteWithName:item->fileName data:object];
    [self _p_setFileAccessDate:item->lastAccessDate forFileName:item->fileName];
    return result;
}
- (BOOL)_removeItemForKey:(NSString *)key
{
    return NO;
}
- (BOOL)_removeItemForKeys:(NSArray<NSString *> *)keys
{
    return NO;
}
- (BOOL)_removeAllObjects
{
    return NO;
}

- (void)_p_initializeFileCacheRecord
{
    NSArray *keys = @[ NSURLContentModificationDateKey,
                       NSURLTotalFileAllocatedSizeKey,
                       NSURLCreationDateKey];
    
    NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_path
                                                   includingPropertiesForKeys:keys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:&error];
    if(error) NSLog(@"%@", error);
    for (NSURL *fileURL in files)
    {
        _HYDiskCacheItem *item = [[_HYDiskCacheItem alloc] init];
        
        //key
        NSString *key = [self _p_keyForEncodedFileURL:fileURL];
        item->key = key;
        item->fileName = [fileURL lastPathComponent];
        
        error = nil;
        NSDictionary *dictionary = [fileURL resourceValuesForKeys:keys error:&error];
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
        
        CFDictionarySetValue(_itemsDic, (__bridge const void*)key, (__bridge const void*)item);
    }
}

#pragma mark key filename transform

- (NSString *)_p_keyForEncodedFileURL:(NSURL *)url
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

- (NSURL *)fileURLForKey:(NSString *)key
{
    if (!key)return nil;
    return [_path URLByAppendingPathComponent:[self _p_fileNameForKey:key]];
}

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
                                                    ofItemAtPath: [[_path URLByAppendingPathComponent:fileName] absoluteString]
                                                           error:&error];
    return success;
}

#pragma mark file action

- (BOOL)_p_fileWriteWithName:(NSString *)filename data:(NSData *)data
{
    NSURL *path = [_path URLByAppendingPathComponent:filename];
    return [data writeToURL:path atomically:NO];
}

- (NSData *)_p_fileReadWithName:(NSString *)filename
{
    NSURL *path = [_path URLByAppendingPathComponent:filename];
    return [NSData dataWithContentsOfURL:path];
}

- (BOOL)_p_fileDeleteWithName:(NSString *)filename
{
    NSURL *path = [_path URLByAppendingPathComponent:filename];
    return [[NSFileManager defaultManager] removeItemAtURL:path error:NULL];
}

@end


///////////////////////////////////////////////////////////////////////////////
#pragma mark HYDiskCache
///////////////////////////////////////////////////////////////////////////////

@interface HYDiskCache ()
{
    dispatch_queue_t _dataQueue;
    dispatch_queue_t _trushQueue;
    
    _HYDiskFileStorage *_storage;
}

@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *directoryPath;
@property (nonatomic, copy, readwrite) NSURL *cachePath;
@property (nonatomic, copy, readwrite) NSURL *cacheDataPath;
@property (nonatomic, copy, readwrite) NSURL *cacheTrushPath;
@end

@implementation HYDiskCache

@synthesize byteCostLimit = _byteCostLimit;
@synthesize totalByteCostNow = _totalByteCostNow;
@synthesize maxAge = _maxAge;

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
        _trushQueue = dispatch_queue_create([dataQueueNamePrefix UTF8String], DISPATCH_QUEUE_SERIAL);
        
        //创建路径
        if (![self p_createPath])
        {
            NSLog(@"HYDiskCache Create Path Failed");
            return nil;
        }
        
        //由于加了锁，所以不影响初始化后对cache的存储操作
        lock();
        dispatch_async(_dataQueue, ^{
           
            _storage = [[_HYDiskFileStorage alloc] initWithPath:_cacheDataPath];
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
    _cachePath = [[NSURL fileURLWithPathComponents:@[_directoryPath, _name]] copy];
    _cacheDataPath = [[NSURL fileURLWithPathComponents:@[_directoryPath, _name, dataPath]] copy];
    _cacheTrushPath = [[NSURL fileURLWithPathComponents:@[_directoryPath, _name, dataPath]] copy];
    
    if (![[NSFileManager defaultManager] createDirectoryAtURL:_cachePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil] ||
        
        ![[NSFileManager defaultManager] createDirectoryAtURL:_cacheDataPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil] ||
        ![[NSFileManager defaultManager] createDirectoryAtURL:_cacheTrushPath
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
    if (!object || key.length == 0) return;
    
    NSData *data;
    if (self.customArchiveBlock)
        data = self.customArchiveBlock(object);
    else
        data = [NSKeyedArchiver archivedDataWithRootObject:object];
    
    lock();
    [_storage _saveObject:data key:key];
    unLock();
}

@end

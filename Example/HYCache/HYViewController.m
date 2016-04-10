//
//  HYViewController.m
//  HYCache
//
//  Created by fangyuxi on 04/05/2016.
//  Copyright (c) 2016 fangyuxi. All rights reserved.
//

#import "HYViewController.h"
#import "HYMemoryCache.h"
#import "HYDiskCache.h"
#import "PINDiskCache.h"

@interface HYViewController ()
{
    HYMemoryCache *_memcache;
    HYDiskCache *_diskCache;
    PINDiskCache *_pinCache;
    
    NSMutableArray *_keys;
    NSMutableArray *_values;
    dispatch_queue_t queue;
}

@end

@implementation HYViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    
    queue = dispatch_queue_create([@"test queue" UTF8String], DISPATCH_QUEUE_CONCURRENT);
    
    _memcache = [[HYMemoryCache alloc] initWithName:@"fangyuxi"];
    _memcache.maxAge = 5.0f;
    _memcache.trimToMaxAgeInterval = 10.0f;
    
    _diskCache = [[HYDiskCache alloc] initWithName:@"fangyuxi"];
    _pinCache = [[PINDiskCache alloc] initWithName:@"yangqian"];
    
    _keys = [NSMutableArray array];
    _values = [NSMutableArray array];
    
    for (NSInteger index = 0; index < 1000; ++index)
    {
        [_keys addObject:[NSString stringWithFormat:@"%ld", (long)index]];
        [_values addObject:[NSNumber numberWithInt:index]];
    }
    
    //[_diskCache objectForKey:@"10"];
    [self testDiskSet];
    //[self testRemoveDisk];
    [self testDiskRead];
    //[self testDiskSet];
    //[self testDiskRemove];
    //[self testTrimCost];
    [self testTrimDiskCost];
}

- (void)testDiskSet
{
    dispatch_queue_t queue1 = dispatch_queue_create("f", DISPATCH_QUEUE_CONCURRENT);
    dispatch_queue_t queue2 = dispatch_queue_create("1", DISPATCH_QUEUE_CONCURRENT);
    
    CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger index = 0; index < 1000; ++index)
    {
        [_diskCache setObject:[_values objectAtIndex:index] forKey:[_keys objectAtIndex:index]];
    }
    
    CFTimeInterval finish = CACurrentMediaTime();
    
    CFTimeInterval f = finish - start;
    printf("set disk:   %8.2f\n", f * 1000);
}

- (void)testDiskRead
{
    dispatch_queue_t queue1 = dispatch_queue_create("f", NULL);
    dispatch_queue_t queue2 = dispatch_queue_create("1", NULL);
    
    CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger index = 0; index < 1000; ++index)
    {
        [_diskCache objectForKey:[_keys objectAtIndex:index]];
    }
    
    CFTimeInterval finish = CACurrentMediaTime();
    
    CFTimeInterval f = finish - start;
    printf("read disk:   %8.2f\n", f * 1000);
}

- (void)testDiskRemove
{
    CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger index = 0; index < 500; ++index)
    {
        [_diskCache removeAllObject];
    }
    CFTimeInterval finish = CACurrentMediaTime();
    
    CFTimeInterval f = finish - start;
    printf("read disk:   %8.2f\n", f * 1000);
}

- (void)testTrimDiskCost
{
    CFTimeInterval start = CACurrentMediaTime();
    [_diskCache trimToCost:500 block:^(HYDiskCache * _Nonnull cache) {
        
    }];
    CFTimeInterval finish = CACurrentMediaTime();
    
    CFTimeInterval f = finish - start;
    printf("trim disk:   %8.2f\n", f * 1000);
}
- (void)testMemSet
{
    CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger index = 0; index < 200000; ++index)
    {
        [_memcache setObject:[_values objectAtIndex:index] forKey:[_keys objectAtIndex:index] withCost:index];
    }
    CFTimeInterval finish = CACurrentMediaTime();
    
    CFTimeInterval f = finish - start;
    printf("set:   %8.2f\n", f * 1000);
}

- (void)testRead
{
    
}

- (void)testRemove
{
    dispatch_queue_t queue1 = dispatch_queue_create("f", NULL);
    dispatch_queue_t queue2 = dispatch_queue_create("1", NULL);
    
    CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger index = 0; index < 500; ++index)
    {
        dispatch_async(queue1, ^{
            
            [_diskCache removeObjectForKey:[_keys objectAtIndex:index]];
        });
    }
    
    for (NSInteger index = 500; index < 1000; ++index)
    {
        dispatch_async(queue2, ^{
            
            [_diskCache removeObjectForKey:[_keys objectAtIndex:index]];
        });
    }
    CFTimeInterval finish = CACurrentMediaTime();
    
    CFTimeInterval f = finish - start;
    printf("read disk:   %8.2f\n", f * 1000);

}

- (void)testTrimMemCost
{

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

@end

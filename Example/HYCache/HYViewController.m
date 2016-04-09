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
        [_keys addObject:[NSString stringWithFormat:@"%d", index]];
        //[_values addObject:[NSNumber numberWithInt:100]];
    }
    
    //[self testDiskSet];
    [self testReadDisk];
    
    //[self testRemove];
    //[self testTrimCost];
}

- (void)testDiskSet
{
    CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger index = 0; index < 1000; ++index)
    {
        [_diskCache setObject:[_values objectAtIndex:index] forKey:[_keys objectAtIndex:index]];
    }
    CFTimeInterval finish = CACurrentMediaTime();
    
    CFTimeInterval f = finish - start;
    printf("set disk:   %8.2f\n", f * 1000);
}

- (void)testReadDisk
{
     CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger index = 0; index < 1000; ++index)
    {
//        dispatch_async(queue, ^{
//
//            [_diskCache objectForKey:[_keys objectAtIndex:index] withBlock:^(HYDiskCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
//                
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    
//                    NSLog(@"Finish %@", object);
//                });
//            }];
//        });
        [_diskCache objectForKey:[_keys objectAtIndex:index]];
    }
    CFTimeInterval finish = CACurrentMediaTime();
    
    CFTimeInterval f = finish - start;
    printf("read disk:   %8.2f\n", f * 1000);
}

- (void)testMemSet
{
    CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger index = 0; index < 200000; ++index)
    {
        //        dispatch_async(queue, ^{
        //
        //            [cache setObject:[values objectAtIndex:index] forKey:[keys objectAtIndex:index] withBlock:^(HYMemoryCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
        //
        //                dispatch_async(dispatch_get_main_queue(), ^{
        //
        //                    NSLog(@"Finish %@", object);
        //                });
        //
        //            }];
        //        });
        
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
    for (NSInteger index = 0; index < 100; ++index)
    {
//                [_cache removeObjectForKey:[_keys objectAtIndex:index] withBlock:^(HYMemoryCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
//                    dispatch_async(dispatch_get_main_queue(), ^{
//                        
//                        NSLog(@"Finish %@", object);
//                    });
//                }];
    }

//    CFTimeInterval start = CACurrentMediaTime();
//    [_cache removeAllObjectWithBlock:^(HYMemoryCache * _Nonnull cache) {
//       
//        dispatch_async(dispatch_get_main_queue(), ^{
//            
//            CFTimeInterval finish = CACurrentMediaTime();
//            
//            CFTimeInterval f = finish - start;
//            printf("remove:   %8.2f\n", f * 1000);
//        });
//    }];
}

- (void)testTrimCost
{
//    [_cache trimToCost:1000 block:^(HYMemoryCache * _Nonnull cache) {
//       
//        
//    }];
//    
//    [_cache trimToCost:500 block:^(HYMemoryCache * _Nonnull cache) {
//        
//        
//    }];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

@end

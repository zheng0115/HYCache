//
//  HYAppDelegate.m
//  HYCache
//
//  Created by fangyuxi on 04/05/2016.
//  Copyright (c) 2016 fangyuxi. All rights reserved.
//

#import "HYAppDelegate.h"
#import "HYMemoryCache.h"

@implementation HYAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    
    dispatch_queue_t queue = dispatch_queue_create([@"test queue" UTF8String], DISPATCH_QUEUE_CONCURRENT);
    
    HYMemoryCache *cache = [HYMemoryCache sharedCache];
    
    NSMutableArray *keys = [NSMutableArray array];
    NSMutableArray *values = [NSMutableArray array];
    
    for (NSInteger index = 0; index < 10000; ++index)
    {
        [keys addObject:@(index)];
        [values addObject:@(index)];
    }
    
    for (NSInteger index = 0; index < 10000; ++index)
    {
        dispatch_async(queue, ^{
        
            [cache setObject:[values objectAtIndex:index] forKey:[keys objectAtIndex:index] withBlock:^(HYMemoryCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    NSLog(@"Finish %@", object);
                });

            }];
        });
        
    }
    
    dispatch_queue_t queue1 = dispatch_queue_create([@"test queue" UTF8String], DISPATCH_QUEUE_CONCURRENT);
    
    for (NSInteger index = 0; index < 10000; ++index)
    {
        dispatch_async(queue1, ^{
            
            [cache objectForKey:[keys objectAtIndex:index] withBlock:^(HYMemoryCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    
                    NSLog(@"%@", object);
                });
            }];
        });
    }
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end

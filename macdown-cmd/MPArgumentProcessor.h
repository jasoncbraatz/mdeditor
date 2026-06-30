//
//  MPArgumentProcessor.h
//  MacDown
//
//  Created by Tzu-ping Chung on 02/12.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MPArgumentProcessor : NSObject

- (instancetype)init;

@property (nonatomic, assign, readonly) BOOL printsHelp;
@property (nonatomic, assign, readonly) BOOL printsVersion;
@property (nonatomic, strong, readonly) NSArray *arguments;

// Phase 3 read-back transport. When --control <url> is given, the CLI does NOT do the
// usual fire-and-forget launch; instead it sends that x-macdown:// URL to the running app
// as a GetURL AppleEvent, waits for the reply, and prints the JSON status to stdout.
// --bundle <id> overrides the target bundle id (default the release mdeditor), e.g. to
// drive the Debug build (com.jasoncbraatz.mdeditor-debug) in tests.
@property (nonatomic, strong, readonly) NSString *controlURL;
@property (nonatomic, strong, readonly) NSString *bundleID;

- (void)printHelp:(BOOL)shouldExit;
- (void)printVersion:(BOOL)shouldExit;

@end

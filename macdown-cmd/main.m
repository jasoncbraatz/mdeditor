//
//  main.m
//  macdown-cmd
//
//  Created by Esben Sorig on 30/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <sys/time.h>
#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>   // kInternetEventClass / kAEGetURL / keyDirectObject
#import <GBCli/GBCli.h>
#import "NSUserDefaults+Suite.h"
#import "MPGlobals.h"
#import "MPArgumentProcessor.h"


const NSUInteger kMPPathEncoding = NSUTF8StringEncoding;

// Default target for --control. NOTE: kMPApplicationBundleIdentifier in MPGlobals.h is
// still the stale upstream id (com.uranusjr.macdown — Phase 6 footgun), so the read-back
// transport hardcodes the real shipping id here instead of trusting that constant.
static NSString * const kMPControlDefaultBundleID = @"com.jasoncbraatz.mdeditor";


NSRunningApplication *MPRunningMacDownInstance()
{
    NSArray *runningInstances = [NSRunningApplication
        runningApplicationsWithBundleIdentifier:kMPApplicationSuiteName];
    return runningInstances.firstObject;
}

void MPCollectPipedContentURLForMacDown(NSURL *url) {
    NSUserDefaults *defaults =
        [[NSUserDefaults alloc] initWithSuiteNamed:kMPApplicationSuiteName];
    
    [defaults setObject:url.path forKey:kMPPipedContentFileToOpen inSuiteNamed:kMPApplicationSuiteName];
    [defaults synchronize];
}

void MPCollectForMacDown(NSOrderedSet<NSURL *> *urls)
{
    NSUserDefaults *defaults =
        [[NSUserDefaults alloc] initWithSuiteNamed:kMPApplicationSuiteName];
    NSMutableArray<NSString *> *urlStrings =
        [[NSMutableArray alloc] initWithCapacity:urls.count];
    for (NSURL *url in urls)
        [urlStrings addObject:url.path];
    [defaults setObject:urlStrings forKey:kMPFilesToOpenKey
           inSuiteNamed:kMPApplicationSuiteName];
    [defaults synchronize];
}

/**
 * Data piped to macdown through stdin.
 * 
 * @return Piped data if any, otherwise nil.
 */
NSData* MPPipedData() {
    NSFileHandle *stdInFileHandle = [NSFileHandle fileHandleWithStandardInput];
    // Check if stdin file handle have anything to read
    // Modified solution from http://stackoverflow.com/questions/7505777/how-do-i-check-for-nsfilehandle-has-data-available
    int fd = [stdInFileHandle fileDescriptor];
    fd_set fdset;
    struct timeval tmout = { 0, 0 };
    FD_ZERO(&fdset);
    FD_SET(fd, &fdset);
    if (select(fd + 1, &fdset, NULL, NULL, &tmout) <= 0) { // Doesn't hold any data
        return nil;
    }
    else if (FD_ISSET(fd, &fdset)) { // Holds data
        NSData *stdInData = [NSData dataWithData:[stdInFileHandle readDataToEndOfFile]];
        return stdInData;
    }
    else {
        return nil;
    }
}

/**
 * Read-back transport (Phase 3): send an x-macdown:// control URL to the running app as a
 * GetURL AppleEvent, WAIT for the reply, and print the handler's JSON status (carried in
 * keyDirectObject) to stdout. Returns 0 on a captured reply, 1 otherwise.
 *
 * Why a direct AppleEvent rather than `open`: LaunchServices' open is fire-and-forget — it
 * drops the AppleEvent reply, so the caller never sees the JSON. Sending GetURL ourselves
 * with kAEWaitReply lets us read keyDirectObject back. (Sending Apple events to another app
 * may require a one-time Automation/TCC grant; on denial macOS returns errAEEventNotPermitted
 * (-1743), which we surface as JSON rather than crashing.)
 */
int MPSendControlURL(NSString *urlString, NSString *bundleID)
{
    NSData *bundleData = [bundleID dataUsingEncoding:NSUTF8StringEncoding];
    NSAppleEventDescriptor *target =
        [NSAppleEventDescriptor descriptorWithDescriptorType:typeApplicationBundleID
                                                        data:bundleData];
    NSAppleEventDescriptor *event =
        [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass
                                                 eventID:kAEGetURL
                                        targetDescriptor:target
                                                returnID:kAutoGenerateReturnID
                                           transactionID:kAnyTransactionID];
    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:urlString]
                   forKeyword:keyDirectObject];

    NSError *sendError = nil;
    NSAppleEventDescriptor *reply =
        [event sendEventWithOptions:(NSAppleEventSendWaitForReply
                                     | NSAppleEventSendCanInteract)
                            timeout:15.0
                              error:&sendError];

    NSString *json = [[reply paramDescriptorForKeyword:keyDirectObject] stringValue];
    if (json.length)
    {
        printf("%s\n", json.UTF8String);
        return 0;
    }

    // No JSON reply — emit a structured error so the MCP/caller can parse a failure too.
    NSString *reason = sendError.localizedDescription ?: @"no reply from app";
    NSDictionary *err = @{@"ok": @NO,
                          @"error": reason,
                          @"bundle": (bundleID ?: @""),
                          @"sentURL": (urlString ?: @"")};
    NSData *data = [NSJSONSerialization dataWithJSONObject:err options:0 error:NULL];
    NSString *out = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                         : @"{\"ok\":false,\"error\":\"send failed\"}";
    printf("%s\n", out.UTF8String);
    return 1;
}


int main(int argc, const char * argv[])
{
    @autoreleasepool
    {
        MPArgumentProcessor *argproc = [[MPArgumentProcessor alloc] init];

        if (argproc.printsHelp)
            [argproc printHelp:YES];
        else if (argproc.printsVersion)
            [argproc printVersion:YES];

        // Read-back transport: --control short-circuits the usual fire-and-forget launch.
        if (argproc.controlURL.length)
        {
            NSString *bundleID = argproc.bundleID.length ? argproc.bundleID
                                                         : kMPControlDefaultBundleID;
            return MPSendControlURL(argproc.controlURL, bundleID);
        }

        NSData *dataFromPipe = MPPipedData();
        
        if (dataFromPipe) {
            // Store piped content in a temporary file which will be read by MacDown on launch
            NSString *fileName = [NSString stringWithFormat:@"%@_%@", [[NSProcessInfo processInfo] globallyUniqueString], @"pipedText.txt"];
            NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:fileName]];
            
            NSError *writeError;
            [dataFromPipe writeToFile:fileURL.path options:0 error:&writeError];
            
            if (writeError == nil) {
                MPCollectPipedContentURLForMacDown(fileURL);
            }
        }

        // Treat all arguments as file names to open. Convert them to absolute
        // paths and store them (as an array) in MacDown's user defaults to
        // be opened later.
        NSString *pwd = [NSFileManager defaultManager].currentDirectoryPath;
        NSURL *pwdUrl = [NSURL fileURLWithPath:pwd isDirectory:YES];
        NSMutableOrderedSet<NSURL *> *urls = [NSMutableOrderedSet orderedSet];
        for (NSString *arg in argproc.arguments)
        {
            NSString *escaped =
                [arg stringByAddingPercentEscapesUsingEncoding:kMPPathEncoding];
            NSURL *url = [NSURL URLWithString:escaped relativeToURL:pwdUrl];
            [urls addObject:url];
        }
        MPCollectForMacDown(urls);

        // Launch MacDown.
        [[NSWorkspace sharedWorkspace] launchAppWithBundleIdentifier:kMPApplicationBundleIdentifier options:NSWorkspaceLaunchDefault additionalEventParamDescriptor:nil launchIdentifier:nil];
    }
    return EXIT_SUCCESS;
}

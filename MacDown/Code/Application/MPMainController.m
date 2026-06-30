//
//  MPMainController.m
//  MacDown
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import "MPMainController.h"
#import <MASPreferences/MASPreferencesWindowController.h>
#import <Sparkle/SUUpdater.h>
#import "MPGlobals.h"
#import "MPUtilities.h"
#import "NSDocumentController+Document.h"
#import "NSUserDefaults+Suite.h"
#import "MPPreferences.h"
#import "MPGeneralPreferencesViewController.h"
#import "MPMarkdownPreferencesViewController.h"
#import "MPEditorPreferencesViewController.h"
#import "MPHtmlPreferencesViewController.h"
#import "MPTerminalPreferencesViewController.h"
#import "MPDocument.h"


static NSString * const kMPTreatLastSeenStampKey = @"treatLastSeenStamp";


NS_INLINE void MPOpenBundledFile(NSString *resource, NSString *extension)
{
    NSURL *source = [[NSBundle mainBundle] URLForResource:resource
                                            withExtension:extension];
    NSString *filename = source.absoluteString.lastPathComponent;
    NSURL *target = [NSURL fileURLWithPathComponents:@[NSTemporaryDirectory(),
                                                       filename]];
    BOOL ok = NO;
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:target error:NULL];
    ok = [manager copyItemAtURL:source toURL:target error:NULL];

    if (!ok)
        return;
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [c openDocumentWithContentsOfURL:target display:YES completionHandler:
     ^(NSDocument *document, BOOL wasOpen, NSError *error) {
         if (!document || wasOpen || error)
             return;
         NSRect frame = [NSScreen mainScreen].visibleFrame;
         for (NSWindowController *wc in document.windowControllers)
             [wc.window setFrame:frame display:YES];
     }];
}

NS_INLINE void treat()
{
    NSDictionary *info = MPGetDataMap(@"treats");
    NSString *name = info[@"name"];
    if (![NSUserName().lowercaseString hasPrefix:name]
            && ![NSFullUserName().lowercaseString hasPrefix:name])
        return;

    NSDictionary *data = info[@"data"];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSCalendarUnit unit =
        NSCalendarUnitDay | NSCalendarUnitMonth | NSCalendarUnitYear;
    NSDateComponents *comps = [calendar components:unit fromDate:[NSDate date]];

    NSString *key =
        [NSString stringWithFormat:@"%02ld%02ld", comps.month, comps.day];
    if (!data[key])     // No matching treat.
        return;

    NSString *stamp = [NSString stringWithFormat:@"%ld%02ld%02ld",
                       comps.year, comps.month, comps.day];

    // User has seen this treat today.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([[defaults objectForKey:kMPTreatLastSeenStampKey] isEqual:stamp])
        return;

    [defaults setObject:stamp forKey:kMPTreatLastSeenStampKey];
    NSArray *components = @[NSTemporaryDirectory(), key];
    NSURL *url = [NSURL fileURLWithPathComponents:components];
    [data[key] writeToURL:url atomically:NO];

    // Make sure this is opened last and immediately visible.
    NSDocumentController *c = [NSDocumentController sharedDocumentController];
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [c openDocumentWithContentsOfURL:url display:YES
                       completionHandler:MPDocumentOpenCompletionEmpty];
    }];
}


@interface MPMainController ()
@property (readonly) NSWindowController *preferencesWindowController;
@end


@implementation MPMainController

@synthesize preferencesWindowController = _preferencesWindowController;

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Using private API [WebCache setDisabled:YES] to disable WebView's cache
    id webCacheClass = (id)NSClassFromString(@"WebCache");
    if (webCacheClass) {
// Ignoring "undeclared selector" warning
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
        BOOL setDisabledValue = YES;
        NSMethodSignature *signature = [webCacheClass methodSignatureForSelector:@selector(setDisabled:)];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = @selector(setDisabled:);
        invocation.target = [webCacheClass class];
        [invocation setArgument:&setDisabledValue atIndex:2];
        [invocation invoke];
#pragma clang diagnostic pop
    }
    [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:self
            andSelector:@selector(openUrlSchemeAppleEvent:withReplyEvent:)
          forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

// x-macdown:// control surface (Phase 3 MCP transport). Two verbs today:
//   open:    x-macdown://open?url=file:///path/to/a/file
//   command: x-macdown://command?id=strong        (any +[MPDocument availableCommandIDs])
// Both route through the SAME registry the test harness drives (-[MPDocument
// invokeCommandID:sender:error:]) — one behaviour path, not two. Inputs are
// allowlist-validated (see +validatedCommandID:/+validatedFileURLFromParam:) so the
// scheme can't be turned into a fetch/SSRF or command-injection vector (Phase 4 tie-in).
// The handler writes a JSON status into the AppleEvent reply; capturing that reply from
// the CLI/MCP (read-back transport) is the next Phase 3 bite — `open` stays fire-and-forget.
- (void)openUrlSchemeAppleEvent:(NSAppleEventDescriptor *)event
                 withReplyEvent:(NSAppleEventDescriptor *)reply
{
    NSString *urlString =
        [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSString *status = [self mp_handleControlURLString:urlString];
    if (reply && reply.descriptorType != typeNull && status)
    {
        [reply setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:status]
                       forKeyword:keyDirectObject];
    }
}

// Parse + dispatch an x-macdown:// control URL. Returns a JSON status string. UI-touching
// (opens documents / invokes commands), so it is exercised via the live GUI pass; the pure
// validation it delegates to is unit-tested headless (MPURLCommandTests).
- (NSString *)mp_handleControlURLString:(NSString *)urlString
{
    if (urlString.length == 0)
        return [self mp_jsonStatusOK:NO verb:nil extra:@{@"error": @"empty url"}];

    NSURL *url = [[NSURL alloc] initWithString:urlString];
    NSURLComponents *c =
        url ? [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO] : nil;
    if (!c)
        return [self mp_jsonStatusOK:NO verb:nil extra:@{@"error": @"malformed url"}];

    NSString *verb = c.host;                 // open | command
    NSArray *items = c.queryItems ?: @[];

    if ([verb isEqualToString:@"open"])
    {
        NSString *fileParam = [self valueForKey:@"url" fromQueryItems:items];
        NSURL *target = [[self class] validatedFileURLFromParam:fileParam];
        if (!target)
            return [self mp_jsonStatusOK:NO verb:@"open"
                                   extra:@{@"error": @"invalid or missing file url"}];
        NSDocumentController *dc = [NSDocumentController sharedDocumentController];
        [dc openDocumentWithContentsOfURL:target display:YES completionHandler:
         ^(NSDocument *document, BOOL wasOpen, NSError *error) {
             if (!document || wasOpen || error)
                 return;
             NSRect frame = [NSScreen mainScreen].visibleFrame;
             for (NSWindowController *wc in document.windowControllers)
                 [wc.window setFrame:frame display:YES];
         }];
        return [self mp_jsonStatusOK:YES verb:@"open" extra:@{@"path": target.path}];
    }
    else if ([verb isEqualToString:@"command"])
    {
        NSString *idParam = [self valueForKey:@"id" fromQueryItems:items];
        NSString *commandID = [[self class] validatedCommandID:idParam];
        if (!commandID)
            return [self mp_jsonStatusOK:NO verb:@"command"
                                   extra:@{@"error": @"unknown command id",
                                           @"id": (idParam ?: @"")}];
        id current = [[NSDocumentController sharedDocumentController] currentDocument];
        if (![current isKindOfClass:[MPDocument class]])
            return [self mp_jsonStatusOK:NO verb:@"command"
                                   extra:@{@"error": @"no current document",
                                           @"id": commandID}];
        NSError *err = nil;
        BOOL ok = [(MPDocument *)current invokeCommandID:commandID sender:self error:&err];
        NSMutableDictionary *extra = [@{@"id": commandID} mutableCopy];
        if (!ok && err.localizedDescription)
            extra[@"error"] = err.localizedDescription;
        return [self mp_jsonStatusOK:ok verb:@"command" extra:extra];
    }

    return [self mp_jsonStatusOK:NO verb:(verb ?: @"") extra:@{@"error": @"unknown verb"}];
}

- (NSString *)mp_jsonStatusOK:(BOOL)ok verb:(NSString *)verb extra:(NSDictionary *)extra
{
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"ok"] = @(ok);
    if (verb)
        d[@"verb"] = verb;
    [extra enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) { d[k] = v; }];
    NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:NULL];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]
                : @"{\"ok\":false,\"error\":\"json encode failed\"}";
}

+ (NSString *)validatedCommandID:(NSString *)candidate
{
    if (![candidate isKindOfClass:[NSString class]] || candidate.length == 0)
        return nil;
    // Exact, case-sensitive allowlist membership — no trimming, no coercion.
    if ([[MPDocument availableCommandIDs] containsObject:candidate])
        return candidate;
    return nil;
}

+ (NSURL *)validatedFileURLFromParam:(NSString *)param
{
    if (![param isKindOfClass:[NSString class]] || param.length == 0)
        return nil;
    NSURL *url = [NSURL URLWithString:param];
    if (!url || !url.isFileURL)
        return nil;
    if (url.path.length == 0 || ![url.path hasPrefix:@"/"])
        return nil;     // require an absolute local path
    return url;
}

- (NSString *)valueForKey:(NSString *)key fromQueryItems:(NSArray *)queryItems
{
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"name=%@", key];
    NSURLQueryItem *queryItem = [[queryItems filteredArrayUsingPredicate:predicate] firstObject];
    return queryItem.value;
}

- (MPPreferences *)preferences
{
    return [MPPreferences sharedInstance];
}

- (NSWindowController *)preferencesWindowController
{
    if (!_preferencesWindowController)
    {
        NSArray *vcs = @[
            [[MPGeneralPreferencesViewController alloc] init],
            [[MPMarkdownPreferencesViewController alloc] init],
            [[MPEditorPreferencesViewController alloc] init],
            [[MPHtmlPreferencesViewController alloc] init],
            [[MPTerminalPreferencesViewController alloc] init],
        ];
        NSString *title = NSLocalizedString(@"Preferences",
                                            @"Preferences window title.");

        typedef MASPreferencesWindowController WC;
        _preferencesWindowController =
            [[WC alloc] initWithViewControllers:vcs title:title];
    }
    return _preferencesWindowController;
}

- (IBAction)showPreferencesWindow:(id)sender
{
    [self.preferencesWindowController showWindow:nil];
}

- (IBAction)showHelp:(id)sender
{
    MPOpenBundledFile(@"help", @"md");
}

- (IBAction)showContributing:(id)sender
{
    MPOpenBundledFile(@"contribute", @"md");
}


#pragma mark - Override

- (instancetype)init
{
    self = [super init];
    if (!self)
        return self;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(showFirstLaunchTips)
                   name:MPDidDetectFreshInstallationNotification
                 object:self.preferences];
    [self copyFiles];
    return self;
}


#pragma mark - NSApplicationDelegate

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    if (self.preferences.filesToOpen.count || self.preferences.pipedContentFileToOpen)
        return NO;
    return !self.preferences.supressesUntitledDocumentOnLaunch;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    [self openPendingPipedContent];
    [self openPendingFiles];
    treat();
}


#pragma mark - SUUpdaterDelegate

- (NSString *)feedURLStringForUpdater:(SUUpdater *)updater
{
    // Auto-update DISABLED for this private fork. IMPORTANT: returning nil here made Sparkle's
    // SUUpdater (which is instantiated by MainMenu.nib) abort during launch, and because it lives
    // in the main nib that aborted the WHOLE main-nib load -> no menu bar, no window, no crash
    // (the "no UI on launch" bug, root-caused + fixed 2026-06-29). Instead hand the updater an
    // inert, OFFLINE feed: a local file:// URL that never advertises an update. The updater then
    // initialises cleanly, never phones home (file scheme = no network), and can't clobber the
    // fork. Belt+suspenders: SUEnableAutomaticChecks=NO keeps it from ever checking on its own.
    return @"file:///dev/null";
}


#pragma mark - Private

- (void)copyFiles
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *root = MPDataDirectory(nil);
    if (![manager fileExistsAtPath:root])
    {
        [manager createDirectoryAtPath:root
           withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    NSBundle *bundle = [NSBundle mainBundle];
    for (NSString *key in @[kMPStylesDirectoryName, kMPThemesDirectoryName])
    {
        NSURL *dirSource = [bundle URLForResource:key withExtension:@""];
        NSURL *dirTarget = [NSURL fileURLWithPath:MPDataDirectory(key)];

        // If the directory doesn't exist, just copy the whole thing.
        if (![manager fileExistsAtPath:dirTarget.path])
        {
            [manager copyItemAtURL:dirSource toURL:dirTarget error:NULL];
            continue;
        }

        // Check for existence of each file and copy if it's not there.
        NSArray *contents = [manager contentsOfDirectoryAtURL:dirSource
                                   includingPropertiesForKeys:nil options:0
                                                        error:NULL];
        for (NSURL *fileSource in contents)
        {
            NSString *name = fileSource.lastPathComponent;
            NSURL *fileTarget = [dirTarget URLByAppendingPathComponent:name];
            if (![manager fileExistsAtPath:fileTarget.path])
                [manager copyItemAtURL:fileSource toURL:fileTarget error:NULL];
        }
    }
}

- (void)openPendingFiles
{
    NSDocumentController *c = [NSDocumentController sharedDocumentController];

    for (NSString *path in self.preferences.filesToOpen)
    {
        NSURL *url = [NSURL fileURLWithPath:path];
        if ([url checkResourceIsReachableAndReturnError:NULL])
        {
            [c openDocumentWithContentsOfURL:url display:YES
                           completionHandler:MPDocumentOpenCompletionEmpty];
        }
        else
        {
            [c createNewEmptyDocumentForURL:url display:YES error:NULL];
        }
    }

    self.preferences.filesToOpen = nil;
    [self.preferences synchronize];
}

- (void)openPendingPipedContent {
    NSDocumentController *c = [NSDocumentController sharedDocumentController];

    if (self.preferences.pipedContentFileToOpen) {
        NSURL *pipedContentFileToOpenURL = [NSURL fileURLWithPath:self.preferences.pipedContentFileToOpen];
        NSError *readPipedContentError;
        NSString *pipedContentString = [NSString stringWithContentsOfURL:pipedContentFileToOpenURL encoding:NSUTF8StringEncoding error:&readPipedContentError];

        NSError *openDocumentError;
        MPDocument *document = (MPDocument *)[c openUntitledDocumentAndDisplay:YES error:&openDocumentError];

        if (document && openDocumentError == nil && readPipedContentError == nil) {
            document.markdown = pipedContentString;
        }

        self.preferences.pipedContentFileToOpen = nil;
        [self.preferences synchronize];
    }
}


#pragma mark - Notification handler

- (void)showFirstLaunchTips
{
    [self showHelp:nil];
    [self showContributing:nil];
}


@end

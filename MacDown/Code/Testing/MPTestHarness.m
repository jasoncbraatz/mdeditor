//
//  MPTestHarness.m
//  MacDown
//
//  Testing API implementation for programmatic MacDown testing.
//

#import "MPTestHarness.h"
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "MPDocument.h"


static NSError *MPTestError(NSString *description, int code) {
    return [NSError errorWithDomain:@"MPTestHarness"
                               code:code
                           userInfo:@{ NSLocalizedDescriptionKey: description }];
}


@implementation MPTestResult

+ (instancetype)successWithData:(NSDictionary *)data {
    MPTestResult *r = [[MPTestResult alloc] init];
    r.success = YES;
    r.data = data ?: @{};
    r.message = @"";
    return r;
}

+ (instancetype)successWithMessage:(NSString *)message {
    MPTestResult *r = [[MPTestResult alloc] init];
    r.success = YES;
    r.message = message;
    r.data = @{};
    return r;
}

+ (instancetype)failureWithError:(NSError *)error {
    MPTestResult *r = [[MPTestResult alloc] init];
    r.success = NO;
    r.error = error;
    r.message = error.localizedDescription;
    return r;
}

+ (instancetype)failureWithMessage:(NSString *)message {
    MPTestResult *r = [[MPTestResult alloc] init];
    r.success = NO;
    r.error = MPTestError(message, 1);
    r.message = message;
    return r;
}

@end


@implementation MPTestHarness

#pragma mark - Helpers

+ (MPDocument *)_getActiveDocument {
    NSDocumentController *docController = [NSDocumentController sharedDocumentController];
    NSDocument *doc = docController.currentDocument;
    if (![doc isKindOfClass:[MPDocument class]]) {
        return nil;
    }
    return (MPDocument *)doc;
}

+ (WebView *)_getPreviewWebView {
    MPDocument *doc = [self _getActiveDocument];
    if (!doc) return nil;

    // Access preview via Key-Value coding to avoid exposing internals
    @try {
        return [doc valueForKey:@"preview"];
    } @catch (NSException *e) {
        return nil;
    }
}

+ (BOOL)_isWebViewBlank:(WebView *)webview {
    if (!webview || !webview.mainFrame) {
        return YES; // Invalid = blank
    }

    DOMDocument *doc = webview.mainFrameDocument;
    if (!doc) return YES;

    // Check body innerText
    @try {
        DOMNodeList *bodyNodes = [doc getElementsByTagName:@"body"];
        if (!bodyNodes || bodyNodes.length == 0) {
            return YES;
        }

        DOMElement *body = (DOMElement *)[bodyNodes item:0];
        NSString *text = body.innerText;

        // Empty, whitespace-only, or contains only default messages
        NSString *trimmed = [text stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (!trimmed.length ||
            [trimmed isEqualToString:@""] ||
            [trimmed containsString:@"Waiting for content"] ||
            [trimmed containsString:@"Error rendering"]) {
            return YES;
        }

        return NO;
    } @catch (NSException *e) {
        return YES; // Error accessing = treat as blank
    }
}

#pragma mark - Document Access

+ (MPDocument *)currentDocument {
    return [self _getActiveDocument];
}

+ (NSURL *)currentDocumentURL {
    MPDocument *doc = [self currentDocument];
    return doc.fileURL;
}

+ (NSString *)currentMarkdownContent {
    MPDocument *doc = [self currentDocument];
    if (!doc) return nil;

    @try {
        return [doc valueForKey:@"markdown"];
    } @catch (NSException *e) {
        return nil;
    }
}

+ (NSString *)currentRenderedHTML {
    MPDocument *doc = [self currentDocument];
    if (!doc) return nil;

    @try {
        return [doc valueForKey:@"html"];
    } @catch (NSException *e) {
        return nil;
    }
}

#pragma mark - Preview State Verification

+ (BOOL)isPreviewReady {
    MPDocument *doc = [self currentDocument];
    if (!doc) return NO;

    @try {
        NSNumber *ready = [doc valueForKey:@"isPreviewReady"];
        return ready.boolValue;
    } @catch (NSException *e) {
        return NO;
    }
}

+ (BOOL)isPreviewBlank {
    WebView *preview = [self _getPreviewWebView];
    return [self _isWebViewBlank:preview];
}

+ (NSString *)previewContent {
    WebView *preview = [self _getPreviewWebView];
    if (!preview || !preview.mainFrameDocument) return nil;

    @try {
        DOMElement *htmlNode = preview.mainFrameDocument.documentElement;
        return htmlNode ? htmlNode.innerHTML : nil;
    } @catch (NSException *e) {
        return nil;
    }
}

+ (NSString *)previewText {
    WebView *preview = [self _getPreviewWebView];
    if (!preview || !preview.mainFrameDocument) return nil;

    @try {
        DOMNodeList *bodyNodes = [preview.mainFrameDocument getElementsByTagName:@"body"];
        if (!bodyNodes || bodyNodes.length == 0) return nil;

        DOMElement *body = (DOMElement *)[bodyNodes item:0];
        return body.innerText;
    } @catch (NSException *e) {
        return nil;
    }
}

+ (NSError *)lastPreviewError {
    // Store errors in document if a render fails
    // For now, return nil (errors are typically not stored)
    return nil;
}

+ (BOOL)isPreviewWebViewValid {
    WebView *preview = [self _getPreviewWebView];
    return preview != nil && preview.window != nil;
}

#pragma mark - Document Operations

+ (BOOL)openFileAtPath:(NSString *)path timeout:(NSTimeInterval)timeout error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        if (error) {
            *error = MPTestError([NSString stringWithFormat:@"File not found: %@", path], 2);
        }
        return NO;
    }

    NSURL *url = [NSURL fileURLWithPath:path];
    NSDocumentController *docController = [NSDocumentController sharedDocumentController];

    __block BOOL success = NO;
    __block NSError *localError = nil;

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    [docController openDocumentWithContentsOfURL:url
                                         display:YES
                               completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *err) {
        if (err) {
            localError = err;
            success = NO;
        } else {
            success = YES;
            // Wait for preview to be ready
            NSTimeInterval endTime = [[NSDate date] timeIntervalSince1970] + timeout;
            while ([[NSDate date] timeIntervalSince1970] < endTime && ![self isPreviewReady]) {
                [[NSRunLoop currentRunLoop] runUntilDate:
                    [NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
        }
        dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));

    if (!success && error) {
        *error = localError ?: MPTestError(@"Unknown error opening file", 3);
    }

    return success;
}

+ (BOOL)openFileAtPath:(NSString *)path error:(NSError **)error {
    return [self openFileAtPath:path timeout:10.0 error:error];
}

+ (void)simulateIdleForSeconds:(NSTimeInterval)seconds {
    NSTimeInterval endTime = [[NSDate date] timeIntervalSince1970] + seconds;
    while ([[NSDate date] timeIntervalSince1970] < endTime) {
        [[NSRunLoop currentRunLoop] runUntilDate:
            [NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
}

+ (void)forceRefreshPreview {
    MPDocument *doc = [self currentDocument];
    if (!doc) return;

    @try {
        [doc setValue:@NO forKey:@"isPreviewReady"];
        [doc performSelector:@selector(render:) withObject:nil];
    } @catch (NSException *e) {
        // Silently fail
    }
}

+ (BOOL)switchToDocumentWithURL:(NSURL *)url error:(NSError **)error {
    NSDocumentController *docController = [NSDocumentController sharedDocumentController];
    for (NSDocument *doc in docController.documents) {
        if (![doc isKindOfClass:[MPDocument class]]) continue;
        if ([[(MPDocument *)doc fileURL] isEqual:url]) {
            [[(MPDocument *)doc windowControllers].firstObject showWindow:nil];
            [NSApp activateIgnoringOtherApps:YES];
            return YES;
        }
    }

    if (error) {
        *error = MPTestError([NSString stringWithFormat:@"Document not found: %@", url], 4);
    }
    return NO;
}

#pragma mark - Diagnostic Helpers

+ (NSDictionary *)previewWebViewState {
    WebView *preview = [self _getPreviewWebView];
    NSMutableDictionary *state = [NSMutableDictionary dictionary];

    state[@"exists"] = @(preview != nil);
    state[@"loading"] = @(preview.loading);
    state[@"ready"] = @([self isPreviewReady]);
    state[@"blank"] = @([self isPreviewBlank]);
    state[@"valid"] = @([self isPreviewWebViewValid]);

    @try {
        DOMDocument *doc = preview.mainFrameDocument;
        state[@"hasDocument"] = @(doc != nil);

        if (doc) {
            DOMNodeList *bodyNodes = [doc getElementsByTagName:@"body"];
            state[@"bodyNodeCount"] = @(bodyNodes.length);

            if (bodyNodes.length > 0) {
                DOMElement *body = (DOMElement *)[bodyNodes item:0];
                NSString *text = body.innerText;
                state[@"bodyTextLength"] = @(text.length);
                state[@"bodyTextPreview"] = [text substringToIndex:MIN(200, text.length)];
            }
        }
    } @catch (NSException *e) {
        state[@"domAccessError"] = e.reason;
    }

    return state;
}

+ (NSString *)diagnosticReport {
    NSMutableString *report = [NSMutableString string];

    [report appendString:@"=== MacDown Diagnostic Report ===\n\n"];

    // Document info
    MPDocument *doc = [self currentDocument];
    [report appendFormat:@"Document:\n"];
    [report appendFormat:@"  URL: %@\n", [self currentDocumentURL] ?: @"(none)"];
    [report appendFormat:@"  Markdown length: %lu\n",
        [self currentMarkdownContent].length];
    [report appendFormat:@"  HTML length: %lu\n",
        [self currentRenderedHTML].length];
    [report appendString:@"\n"];

    // Preview info
    [report appendString:@"Preview State:\n"];
    [report appendFormat:@"  Ready: %@\n", @([self isPreviewReady]) ? @"YES" : @"NO"];
    [report appendFormat:@"  Blank: %@\n", @([self isPreviewBlank]) ? @"YES (BUG!)" : @"NO"];
    [report appendFormat:@"  Valid: %@\n", @([self isPreviewWebViewValid]) ? @"YES" : @"NO"];

    NSDictionary *webViewState = [self previewWebViewState];
    [report appendFormat:@"  Loading: %@\n", webViewState[@"loading"]];
    [report appendFormat:@"  Body text length: %@\n", webViewState[@"bodyTextLength"]];
    [report appendString:@"\n"];

    // Content preview
    [report appendString:@"Preview Text (first 300 chars):\n"];
    NSString *previewText = [self previewText];
    if (previewText) {
        [report appendString:[previewText substringToIndex:MIN(300, previewText.length)]];
        [report appendString:@"\n"];
    } else {
        [report appendString:@"  (no text content)\n"];
    }
    [report appendString:@"\n"];

    // Bug status
    BOOL isBlank = [self isPreviewBlank];
    [report appendFormat:@"BLANK CANVAS BUG: %@\n", isBlank ? @"DETECTED" : @"NOT DETECTED"];

    return report;
}

+ (void)printDiagnosticReport {
    NSLog(@"%@", [self diagnosticReport]);
}

#pragma mark - Test Assertions

+ (void)assertPreviewReadyAndNotBlank:(NSString *)context {
    if (![self isPreviewReady]) {
        [NSException raise:@"PreviewNotReady"
                   format:@"Preview not ready: %@", context];
    }
    if ([self isPreviewBlank]) {
        [NSException raise:@"PreviewBlank"
                   format:@"Preview is blank (blank canvas bug!): %@", context];
    }
}

+ (void)assertPreviewContainsText:(NSString *)expectedText context:(NSString *)context {
    NSString *previewText = [self previewText];
    if (!previewText || ![previewText containsString:expectedText]) {
        [NSException raise:@"PreviewTextNotFound"
                   format:@"Preview does not contain expected text '%@': %@",
                   expectedText, context];
    }
}

+ (void)assertNoBlankCanvasBug:(NSString *)context {
    if ([self isPreviewBlank]) {
        [NSException raise:@"BlankCanvasBugDetected"
                   format:@"Blank canvas bug detected: %@\n%@",
                   context, [self diagnosticReport]];
    }
}

@end

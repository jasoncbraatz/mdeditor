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


static BOOL s_headlessMode = NO;

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
    if ([doc isKindOfClass:[MPDocument class]]) {
        return (MPDocument *)doc;
    }
    // Fallback (fix 2026-06-29): under automated XCTest the app may not be frontmost, so
    // -currentDocument is nil even though a document window is open. Prefer an MPDocument
    // whose window is main/visible, else the most-recently-added MPDocument.
    MPDocument *visible = nil, *anyDoc = nil;
    for (NSDocument *d in docController.documents) {
        if (![d isKindOfClass:[MPDocument class]]) continue;
        anyDoc = (MPDocument *)d;
        for (NSWindowController *wc in d.windowControllers) {
            if (wc.window.isMainWindow || wc.window.isVisible) { visible = (MPDocument *)d; break; }
        }
    }
    return visible ?: anyDoc;
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
    // The blank-canvas BUG is the preview STAYING empty. A freshly-loaded WebView is briefly
    // empty while it parses/renders, so an instantaneous read yields false positives. Pump the
    // run loop up to ~3s: return NO the moment content appears; only report blank if it stays
    // blank for the whole window (the actual bug). (fix 2026-06-29)
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
    BOOL blank = YES;
    while ([deadline timeIntervalSinceNow] > 0) {
        blank = [self _isWebViewBlank:[self _getPreviewWebView]];
        if (!blank) break;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    return blank;
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

    __block BOOL done = NO;

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
        done = YES;
    }];

    // Pump the main run loop instead of blocking on a semaphore: -openDocumentWithContentsOfURL:
    // delivers its completion handler on the MAIN thread, so a blocking wait here deadlocks
    // (the handler can never run) and every open "times out" with a bogus error. (fix 2026-06-29)
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!done && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    if (!success && error) {
        *error = localError ?: MPTestError(@"Unknown error opening file", 3);
    }

    // Headless: park the freshly-shown window off every visible Space so it never
    // flickers the user's desktop. (Belt & suspenders to the app-side didLoadNib hook,
    // which AppKit can override when it cascades the window on show.)
    if (s_headlessMode && success) {
        MPDocument *opened = [self currentDocument];
        for (NSWindowController *wc in opened.windowControllers) {
            wc.shouldCascadeWindows = NO;
            wc.window.frameAutosaveName = @"";
            [wc.window setFrameOrigin:NSMakePoint(-30000, -30000)];
            wc.window.alphaValue = 0.0;
        }
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
            NSWindowController *wc = [(MPDocument *)doc windowControllers].firstObject;
            if (s_headlessMode) {
                // Stay invisible: never front/activate under headless; keep it parked.
                wc.window.alphaValue = 0.0;
                [wc.window setFrameOrigin:NSMakePoint(-30000, -30000)];
            } else {
                [wc showWindow:nil];
                [NSApp activateIgnoringOtherApps:YES];
            }
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


#pragma mark - Headless / No-UI Test Mode

+ (void)initialize {
    if (self == [MPTestHarness class]) {
        // Auto-enable headless when running under XCTest so the suite never
        // flickers Jason's desktop. Explicit callers (e.g. an MCP) use
        // +enableHeadlessTestMode directly.
        NSDictionary *env = NSProcessInfo.processInfo.environment;
        if (env[@"XCTestConfigurationFilePath"] || env[@"XCTestSessionIdentifier"])
            [self enableHeadlessTestMode];
    }
}

+ (void)enableHeadlessTestMode {
    s_headlessMode = YES;
    // A PROCESS-ONLY flag the app target (MPDocument) reads to hide new windows the
    // instant their nib loads. Deliberately an env var, NOT NSUserDefaults: a persisted
    // default would survive into Jason's real app and hide ITS windows too.
    setenv("MPHeadlessTestMode", "1", 1);
    // Accessory app: no Dock icon, never steals focus from the user's work.
    if (NSApp)
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

+ (BOOL)isHeadlessTestMode {
    return s_headlessMode;
}

+ (NSArray<NSWindow *> *)onscreenVisibleWindows {
    NSMutableArray *result = [NSMutableArray array];
    for (NSWindow *w in NSApp.windows) {
        if (!w.isVisible) continue;
        if (w.alphaValue < 0.01) continue;          // transparent => not seen
        BOOL onScreen = NO;
        for (NSScreen *s in NSScreen.screens) {
            if (NSIntersectsRect(w.frame, s.frame)) { onScreen = YES; break; }
        }
        if (onScreen) [result addObject:w];
    }
    return result;
}

+ (void)enforceHeadlessOnAllWindows {
    if (!s_headlessMode) return;
    for (NSWindow *w in NSApp.windows) {
        if (w.alphaValue > 0.0) w.alphaValue = 0.0;
        if (NSMinX(w.frame) > -10000.0)
            [w setFrameOrigin:NSMakePoint(-30000, -30000)];
    }
}


#pragma mark - Editor Input

+ (NSTextView *)_editor {
    MPDocument *doc = [self currentDocument];
    if (!doc) return nil;
    @try {
        id ed = [doc valueForKey:@"editor"];
        return [ed isKindOfClass:[NSTextView class]] ? (NSTextView *)ed : nil;
    } @catch (NSException *e) { return nil; }
}

+ (void)setMarkdown:(NSString *)markdown {
    MPDocument *doc = [self currentDocument];
    @try { [doc setValue:(markdown ?: @"") forKey:@"markdown"]; }
    @catch (NSException *e) {}
}

+ (BOOL)selectRange:(NSRange)range {
    NSTextView *ed = [self _editor];
    if (!ed) return NO;
    if (NSMaxRange(range) > ed.string.length) return NO;
    ed.selectedRange = range;
    return YES;
}

+ (void)selectAll {
    NSTextView *ed = [self _editor];
    if (ed) ed.selectedRange = NSMakeRange(0, ed.string.length);
}

+ (NSRange)selectedRange {
    NSTextView *ed = [self _editor];
    return ed ? ed.selectedRange : NSMakeRange(NSNotFound, 0);
}

+ (NSString *)selectedText {
    NSTextView *ed = [self _editor];
    if (!ed) return @"";
    NSRange r = ed.selectedRange;
    if (NSMaxRange(r) > ed.string.length) return @"";
    return [ed.string substringWithRange:r];
}

+ (BOOL)selectSubstring:(NSString *)substring {
    NSTextView *ed = [self _editor];
    if (!ed || !substring.length) return NO;
    NSRange r = [ed.string rangeOfString:substring];
    if (r.location == NSNotFound) return NO;
    ed.selectedRange = r;
    return YES;
}


#pragma mark - Command Registry

+ (NSDictionary<NSString *, NSString *> *)commandSelectorMap {
    static NSDictionary *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            // inline formatting
            @"strong": @"toggleStrong:",
            @"emphasis": @"toggleEmphasis:",
            @"code": @"toggleInlineCode:",
            @"strikethrough": @"toggleStrikethrough:",
            @"underline": @"toggleUnderline:",
            @"highlight": @"toggleHighlight:",
            @"comment": @"toggleComment:",
            @"link": @"toggleLink:",
            @"image": @"toggleImage:",
            // headings / paragraph
            @"h1": @"convertToH1:", @"h2": @"convertToH2:", @"h3": @"convertToH3:",
            @"h4": @"convertToH4:", @"h5": @"convertToH5:", @"h6": @"convertToH6:",
            @"paragraph": @"convertToParagraph:",
            // blocks
            @"ul": @"toggleUnorderedList:",
            @"ol": @"toggleOrderedList:",
            @"blockquote": @"toggleBlockquote:",
            @"indent": @"indent:",
            @"unindent": @"unindent:",
            @"newParagraph": @"insertNewParagraph:",
            // output
            @"copyHtml": @"copyHtml:",
            @"render": @"render:",
            // view / layout toggles
            @"togglePreviewPane": @"togglePreviewPane:",
            @"toggleEditorPane": @"toggleEditorPane:",
            @"toggleToolbar": @"toggleToolbar:",
            @"editorOneQuarter": @"setEditorOneQuarter:",
            @"editorThreeQuarters": @"setEditorThreeQuarters:",
            @"equalSplit": @"setEqualSplit:",
            // export (modal save panel — NOT for automation)
            @"exportHtml": @"exportHtml:",
            @"exportPdf": @"exportPdf:",
        };
    });
    return map;
}

+ (NSArray<NSString *> *)availableCommands {
    return [[self commandSelectorMap].allKeys
            sortedArrayUsingSelector:@selector(compare:)];
}

+ (BOOL)invokeCommand:(NSString *)commandId error:(NSError **)error {
    NSString *selName = [self commandSelectorMap][commandId];
    if (!selName) {
        if (error) *error = MPTestError(
            [NSString stringWithFormat:@"Unknown command id: %@", commandId], 10);
        return NO;
    }
    MPDocument *doc = [self currentDocument];
    if (!doc) {
        if (error) *error = MPTestError(@"No current document to invoke command on", 11);
        return NO;
    }
    SEL sel = NSSelectorFromString(selName);
    if (![doc respondsToSelector:sel]) {
        if (error) *error = MPTestError(
            [NSString stringWithFormat:@"Document does not respond to %@", selName], 12);
        return NO;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [doc performSelector:sel withObject:nil];
#pragma clang diagnostic pop
    // Let any editor mutation settle on the runloop.
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                             beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return YES;
}


#pragma mark - Layout / View State

+ (BOOL)_boolKey:(NSString *)key {
    MPDocument *doc = [self currentDocument];
    if (!doc) return NO;
    @try { return [[doc valueForKey:key] boolValue]; }
    @catch (NSException *e) { return NO; }
}
+ (BOOL)previewVisible { return [self _boolKey:@"previewVisible"]; }
+ (BOOL)editorVisible  { return [self _boolKey:@"editorVisible"]; }
+ (BOOL)toolbarVisible { return [self _boolKey:@"toolbarVisible"]; }

@end

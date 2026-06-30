//
//  MPDocument.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 6/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Cocoa/Cocoa.h>
@class MPPreferences;


@interface MPDocument : NSDocument

@property (nonatomic, readonly) MPPreferences *preferences;
@property (readonly) BOOL previewVisible;
@property (readonly) BOOL editorVisible;

@property (nonatomic, readwrite) NSString *markdown;
@property (nonatomic, readonly) NSString *html;

// Test-harness / blank-canvas recovery hook (task 1216089018004712).
@property (readonly) BOOL isPreviewReady;
- (void)forceRefreshPreview;

// Command registry (Phase 1) — the SINGLE implementation behind every editing
// IBAction. Menus and the toolbar reach editing commands through their
// IBActions, which now delegate to -invokeCommandID:sender:error:; the test
// harness and the (future) MCP call the same method directly. That is what makes
// "the GUI only confirms what the harness proves" literally true: one behavior
// path, not two. Command ids are stable strings (e.g. @"strong", @"h1", @"ul").
// See docs/TEST-HARNESS.md for the full id list.
+ (NSArray<NSString *> *)availableCommandIDs;
- (BOOL)invokeCommandID:(NSString *)commandID sender:(id)sender
                  error:(NSError **)error;

// Security (Phase 4, SECURITY-AUDIT finding 1c): allowlist predicate for preview
// WebView subresource loads. YES only for local schemes (file/applewebdata/about/
// data); every remote scheme is refused so a malicious .md cannot beacon out / SSRF.
// Pure class method; unit-tested headlessly (mirrors the MPMainController validators).
+ (BOOL)mp_isAllowedPreviewResourceURL:(NSURL *)url;

@end

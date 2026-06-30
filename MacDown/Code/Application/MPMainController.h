//
//  MPMainController.h
//  MacDown
//
//  Created by Tzu-ping Chung  on 7/06/2014.
//  Copyright (c) 2014 Tzu-ping Chung . All rights reserved.
//

#import <Foundation/Foundation.h>
@class MPPreferences;

@interface MPMainController : NSObject <NSApplicationDelegate>

@property (nonatomic, readonly) MPPreferences *preferences;

#pragma mark - x-macdown:// control surface (Phase 3 MCP transport)

/**
 * Allowlist-validate a candidate editing-command id for `x-macdown://command?id=<id>`.
 *
 * Returns @c candidate unchanged iff it is an EXACT, case-sensitive member of
 * @c +[MPDocument availableCommandIDs] (the very registry the test harness drives),
 * otherwise @c nil. This is an allowlist, NOT a sanitizer: anything not on the list —
 * empty, unknown, or shell/path/whitespace garbage (@c "strong; rm -rf", @c "../x",
 * @c "STRONG\n") — is rejected, never coerced. The transport therefore cannot invoke
 * anything outside the editing-command set. (Phase 4 tie-in: no command injection
 * through the URL scheme.) Pure function — no UI/document state; unit-tested headless.
 */
+ (NSString *_Nullable)validatedCommandID:(NSString *_Nullable)candidate;

/**
 * Validate the @c url= parameter of `x-macdown://open?url=...`.
 *
 * Returns a @c file:// NSURL with an absolute path iff @c param parses to a local-file
 * URL, otherwise @c nil. Rejects non-file schemes (http/https/javascript/x-macdown/…)
 * so the open verb is strictly a local-file opener and not a generic fetch / SSRF /
 * scheme-redirect vector. Does NOT require the file to exist (preserves the prior
 * open-or-create behaviour). Pure function; unit-tested headless. (Phase 4 tie-in.)
 */
+ (NSURL *_Nullable)validatedFileURLFromParam:(NSString *_Nullable)param;

@end

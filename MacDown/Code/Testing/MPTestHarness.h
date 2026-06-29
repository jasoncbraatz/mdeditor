//
//  MPTestHarness.h
//  MacDown
//
//  Testing API for validating MacDown functionality without UI automation.
//  Provides programmatic access to document state, preview content, and operations.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@class MPDocument;

/**
 * MPTestHarness: API for testing MacDown without UI robot automation.
 *
 * Provides methods to:
 * - Inspect document and preview state
 * - Verify preview content is not blank
 * - Programmatically open files
 * - Simulate idle periods
 * - Force preview refresh
 * - Collect diagnostic information
 */
@interface MPTestHarness : NSObject

#pragma mark - Document Access
/// Returns the currently active document (frontmost window's document)
+ (MPDocument *)currentDocument;

/// Returns the file URL of the current document
+ (NSURL *)currentDocumentURL;

/// Returns the markdown content of the current document
+ (NSString *)currentMarkdownContent;

/// Returns the rendered HTML of the current document
+ (NSString *)currentRenderedHTML;


#pragma mark - Preview State Verification
/// Returns YES if the preview WebView has finished loading
+ (BOOL)isPreviewReady;

/// Returns YES if the preview appears blank/empty (bug indicator)
+ (BOOL)isPreviewBlank;

/// Returns the raw HTML content of the preview WebView
+ (NSString *)previewContent;

/// Returns the DOM innerText of the preview body (rendered text)
+ (NSString *)previewText;

/// Returns any error from the last preview render attempt
+ (NSError *)lastPreviewError;

/// Returns YES if preview WebView exists and is valid
+ (BOOL)isPreviewWebViewValid;


#pragma mark - Document Operations
/**
 * Opens a file at the given path.
 * Waits for the document to fully load and preview to render.
 *
 * @param path Absolute file path to .md file
 * @param timeout Maximum seconds to wait for load completion
 * @param error Output parameter for any errors
 * @return YES if successful, NO if timeout or error occurred
 */
+ (BOOL)openFileAtPath:(NSString *)path
              timeout:(NSTimeInterval)timeout
                error:(NSError **)error;

/// Opens a file and waits up to 10 seconds for completion
+ (BOOL)openFileAtPath:(NSString *)path error:(NSError **)error;

/// Simulates an idle period (allows async operations to complete)
+ (void)simulateIdleForSeconds:(NSTimeInterval)seconds;

/// Forces the preview to refresh immediately
+ (void)forceRefreshPreview;

/// Switches focus to a different open document (by URL)
+ (BOOL)switchToDocumentWithURL:(NSURL *)url error:(NSError **)error;


#pragma mark - Diagnostic Helpers
/**
 * Returns a diagnostic report including:
 * - Current document state
 * - Preview ready flag
 * - Preview content (first 500 chars)
 * - WebView DOM tree dump
 * - Any errors from preview rendering
 */
+ (NSString *)diagnosticReport;

/// Prints diagnostic report to stdout
+ (void)printDiagnosticReport;

/// Returns detailed WebView state as dictionary
+ (NSDictionary *)previewWebViewState;


#pragma mark - Test Assertions
/// Asserts preview is ready and not blank; raises exception if fails
+ (void)assertPreviewReadyAndNotBlank:(NSString *)context;

/// Asserts preview contains expected text; raises exception if fails
+ (void)assertPreviewContainsText:(NSString *)expectedText
                          context:(NSString *)context;

/// Asserts no preview blank canvas bug detected; raises exception if fails
+ (void)assertNoBlankCanvasBug:(NSString *)context;


#pragma mark - Headless / No-UI Test Mode
/**
 * Enables headless test mode: the app becomes an accessory (no Dock icon, never
 * steals focus) and every document window is positioned far off-screen the moment
 * its nib loads, so the test suite never flickers the user's desktop. The editor
 * and preview still render normally (the window exists, just off every visible
 * Space), so all reads/commands work. Auto-enabled when running under XCTest.
 */
+ (void)enableHeadlessTestMode;

/// YES if headless test mode is active.
+ (BOOL)isHeadlessTestMode;


#pragma mark - Editor Input (drive the editor like a user)
/// Replaces the entire editor contents with the given markdown.
+ (void)setMarkdown:(NSString *)markdown;

/// Selects the given character range in the editor. Returns NO if out of range.
+ (BOOL)selectRange:(NSRange)range;

/// Selects the whole document.
+ (void)selectAll;

/// The current editor selection range.
+ (NSRange)selectedRange;

/// The currently selected text (empty string if none).
+ (NSString *)selectedText;

/// Selects the first occurrence of `substring`. Returns NO if not found.
+ (BOOL)selectSubstring:(NSString *)substring;


#pragma mark - Command Registry (every toolbar/menu editing action)
/// All stable command ids the harness can invoke (sorted), e.g. @"strong",
/// @"emphasis", @"h1"..@"h6", @"ul", @"ol", @"blockquote", @"indent", @"link".
/// Same ids back the tests and (later) the MCP.
+ (NSArray<NSString *> *)availableCommands;

/// Maps a command id to the MPDocument selector it invokes (@"strong" -> "toggleStrong:").
+ (NSDictionary<NSString *, NSString *> *)commandSelectorMap;

/// Invokes an editing command by stable id against the current document, exactly
/// as the toolbar/menu would. NO (with error) for unknown ids or no current
/// document. Headless-safe for editor commands; @"exportHtml"/@"exportPdf" open a
/// modal panel and are NOT for automation.
+ (BOOL)invokeCommand:(NSString *)commandId error:(NSError **)error;


#pragma mark - Layout / View State (for view-toggle commands)
/// YES if the preview pane is showing (width != 0).
+ (BOOL)previewVisible;
/// YES if the editor pane is showing (width != 0).
+ (BOOL)editorVisible;
/// YES if the window toolbar is visible.
+ (BOOL)toolbarVisible;

@end


#pragma mark - Test Result Data Structure

/**
 * Result of a test operation
 */
@interface MPTestResult : NSObject
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSDictionary *data;
@property (nonatomic, strong) NSString *message;

+ (instancetype)successWithData:(NSDictionary *)data;
+ (instancetype)successWithMessage:(NSString *)message;
+ (instancetype)failureWithError:(NSError *)error;
+ (instancetype)failureWithMessage:(NSString *)message;
@end

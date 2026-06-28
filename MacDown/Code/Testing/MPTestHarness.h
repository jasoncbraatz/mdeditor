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

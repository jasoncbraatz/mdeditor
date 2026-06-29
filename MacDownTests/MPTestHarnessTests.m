//
//  MPTestHarnessTests.m
//  MacDownTests
//
//  Test scenarios using MPTestHarness API to validate MacDown functionality
//  and verify the blank canvas bug is fixed.
//

#import <XCTest/XCTest.h>
#import "MPTestHarness.h"
#import <Foundation/Foundation.h>


@interface MPTestHarnessTests : XCTestCase

@property (nonatomic, strong) NSString *tempDir;
@property (nonatomic, strong) NSString *testFile1;
@property (nonatomic, strong) NSString *testFile2;

@end


@implementation MPTestHarnessTests

- (void)setUp {
    [super setUp];

    // Create temporary directory for test files
    self.tempDir = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"MacDownTests"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    // Create test markdown files
    self.testFile1 = [self.tempDir stringByAppendingPathComponent:@"test1.md"];
    self.testFile2 = [self.tempDir stringByAppendingPathComponent:@"test2.md"];

    NSString *content1 = @"# Test File 1\n\nThis is test file 1.\n\n- Item 1\n- Item 2\n";
    NSString *content2 = @"# Test File 2\n\nThis is test file 2.\n\n> A blockquote\n";

    [[NSFileManager defaultManager] createFileAtPath:self.testFile1
                                            contents:[content1 dataUsingEncoding:NSUTF8StringEncoding]
                                          attributes:nil];

    [[NSFileManager defaultManager] createFileAtPath:self.testFile2
                                            contents:[content2 dataUsingEncoding:NSUTF8StringEncoding]
                                          attributes:nil];
}

- (void)tearDown {
    // Close documents opened during the test so windows don't leak across tests — otherwise a
    // stale prior window gets picked up as the "active" document and content reads go to the wrong
    // preview. Copy the array since -close mutates the controller's documents list. (fix 2026-06-29)
    for (NSDocument *doc in [[[NSDocumentController sharedDocumentController] documents] copy]) {
        [doc close];
    }

    // Clean up temporary directory
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];

    [super tearDown];
}

#pragma mark - Scenario 1: Sequential File Opens

/**
 * Test: Sequential file opens with idle periods
 * Expected: Preview updates correctly, no blank canvas
 *
 * Steps:
 * 1. Open file1.md → Verify preview shows content
 * 2. Wait 5 seconds (idle)
 * 3. Open file2.md → Verify preview updates (not blank)
 * 4. Wait 5 seconds (idle)
 * 5. Verify preview still shows content
 */
- (void)testSequentialFileOpensWithIdle {
    NSError *error = nil;

    // Step 1: Open first file
    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error],
                  @"Failed to open test file 1: %@", error);
    XCTAssertFalse([MPTestHarness isPreviewBlank],
                   @"Preview blank after opening file 1 (bug!)");
    NSString *preview1 = [MPTestHarness previewText];
    XCTAssertTrue([preview1 containsString:@"Test File 1"],
                  @"Preview doesn't contain expected content from file 1");

    // Step 2: Simulate idle
    [MPTestHarness simulateIdleForSeconds:5.0];

    // Step 3: Open second file
    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile2 error:&error],
                  @"Failed to open test file 2: %@", error);

    // **CRITICAL ASSERTION** - This is where the blank canvas bug manifests
    XCTAssertFalse([MPTestHarness isPreviewBlank],
                   @"BLANK CANVAS BUG DETECTED: Preview is blank after opening file 2!\n%@",
                   [MPTestHarness diagnosticReport]);

    NSString *preview2 = [MPTestHarness previewText];
    XCTAssertTrue([preview2 containsString:@"Test File 2"],
                  @"Preview doesn't contain expected content from file 2");

    // Step 4: Simulate idle
    [MPTestHarness simulateIdleForSeconds:5.0];

    // Step 5: Verify preview still shows content
    XCTAssertFalse([MPTestHarness isPreviewBlank],
                   @"Preview blank after idle (bug!): %@",
                   [MPTestHarness diagnosticReport]);
}

#pragma mark - Scenario 2: Rapid File Switching

/**
 * Test: Rapid file switching (no idle between opens)
 * Expected: Preview eventually shows correct content, never blank
 *
 * Steps:
 * 1. Open file1.md
 * 2. Immediately open file2.md (while file1 may still be loading)
 * 3. Verify preview shows file2 content (NOT blank)
 * 4. Verify preview is ready
 */
- (void)testRapidFileSwitching {
    NSError *error = nil;

    // Open file 1 (don't wait for completion)
    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1
                                       timeout:2.0
                                        error:&error],
                  @"Failed to open test file 1: %@", error);

    // Immediately open file 2 (rapid switch)
    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile2
                                       timeout:5.0
                                        error:&error],
                  @"Failed to open test file 2: %@", error);

    // **CRITICAL ASSERTION** - Blank canvas bug check
    XCTAssertFalse([MPTestHarness isPreviewBlank],
                   @"BLANK CANVAS BUG: Preview blank after rapid file switch\n%@",
                   [MPTestHarness diagnosticReport]);

    // Verify correct file is shown
    NSString *preview = [MPTestHarness previewText];
    XCTAssertTrue([preview containsString:@"Test File 2"],
                  @"Preview shows wrong content after rapid switch");
}

#pragma mark - Scenario 3: Preview State Consistency

/**
 * Test: Preview state flags are consistent
 * Expected: isPreviewReady flag accurately reflects state
 *
 * Steps:
 * 1. Open a file
 * 2. Verify isPreviewReady becomes true
 * 3. Verify preview is valid
 * 4. Verify preview is not blank
 */
- (void)testPreviewStateConsistency {
    NSError *error = nil;

    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error],
                  @"Failed to open test file: %@", error);

    // Check all state flags
    XCTAssertTrue([MPTestHarness isPreviewReady],
                  @"Preview should be ready after file open");
    XCTAssertTrue([MPTestHarness isPreviewWebViewValid],
                  @"Preview WebView should be valid");
    XCTAssertFalse([MPTestHarness isPreviewBlank],
                   @"Preview should not be blank: %@",
                   [MPTestHarness diagnosticReport]);
}

#pragma mark - Scenario 4: Repeated Opens (Stress Test)

/**
 * Test: Repeated file opens to stress the preview refresh logic
 * Expected: No crashes, no blank canvas on any open
 *
 * Steps:
 * 1-10. Repeatedly open file1 and file2, alternating
 * 11. Verify no blank canvas bug detected
 */
- (void)testRepeatedFileOpens {
    NSError *error = nil;

    for (int i = 0; i < 5; i++) {
        // Cycle 1: Open file1
        XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error],
                      @"Failed to open file1 in cycle %d: %@", i, error);
        XCTAssertFalse([MPTestHarness isPreviewBlank],
                       @"Preview blank on file1 cycle %d (bug!)", i);

        // Cycle 2: Open file2
        XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile2 error:&error],
                      @"Failed to open file2 in cycle %d: %@", i, error);
        XCTAssertFalse([MPTestHarness isPreviewBlank],
                       @"Preview blank on file2 cycle %d (bug!): %@",
                       i, [MPTestHarness diagnosticReport]);
    }
}

#pragma mark - Scenario 5: Force Refresh

/**
 * Test: Force refresh clears blank canvas state
 * Expected: After force refresh, preview shows content
 *
 * Steps:
 * 1. Open a file
 * 2. Manually simulate blank canvas (if we add that capability)
 * 3. Call forceRefreshPreview
 * 4. Verify preview is no longer blank
 */
- (void)testForceRefreshRecovery {
    NSError *error = nil;

    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error],
                  @"Failed to open test file: %@", error);

    // Trigger a refresh
    [MPTestHarness forceRefreshPreview];

    // Wait for refresh to complete
    [MPTestHarness simulateIdleForSeconds:2.0];

    // Verify not blank after refresh
    XCTAssertFalse([MPTestHarness isPreviewBlank],
                   @"Preview blank after force refresh");
}

#pragma mark - Scenario 6: Diagnostic Reporting

/**
 * Test: Diagnostic report generates without crashing
 * Expected: Report contains expected sections
 */
- (void)testDiagnosticReporting {
    NSError *error = nil;

    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error]);

    NSString *report = [MPTestHarness diagnosticReport];
    XCTAssertNotNil(report);
    XCTAssertTrue(report.length > 0);

    // Verify report contains expected sections
    XCTAssertTrue([report containsString:@"Diagnostic Report"]);
    XCTAssertTrue([report containsString:@"Preview State"]);
    XCTAssertTrue([report containsString:@"BLANK CANVAS BUG"]);
}


#pragma mark - Scenario 7: Headless / No-UI Test Mode

/// The whole point of the harness: a Claude can drive the app WITHOUT a visible UI.
/// Under XCTest, headless mode auto-enables and document windows live off-screen.
- (void)testHeadlessModeKeepsEveryWindowInvisible {
    XCTAssertTrue([MPTestHarness isHeadlessTestMode],
                  @"Headless mode should auto-enable under XCTest");

    NSError *error = nil;
    // Exercise EVERY window code path: open two docs and switch between them.
    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error], @"open1: %@", error);
    XCTAssertEqual(NSApp.activationPolicy, NSApplicationActivationPolicyAccessory,
                   @"App should be an accessory (no Dock icon / focus steal) during tests");
    XCTAssertEqual([MPTestHarness onscreenVisibleWindows].count, 0u,
                   @"After open #1, NO window may be visible on the user's screen");

    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile2 error:&error], @"open2: %@", error);
    XCTAssertEqual([MPTestHarness onscreenVisibleWindows].count, 0u,
                   @"After open #2, NO window may be visible");

    [MPTestHarness switchToDocumentWithURL:[NSURL fileURLWithPath:self.testFile1] error:&error];
    XCTAssertEqual([MPTestHarness onscreenVisibleWindows].count, 0u,
                   @"After switching documents, NO window may be visible (switch must not front/activate)");

    // The windows EXIST (they render) — they're just invisible, not absent.
    BOOL anyDocWindow = NO;
    for (NSWindow *w in NSApp.windows) { if (w.isVisible) { anyDocWindow = YES; break; } }
    XCTAssertTrue(anyDocWindow, @"Expected invisible-but-present document windows");
}


#pragma mark - Scenario 8: Command Registry — coverage

- (void)testCommandRegistryCoversToolbarActions {
    NSArray<NSString *> *cmds = [MPTestHarness availableCommands];
    XCTAssertGreaterThanOrEqual(cmds.count, 25u,
                                @"Registry should cover the toolbar/menu editing actions");
    for (NSString *expected in @[@"strong", @"emphasis", @"code", @"strikethrough",
                                 @"underline", @"highlight", @"comment", @"link", @"image",
                                 @"h1", @"h2", @"h3", @"h4", @"h5", @"h6", @"paragraph",
                                 @"ul", @"ol", @"blockquote", @"indent", @"unindent"]) {
        XCTAssertTrue([cmds containsObject:expected],
                      @"Registry missing command id '%@'", expected);
    }
}

- (void)testInvokeUnknownCommandReturnsError {
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error]);
    error = nil;
    XCTAssertFalse([MPTestHarness invokeCommand:@"bogus-command" error:&error],
                   @"Unknown command id should fail");
    XCTAssertNotNil(error);
}


#pragma mark - Scenario 9: Per-command round-trips (the UI commands, headless)

/// Open a doc, set known editor text, select the whole thing.
- (void)_loadEditorWithText:(NSString *)text {
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error],
                  @"open failed: %@", error);
    [MPTestHarness setMarkdown:text];
    [MPTestHarness selectAll];
}

- (void)_assertInlineCommand:(NSString *)cmd
                  wrapsInput:(NSString *)input
                    toResult:(NSString *)expected {
    [self _loadEditorWithText:input];
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness invokeCommand:cmd error:&error],
                  @"invoke %@ failed: %@", cmd, error);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], expected,
                          @"command '%@' round-trip mismatch", cmd);
}

- (void)testCommand_strong        { [self _assertInlineCommand:@"strong"        wrapsInput:@"boldcheck" toResult:@"**boldcheck**"]; }
- (void)testCommand_emphasis      { [self _assertInlineCommand:@"emphasis"      wrapsInput:@"emcheck"   toResult:@"*emcheck*"]; }
- (void)testCommand_inlineCode    { [self _assertInlineCommand:@"code"          wrapsInput:@"codecheck" toResult:@"`codecheck`"]; }
- (void)testCommand_strikethrough { [self _assertInlineCommand:@"strikethrough" wrapsInput:@"strike"    toResult:@"~~strike~~"]; }
- (void)testCommand_underline     { [self _assertInlineCommand:@"underline"     wrapsInput:@"under"     toResult:@"_under_"]; }
- (void)testCommand_highlight     { [self _assertInlineCommand:@"highlight"     wrapsInput:@"hl"        toResult:@"==hl=="]; }
- (void)testCommand_comment       { [self _assertInlineCommand:@"comment"       wrapsInput:@"note"      toResult:@"<!--note-->"]; }

- (void)testCommand_heading1 {
    [self _loadEditorWithText:@"Title"];
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness invokeCommand:@"h1" error:&error], @"h1 failed: %@", error);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], @"# Title");
}

- (void)testCommand_heading3 {
    [self _loadEditorWithText:@"Sub"];
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness invokeCommand:@"h3" error:&error], @"h3 failed: %@", error);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], @"### Sub");
}

- (void)testCommand_headingTogglesBackToParagraph {
    [self _loadEditorWithText:@"Line"];
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness invokeCommand:@"h2" error:&error]);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], @"## Line");
    [MPTestHarness selectAll];
    XCTAssertTrue([MPTestHarness invokeCommand:@"paragraph" error:&error]);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], @"Line");
}

- (void)testCommand_unorderedList {
    [self _loadEditorWithText:@"item"];
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness invokeCommand:@"ul" error:&error], @"ul failed: %@", error);
    NSString *md = [MPTestHarness currentMarkdownContent];
    XCTAssertTrue([md hasSuffix:@"item"], @"ul should keep content: '%@'", md);
    XCTAssertTrue([md rangeOfString:@"item"].location >= 2,
                  @"ul should prepend a list marker: '%@'", md);
}

- (void)testCommand_orderedList {
    [self _loadEditorWithText:@"item"];
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness invokeCommand:@"ol" error:&error], @"ol failed: %@", error);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], @"1. item");
}

- (void)testCommand_blockquote {
    [self _loadEditorWithText:@"quote"];
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness invokeCommand:@"blockquote" error:&error], @"bq failed: %@", error);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], @"> quote");
}

- (void)testCommand_indentUnindent {
    [self _loadEditorWithText:@"line"];
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness invokeCommand:@"indent" error:&error], @"indent failed: %@", error);
    NSString *indented = [MPTestHarness currentMarkdownContent];
    XCTAssertTrue([indented hasSuffix:@"line"] && indented.length > 4,
                  @"indent should add leading padding: '%@'", indented);
    [MPTestHarness selectAll];
    XCTAssertTrue([MPTestHarness invokeCommand:@"unindent" error:&error], @"unindent failed: %@", error);
    XCTAssertEqualObjects([MPTestHarness currentMarkdownContent], @"line",
                          @"unindent should restore the line");
}


#pragma mark - Scenario 10: Crash-safety sweep (the d0e2853 class of bug)

/// Invoke EVERY non-modal command on an empty doc with no selection — must not crash.
/// (Excludes exportHtml/exportPdf, which open a modal save panel unsuitable for automation.)
- (void)testCrashSafetySweepEmptyDocument {
    NSError *error = nil;
    XCTAssertTrue([MPTestHarness openFileAtPath:self.testFile1 error:&error]);
    [MPTestHarness setMarkdown:@""];

    NSSet *skip = [NSSet setWithArray:@[@"exportHtml", @"exportPdf"]];
    for (NSString *cmd in [MPTestHarness availableCommands]) {
        if ([skip containsObject:cmd]) continue;
        [MPTestHarness selectRange:NSMakeRange(0, 0)];
        NSError *e = nil;
        XCTAssertTrue([MPTestHarness invokeCommand:cmd error:&e],
                      @"command '%@' should invoke without error on empty doc: %@", cmd, e);
        // Surviving to here = it did not crash, which is the point.
    }
    XCTAssertNotNil([MPTestHarness currentDocument], @"document should survive the sweep");
}

@end

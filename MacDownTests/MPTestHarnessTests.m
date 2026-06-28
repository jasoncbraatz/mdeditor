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

@end

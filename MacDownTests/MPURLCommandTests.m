//
//  MPURLCommandTests.m
//  MacDownTests
//
//  Phase 3 (MCP transport) — contract tests for the x-macdown:// control-surface
//  validators on MPMainController. These cover the PURE validation layer (no GUI):
//    • +validatedCommandID:        — the editing-command allowlist
//    • +validatedFileURLFromParam: — the open-verb file-URL guard
//  The actual application of a command to a document is already covered by the registry
//  tests (-[MPDocument invokeCommandID:sender:error:]); the live GUI dispatch path is
//  confirmed by the every-5th-handoff UI pass (MASTER-PLAN §11). Trust model + verb
//  contract: docs/MCP-TRANSPORT.md.
//

#import <XCTest/XCTest.h>
#import "MPMainController.h"
#import "MPDocument.h"

@interface MPURLCommandTests : XCTestCase
@end

@implementation MPURLCommandTests

#pragma mark - +validatedCommandID:

- (void)testKnownCommandIDsPassThroughUnchanged
{
    for (NSString *cid in @[@"strong", @"emphasis", @"code", @"h1", @"h6",
                            @"ul", @"ol", @"blockquote", @"link", @"image"])
    {
        XCTAssertTrue([[MPDocument availableCommandIDs] containsObject:cid],
                      @"sanity: '%@' must be a real registry id", cid);
        XCTAssertEqualObjects([MPMainController validatedCommandID:cid], cid,
                              @"known id '%@' should validate to itself", cid);
    }
}

- (void)testAllowlistIsExactlyTheRegistry
{
    // The allowlist IS +[MPDocument availableCommandIDs] — they must never drift apart,
    // so every advertised id validates.
    for (NSString *cid in [MPDocument availableCommandIDs])
        XCTAssertEqualObjects([MPMainController validatedCommandID:cid], cid);
}

- (void)testUnknownOrMalformedCommandIDsRejected
{
    NSArray<NSString *> *bad = @[ @"", @"bogus", @"STRONG", @" strong", @"strong ",
                                  @"strong\n", @"strong; rm -rf /", @"../../etc/passwd",
                                  @"h7", @"<script>", @"strong&id=image", @"str" ];
    for (NSString *cid in bad)
        XCTAssertNil([MPMainController validatedCommandID:cid],
                     @"garbage id '%@' must be rejected", cid);
    XCTAssertNil([MPMainController validatedCommandID:nil]);
}

#pragma mark - +validatedFileURLFromParam:

- (void)testValidFileURLAccepted
{
    NSURL *u = [MPMainController validatedFileURLFromParam:@"file:///tmp/a%20note.md"];
    XCTAssertNotNil(u);
    XCTAssertTrue(u.isFileURL);
    XCTAssertEqualObjects(u.path, @"/tmp/a note.md", @"percent-escapes should decode");
}

- (void)testNonFileOrMissingURLRejected
{
    NSArray<NSString *> *bad = @[ @"", @"http://evil.example/x", @"https://evil.example",
                                  @"javascript:alert(1)", @"x-macdown://command?id=strong",
                                  @"ftp://host/f", @"foo.md" ];
    for (NSString *p in bad)
        XCTAssertNil([MPMainController validatedFileURLFromParam:p],
                     @"non-file/garbage param '%@' must be rejected", p);
    XCTAssertNil([MPMainController validatedFileURLFromParam:nil]);
}


#pragma mark - +validatedExportPathFromParam:

- (void)testValidExportPathsAccepted
{
    for (NSString *param in @[ @"file:///tmp/out.html", @"file:///tmp/out.htm",
                              @"file:///tmp/My%20Doc.HTML", @"file:///Users/x/a.b.html" ])
    {
        NSURL *u = [MPMainController validatedExportPathFromParam:param];
        XCTAssertNotNil(u, @"export path '%@' should validate", param);
        XCTAssertTrue(u.isFileURL);
    }
}

- (void)testNonHTMLExtensionExportPathsRejected
{
    // Stricter than the open guard: writing requires an .html/.htm suffix so a typo can't
    // clobber a dotfile/binary, and non-file schemes stay off the network.
    NSArray<NSString *> *bad = @[ @"", @"file:///tmp/out.md", @"file:///tmp/out",
                                  @"file:///tmp/.bashrc", @"file:///tmp/out.html.sh",
                                  @"http://evil.example/x.html", @"javascript:alert(1)",
                                  @"file://relative.html", @"out.html" ];
    for (NSString *param in bad)
        XCTAssertNil([MPMainController validatedExportPathFromParam:param],
                     @"export path '%@' must be rejected", param);
    XCTAssertNil([MPMainController validatedExportPathFromParam:nil]);
}

@end

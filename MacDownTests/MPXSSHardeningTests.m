//
//  MPXSSHardeningTests.m
//  MacDownTests
//
//  Phase 4 (security audit) — contract tests for the preview-WebView XSS hardening
//  (SECURITY-AUDIT.md finding 1). These cover the two PURE logic units, headlessly:
//    • MPSanitizeHTMLBody()                      — the md->HTML body sanitizer (layer 1)
//    • +[MPDocument mp_isAllowedPreviewResourceURL:] — the remote-load allowlist (layer 3)
//  The CSP <meta> (layer 2) is a declarative template change verified by the
//  every-5th-handoff GUI pass (preview/Prism/MathJax still render) — it has no logic
//  to unit-test. Mirrors the MPURLCommandTests style. Trust model: SECURITY-AUDIT.md.
//

#import <XCTest/XCTest.h>
#import "MPRenderer.h"
#import "MPDocument.h"

@interface MPXSSHardeningTests : XCTestCase
@end

@implementation MPXSSHardeningTests

#pragma mark - MPSanitizeHTMLBody: strips active content

- (void)testStripsScriptElementAndContent
{
    NSString *out = MPSanitizeHTMLBody(@"<p>hi</p><script>alert(1)</script><p>bye</p>");
    XCTAssertFalse([out.lowercaseString containsString:@"<script"], @"script tag must be gone");
    XCTAssertFalse([out containsString:@"alert(1)"], @"script body must be gone");
    XCTAssertTrue([out containsString:@"<p>hi</p>"], @"legit content preserved");
    XCTAssertTrue([out containsString:@"<p>bye</p>"], @"legit content preserved");
}

- (void)testStripsScriptWithAttributesAndUppercase
{
    NSString *out = MPSanitizeHTMLBody(@"<SCRIPT type=\"text/javascript\">evil()</SCRIPT>");
    XCTAssertFalse([out.lowercaseString containsString:@"script"], @"case-insensitive strip");
    XCTAssertFalse([out containsString:@"evil()"], @"body gone");
}

- (void)testStripsStrayUnclosedScriptOpener
{
    NSString *out = MPSanitizeHTMLBody(@"<p>x</p><script src=\"evil.js\">");
    XCTAssertFalse([out.lowercaseString containsString:@"<script"], @"lone opener removed");
}

- (void)testStripsIframeObjectEmbed
{
    NSString *out = MPSanitizeHTMLBody(
        @"<iframe src=\"http://evil\"></iframe><object data=\"x\"></object><embed src=\"y\">");
    XCTAssertFalse([out.lowercaseString containsString:@"<iframe"], @"iframe gone");
    XCTAssertFalse([out.lowercaseString containsString:@"<object"], @"object gone");
    XCTAssertFalse([out.lowercaseString containsString:@"<embed"], @"embed gone");
}

- (void)testStripsInlineEventHandlers
{
    NSString *out = MPSanitizeHTMLBody(@"<img src=\"cat.png\" onerror=\"alert(1)\">");
    XCTAssertFalse([out.lowercaseString containsString:@"onerror"], @"on*= handler removed");
    XCTAssertFalse([out containsString:@"alert(1)"], @"handler body gone");
    XCTAssertTrue([out containsString:@"cat.png"], @"the legit src survives");
}

- (void)testStripsEventHandlerUnquotedAndUppercase
{
    NSString *out = MPSanitizeHTMLBody(@"<div ONCLICK=doEvil()>x</div>");
    XCTAssertFalse([out.lowercaseString containsString:@"onclick"], @"unquoted/uppercase handler removed");
}

- (void)testNeutralizesJavascriptURI
{
    NSString *out = MPSanitizeHTMLBody(@"<a href=\"javascript:alert(1)\">click</a>");
    XCTAssertFalse([out.lowercaseString containsString:@"javascript:"], @"javascript: scheme neutralized");
    XCTAssertTrue([out containsString:@"unsafe:"], @"replaced with inert scheme");
    XCTAssertTrue([out containsString:@">click</a>"], @"link text preserved");
}

- (void)testNeutralizesVbscriptAndUnquotedJavascript
{
    NSString *out = MPSanitizeHTMLBody(@"<a href=vbscript:msgbox>x</a><a href='javascript:x'>y</a>");
    XCTAssertFalse([out.lowercaseString containsString:@"vbscript:"], @"vbscript: neutralized");
    XCTAssertFalse([out.lowercaseString containsString:@"javascript:"], @"quoted javascript: neutralized");
}

- (void)testNeutralizesDangerousDataURIButKeepsImages
{
    NSString *html = @"<a href=\"data:text/html,<script>alert(1)</script>\">x</a>"
                     @"<img src=\"data:image/png;base64,iVBORw0KGgo=\">";
    NSString *out = MPSanitizeHTMLBody(html);
    XCTAssertFalse([out.lowercaseString containsString:@"data:text/html"], @"data:text/html neutralized");
    XCTAssertTrue([out containsString:@"data:image/png;base64,iVBORw0KGgo="], @"data:image/png preserved");
}

- (void)testNeutralizesDataSvgWhichCanCarryScript
{
    NSString *out = MPSanitizeHTMLBody(@"<img src=\"data:image/svg+xml;base64,PHN2Zz4=\">");
    XCTAssertFalse([out.lowercaseString containsString:@"data:image/svg"], @"svg data URI is not in the raster allowlist");
}

#pragma mark - MPSanitizeHTMLBody: preserves legitimate markup

- (void)testPreservesLegitimateInlineHTML
{
    NSString *html = @"<h1>Title</h1><p>A <strong>bold</strong> <em>word</em> and "
                     @"<a href=\"https://example.com\">a link</a>.</p>"
                     @"<table><tr><td>cell</td></tr></table><pre><code class=\"language-c\">int x;</code></pre>";
    NSString *out = MPSanitizeHTMLBody(html);
    XCTAssertEqualObjects(out, html, @"benign HTML (incl. http: links + code blocks) must pass through unchanged");
}

- (void)testEmptyAndNilSafe
{
    XCTAssertEqualObjects(MPSanitizeHTMLBody(@""), @"", @"empty in, empty out");
    XCTAssertNil(MPSanitizeHTMLBody(nil), @"nil in, nil out (no crash)");
}

#pragma mark - +mp_isAllowedPreviewResourceURL: remote-load allowlist

- (void)testLocalSchemesAllowed
{
    for (NSString *u in @[@"file:///Users/x/a.png",
                          @"applewebdata://abc/x.css",
                          @"about:blank",
                          @"data:image/png;base64,iVBORw0KGgo="])
    {
        XCTAssertTrue([MPDocument mp_isAllowedPreviewResourceURL:[NSURL URLWithString:u]],
                      @"local scheme must be allowed: %@", u);
    }
}

- (void)testRemoteSchemesBlocked
{
    for (NSString *u in @[@"http://evil.example/beacon.gif",
                          @"https://evil.example/x.js",
                          @"ftp://host/f",
                          @"ws://host/s"])
    {
        XCTAssertFalse([MPDocument mp_isAllowedPreviewResourceURL:[NSURL URLWithString:u]],
                       @"remote scheme must be blocked: %@", u);
    }
}

- (void)testSchemelessRelativeAllowed
{
    XCTAssertTrue([MPDocument mp_isAllowedPreviewResourceURL:[NSURL URLWithString:@"images/cat.png"]],
                  @"a relative (schemeless) reference resolves locally and is allowed");
}

- (void)testSchemeMatchIsCaseInsensitive
{
    XCTAssertTrue([MPDocument mp_isAllowedPreviewResourceURL:[NSURL URLWithString:@"FILE:///x"]],
                  @"scheme comparison is case-insensitive");
    XCTAssertFalse([MPDocument mp_isAllowedPreviewResourceURL:[NSURL URLWithString:@"HTTPS://evil/x"]],
                   @"case-insensitive block too");
}

@end

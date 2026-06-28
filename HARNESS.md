# MacDown Test Harness & API

## Blank Canvas Bug

### Problem
After opening a markdown file and letting it idle, opening another file results in a blank 2-panel canvas (editor + preview panes both appear blank/empty). The only resolution is closing and reopening the app.

### Root Cause
The bug is likely a **state management issue** in the WebView lifecycle:

1. **Stale WebView state**: When a new document is opened while another is idle, the preview WebView (`self.preview`) may retain stale DOM state or fail to properly load new HTML.
2. **Race condition in frame loading**: The `didFinishLoadForFrame:` delegate may not be called properly on subsequent document opens, leaving `isPreviewReady` in an inconsistent state.
3. **Missing force-refresh**: There's no explicit mechanism to reset the WebView completely when switching documents.

### Technical Details
From `MPDocument.m`:
- Line 1115: `[self.preview.mainFrame loadHTMLString:html baseURL:baseUrl]` loads preview HTML
- Line 882: `self.isPreviewReady = YES` is set in `didFinishLoadForFrame:`
- The WebView delegates are set up in `windowControllerDidLoadNib:` (line 399-402)
- When a second file is opened, the same WebView instance is reused

### Solution
1. **Force WebView reset** when switching documents
2. **Ensure isPreviewReady is reset** to NO when starting a new render
3. **Add defensive null checks** for WebView state
4. **Test with automation** to reproduce and validate the fix

## Test Harness

### API-Based Testing (No UI Robot)
The test harness provides a Swift/Objective-C API to:

1. **Document State Inspection**
   - Get current document's markdown content
   - Get current document's rendered HTML
   - Get current document's file URL

2. **Preview Verification**
   - Query preview WebView DOM
   - Verify preview content is not blank
   - Check if preview is ready

3. **Document Switching**
   - Open a file programmatically
   - Trigger idle state
   - Switch to another file
   - Validate no blank canvas occurs

### Swift/Objective-C Test API

```objective-c
// MPTestHarness.h - API for testing without UI automation

@interface MPTestHarness : NSObject

// Document management
+ (NSDocument *)currentDocument;
+ (NSURL *)currentDocumentURL;
+ (NSString *)currentMarkdownContent;
+ (NSString *)currentRenderedHTML;

// Preview state
+ (BOOL)isPreviewReady;
+ (BOOL)isPreviewBlank;
+ (NSString *)previewContent;
+ (NSError *)lastPreviewError;

// Operations
+ (void)openFileAtPath:(NSString *)path completion:(void (^)(NSError *error))completion;
+ (void)simulateIdleForSeconds:(NSTimeInterval)seconds;
+ (void)forceRefreshPreview;

// Debugging
+ (NSString *)diagnosticReport;

@end
```

### Test Scenarios

**Scenario 1: Sequential File Opens**
```
1. Open file1.md → Verify preview is not blank
2. Wait 5 seconds (idle) → Verify preview still shows content
3. Open file2.md → Verify preview updates (NOT blank)
4. Wait 5 seconds (idle) → Verify preview still shows content
```

**Scenario 2: Rapid File Switching**
```
1. Open file1.md
2. Open file2.md  (while file1 is still loading)
3. Verify preview shows file2 content (NOT blank)
```

**Scenario 3: Window Reuse**
```
1. Open file1.md in window1 → Verify content
2. Open file2.md in window1 → Verify content updates
3. Switch back to file1 → Verify content (NOT blank)
```

## Build & Compile

### Prerequisites
- Xcode Command Line Tools
- CocoaPods (via Bundler)
- macOS 10.8+

### Build Steps

```bash
cd macdown

# Install dependencies
bundle install
bundle exec pod install

# Build via Xcode (scheme: MacDown)
xcodebuild -workspace MacDown.xcworkspace \
  -scheme MacDown \
  -configuration Release \
  build

# Output: build/Release/MacDown.app
```

### Devkit Setup (Darwin Configuration)

Add to `~/.zshrc` or `~/.bash_profile`:

```bash
# MacDown development kit paths
export MACDOWN_REPO="$HOME/Desktop/downloads/strike-zone/1216089018004712/macdown"
export MACDOWN_BUILD="$MACDOWN_REPO/build/Release"
export MACDOWN_BUNDLE="$MACDOWN_BUILD/MacDown.app"

# Xcode toolchain (already available via Command Line Tools)
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# CocoaPods via bundler (from repo)
alias pod='cd "$MACDOWN_REPO" && bundle exec pod'

# Quick launch (for testing)
alias macdown-dev='open -a "$MACDOWN_BUNDLE"'
```

## Implementation Plan

### Phase 1: Test Harness (this run)
1. ✅ Create `MPTestHarness.h/m` with inspection API
2. ✅ Implement document/preview state queries
3. ✅ Build automated test scenarios

### Phase 2: Bug Fix (next run if needed)
1. Modify `MPDocument.m` to force WebView refresh on document switch
2. Reset `isPreviewReady` flag appropriately
3. Add defensive state checks

### Phase 3: Validation (next run)
1. Run test harness against patched build
2. Verify scenarios pass
3. Create regression test suite

## Files Modified/Created

- `macdown/MPTestHarness.h` - Test API header
- `macdown/MPTestHarness.m` - Test API implementation
- `macdown/MacDownTests/TestHarnessTests.m` - Test scenarios
- `macdown/MacDown/Code/Document/MPDocument.m` - Bug fixes (in progress)
- `HARNESS.md` - This file

## Known Issues

- CocoaPods installation may fail on newer macOS with older pod versions
  - Workaround: Use Xcode's built-in handling or manually manage frameworks
- WebView is deprecated in newer macOS (use WKWebView in future)
  - This project uses legacy WebView; keep for now for compatibility

#!/bin/bash
#
# DARWIN-SETUP.sh — MacDown development environment configuration
#
# Sets up the macOS development environment for building MacDown from our fork.
# Configures environment variables, paths, and aliases for efficient development.
#
# Usage:
#   source DARWIN-SETUP.sh
#   # Or add to ~/.zshrc or ~/.bash_profile:
#   # source ~/Desktop/downloads/strike-zone/1216089018004712/macdown/DARWIN-SETUP.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}═══ MacDown Darwin Development Setup ═══${NC}"

# ============================================================================
# 1. REPOSITORY PATH
# ============================================================================

MACDOWN_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo -e "${GREEN}✓${NC} Repository: $MACDOWN_REPO"

# ============================================================================
# 2. XCODE TOOLCHAIN PATHS
# ============================================================================

# Verify Xcode Command Line Tools are installed
if ! xcode-select --print-path > /dev/null 2>&1; then
    echo -e "${RED}✗ Xcode Command Line Tools not found${NC}"
    echo "  Install with: xcode-select --install"
    exit 1
fi

XCODE_PATH=$(xcode-select --print-path)
echo -e "${GREEN}✓${NC} Xcode toolchain: $XCODE_PATH"

# Verify FULL Xcode.app — CocoaPods + xcodebuild need it (CLT alone is not enough).
XCODE_APP=""
for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    [ -d "$candidate" ] && XCODE_APP="$candidate" && break
done
if [ -z "$XCODE_APP" ]; then
    echo -e "${YELLOW}!${NC} Full Xcode.app NOT installed (only CLT detected)."
    echo "    Required for macdown-build/test. Install via Mac App Store, then run:"
    echo "      sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    echo "      sudo xcodebuild -license accept"
    echo "      sudo xcodebuild -runFirstLaunch"
    echo "    Re-source this script after install."
else
    echo -e "${GREEN}✓${NC} Xcode.app: $XCODE_APP"
    if [ "$XCODE_PATH" != "$XCODE_APP/Contents/Developer" ]; then
        echo -e "${YELLOW}!${NC} xcode-select points at CLT, not Xcode.app. Switch with:"
        echo "      sudo xcode-select --switch $XCODE_APP/Contents/Developer"
    fi
fi

# ============================================================================
# 3. BUILD OUTPUT PATHS
# ============================================================================

MACDOWN_BUILD="$MACDOWN_REPO/build/Release"
MACDOWN_BUNDLE="$MACDOWN_BUILD/MacDown.app"
MACDOWN_EXECUTABLE="$MACDOWN_BUNDLE/Contents/MacOS/MacDown"

# ============================================================================
# 4. COCOAPODS SETUP
# ============================================================================

# Check if Bundler is available
if ! command -v bundle &> /dev/null; then
    echo -e "${RED}✗ Bundler not found${NC}"
    echo "  Install with: sudo gem install bundler"
    exit 1
fi

echo -e "${GREEN}✓${NC} Bundler available"

# Function to run pod via bundler (from repo)
macdown_pod() {
    (cd "$MACDOWN_REPO" && bundle exec pod "$@")
}

# ============================================================================
# 5. ENVIRONMENT VARIABLES
# ============================================================================

# Export for use in subshells
export MACDOWN_REPO
export XCODE_PATH
export MACDOWN_BUILD
export MACDOWN_BUNDLE
export MACDOWN_EXECUTABLE
export DEVELOPER_DIR="$XCODE_PATH"

echo -e "${GREEN}✓${NC} Environment variables set"

# ============================================================================
# 6. SHELL ALIASES & FUNCTIONS
# ============================================================================

# Build MacDown
macdown-build() {
    echo -e "${YELLOW}Building MacDown...${NC}"
    cd "$MACDOWN_REPO"

    # Install pods if needed
    if [ ! -d "Pods" ]; then
        echo -e "${YELLOW}Installing CocoaPods dependencies...${NC}"
        macdown_pod install
    fi

    # Build
    xcodebuild \
        -workspace MacDown.xcworkspace \
        -scheme MacDown \
        -configuration Release \
        -derivedDataPath build \
        build

    echo -e "${GREEN}✓ Build complete: $MACDOWN_BUNDLE${NC}"
}

# Clean build
macdown-clean() {
    echo -e "${YELLOW}Cleaning build artifacts...${NC}"
    cd "$MACDOWN_REPO"
    xcodebuild clean
    rm -rf build/
    echo -e "${GREEN}✓ Clean complete${NC}"
}

# Launch built app
macdown-run() {
    if [ ! -d "$MACDOWN_BUNDLE" ]; then
        echo -e "${RED}✗ Build not found at $MACDOWN_BUNDLE${NC}"
        echo "  Run 'macdown-build' first"
        return 1
    fi

    echo -e "${YELLOW}Launching MacDown...${NC}"
    open -a "$MACDOWN_BUNDLE"
}

# Run tests
macdown-test() {
    echo -e "${YELLOW}Running tests...${NC}"
    cd "$MACDOWN_REPO"

    xcodebuild \
        -workspace MacDown.xcworkspace \
        -scheme MacDownTests \
        -configuration Debug \
        -derivedDataPath build \
        test
}

# Install development dependencies
macdown-deps() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    cd "$MACDOWN_REPO"
    bundle install --deployment
    macdown_pod install
    echo -e "${GREEN}✓ Dependencies installed${NC}"
}

# Print setup summary
macdown-info() {
    cat <<EOF

${GREEN}MacDown Development Environment${NC}

Repository:     $MACDOWN_REPO
Build Output:   $MACDOWN_BUILD
Bundle:         $MACDOWN_BUNDLE
Xcode:          $XCODE_PATH

${YELLOW}Available Commands:${NC}

  macdown-deps      Install all dependencies (CocoaPods, Bundler)
  macdown-build     Build MacDown in Release mode
  macdown-clean     Clean build artifacts
  macdown-run       Launch the built application
  macdown-test      Run test suite
  macdown-info      Show this information

  macdown_pod       Run pod commands (e.g., macdown_pod install)

${YELLOW}Example Workflow:${NC}

  macdown-deps      # Install dependencies (one-time)
  macdown-build     # Build the app
  macdown-run       # Launch to test
  macdown-test      # Run tests

  # Make changes to source code...
  macdown-build     # Rebuild
  macdown-run       # Test changes

${YELLOW}Troubleshooting:${NC}

  • CocoaPods install fails:
    Try: macdown_pod install --repo-update

  • Build fails with missing framework:
    Try: macdown-clean && macdown-deps && macdown-build

  • Tests fail to find headers:
    Try: xcodebuild -workspace MacDown.xcworkspace -scheme MacDown build-for-testing

EOF
}

# ============================================================================
# 7. INITIALIZATION OUTPUT
# ============================================================================

echo -e "${GREEN}✓${NC} Environment configured successfully"
echo ""
echo "Run ${YELLOW}macdown-info${NC} to see available commands."

# Export functions for use in subshells
export -f macdown-build
export -f macdown-clean
export -f macdown-run
export -f macdown-test
export -f macdown-deps
export -f macdown-info
export -f macdown_pod

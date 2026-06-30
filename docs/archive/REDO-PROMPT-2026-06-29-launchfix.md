
---
## STATE UPDATE — 2026-06-29 (co-pilot, interactive Cowork session)
Advanced the prep so the ONLY remaining blocker is the Xcode.app install:
- ✅ `verify_integration.sh` all green (5 bug-fix markers, forceRefreshPreview .h/.m, harness wired, clang parse OK, remote tip 85996b5).
- ✅ Toolchain installed via Homebrew (no Apple ID needed, reversible `brew uninstall`):
  - `cocoapods` 1.16.2 on Homebrew **ruby 4.0.5** — this SIDESTEPS the system-ruby-2.6 crash the worker hit (do NOT use /usr/bin/ruby for pods).
  - `xcodes` 2.0.2 — makes the Xcode install one command.
- ✅ `pod install` COMPLETED — all 9 pods staged (Pods/ + MacDown.xcworkspace ready). (Pods/ is gitignored; pod install also touched project.pbxproj + Podfile.lock locally — regenerable, not pushed.)

### The remaining HITL step (needs YOUR Apple ID):
```bash
xcodes install --latest          # prompts for Apple ID + 2FA; downloads full Xcode.app (~15GB+)
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch
```
### Then build/test (deps already staged — skip macdown-deps):
```bash
cd ~/Desktop/downloads/strike-zone/1216089018004712/macdown
git checkout fix/blank-canvas-bug
xcodebuild -workspace MacDown.xcworkspace -scheme MacDown -configuration Debug build
# then run the built app + macdown-test (MPTestHarnessTests)
```
### ⚠️ EXPECT THIS NEXT HURDLE: deployment target is `10.8` (Podfile + project.pbxproj).
Modern Xcode (16+/26) refuses targets below ~10.13. First build will likely error on the
deployment target. Fix: bump `platform :osx, "10.8"` in Podfile to e.g. "10.13" (or 11.0),
bump MACOSX_DEPLOYMENT_TARGET in MacDown.xcodeproj, then re-run `pod install` and rebuild.
Hold this as the first fix to try once Xcode is in (don't edit blind before you can compile).

---
## ✅ COMPLETE — 2026-06-29 (co-pilot, interactive Cowork session)
Xcode 26.6 installed (xcodes, `/Applications/Xcode-26.6.0.app`). MacDown now BUILDS and the
blank-canvas fix is VALIDATED — full suite **26 tests, 0 failures** (incl. MPTestHarnessTests 6/6,
testSequentialFileOpensWithIdle = the blank-canvas reproduction). Also confirmed live by eye
(preview renders Test File 2, not blank). Build cmd used:
`xcodebuild test -workspace MacDown.xcworkspace -scheme MacDown -configuration Debug CODE_SIGNING_ALLOWED=NO`.
Fixes shipped to fork branch fix/blank-canvas-bug (commit 1da04da): deployment target 10.8→10.13,
+ 4 harness bugs (main-thread-deadlock open, instantaneous-blank false positive, nil currentDocument
fallback, doc-leak across tests). PREREQ on a fresh clone: `git submodule update --init --recursive`
(prism). Remaining OPTIONAL polish: pod per-target deployment warnings (10.6/10.7) — cosmetic; add a
Podfile post_install to silence. PR to upstream still NOT opened (per original task).

PROJECT = GlossPop.xcodeproj
SCHEME  = GlossPop
DEST    = platform=macOS,arch=arm64

# Debug signing: a Developer ID identity (auto-detected from the keychain) keeps the binary's
# code-signing identity stable across rebuilds, so the Accessibility (TCC) grant sticks instead
# of re-prompting after every build. With no such certificate, builds fall back to unsigned
# ad-hoc exactly as before. Override: make build SIGN_ID="…" (or SIGN_ID= to force unsigned).
SIGN_ID ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
ifeq ($(strip $(SIGN_ID)),)
SIGNING = CODE_SIGNING_ALLOWED=NO
else
SIGNING = CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(SIGN_ID)"
endif

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination '$(DEST)' -configuration Debug \
	  -derivedDataPath build $(SIGNING) -quiet

# Tests stay unsigned (they never touch TCC) and use their own derived data: a hardened-runtime
# Developer ID host from `make build` would block XCTest bundle injection (library validation),
# and an incremental build does not strip the previous signature.
test: gen
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -destination '$(DEST)' -derivedDataPath build-test \
	  CODE_SIGNING_ALLOWED=NO -quiet

run: build
	open build/Build/Products/Debug/GlossPop.app

clean:
	rm -rf build build-test $(PROJECT)

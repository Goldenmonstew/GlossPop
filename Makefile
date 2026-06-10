PROJECT = GlossPop.xcodeproj
SCHEME  = GlossPop
DEST    = platform=macOS,arch=arm64

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	  -destination '$(DEST)' -configuration Debug \
	  -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet

test: gen
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
	  -destination '$(DEST)' -derivedDataPath build \
	  CODE_SIGNING_ALLOWED=NO -quiet

run: build
	open build/Build/Products/Debug/GlossPop.app

clean:
	rm -rf build $(PROJECT)

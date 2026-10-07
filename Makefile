PROJECT  := Spread.xcodeproj
SCHEME   := Spread
DERIVED  := build/DerivedData
DEST     := 'platform=macOS'
XCB      := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination $(DEST) -derivedDataPath $(DERIVED)

.PHONY: gen build test run install clean

gen:
	xcodegen generate

build: gen
	$(XCB) -configuration Debug build

test: gen
	$(XCB) test

run: build
	-pkill -x Spread
	open $(DERIVED)/Build/Products/Debug/Spread.app

install: gen
	$(XCB) -configuration Release build
	-pkill -x Spread
	rm -rf /Applications/Spread.app
	cp -R $(DERIVED)/Build/Products/Release/Spread.app /Applications/Spread.app
	open /Applications/Spread.app

clean:
	rm -rf build $(PROJECT)

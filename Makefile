PROJECT := TuringEnigma.xcodeproj
SCHEME := TuringEnigma
DERIVED := .build
APP := $(DERIVED)/Build/Products/Debug/Turing Enigma.app
ICON := Sources/App/Resources/AppIcon.icns
SWIFT := xcrun swift

.PHONY: generate build test uitest check run snapshot viewport-check flow-check ui-check icon clean

generate: $(ICON)
	xcodegen generate

$(ICON): Scripts/generate-icon.swift
	$(SWIFT) Scripts/generate-icon.swift $(ICON) $(DERIVED)/icon/AppIcon-1024.png

icon: $(ICON)
	file $(ICON)

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -configuration Debug build CODE_SIGNING_ALLOWED=NO

test: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -configuration Debug test -only-testing:TuringEnigmaCoreTests CODE_SIGNING_ALLOWED=NO

uitest: generate
	@DevToolsSecurity -status | grep -q enabled || { echo "UI tests require Developer Mode. Enable it with: sudo DevToolsSecurity -enable"; exit 1; }
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -configuration Debug test -only-testing:TuringEnigmaUITests CODE_SIGNING_ALLOWED=NO

check: test snapshot viewport-check flow-check ui-check
	@echo "Core tests, visual snapshots, viewport checks, demo flow checks, and UI actions are up to date."

run: build
	open "$(APP)"

snapshot: build
	"$(APP)/Contents/MacOS/Turing Enigma" --snapshot .build/snapshots

viewport-check: build
	"$(APP)/Contents/MacOS/Turing Enigma" --viewport-check

flow-check: build
	"$(APP)/Contents/MacOS/Turing Enigma" --flow-check

ui-check: build
	"$(APP)/Contents/MacOS/Turing Enigma" --ui-action-check

clean:
	rm -rf $(DERIVED) TuringEnigma.xcodeproj

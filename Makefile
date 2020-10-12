prefix ?= /usr/local
bindir = $(prefix)/bin

build:
	swift build -c release --disable-sandbox

install: build
	install ".build/release/swift-package-api-diff" "$(bindir)"

uninstall:
	rm -rf "$(bindir)/swift-package-api-diff"

clean:
	rm -rf .build

.PHONY: build install uninstall clean

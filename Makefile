PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: install uninstall check test

install:
	install -Dm755 bin/lfs "$(DESTDIR)$(PREFIX)/bin/lfs"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/lfs"

check:
	bash -n bin/lfs scripts/build-binutils-pass1.sh scripts/test-blf-workspace.sh

test: check
	bash scripts/test-blf-workspace.sh

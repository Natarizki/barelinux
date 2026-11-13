PREFIX ?= /usr/local
DESTDIR ?=

.PHONY: install uninstall check test

install:
	install -Dm755 bin/lfs "$(DESTDIR)$(PREFIX)/bin/lfs"

uninstall:
	rm -f "$(DESTDIR)$(PREFIX)/bin/lfs"

check:
	bash -n bin/lfs scripts/test-blf-workspace.sh

test: check
	bash scripts/test-blf-workspace.sh

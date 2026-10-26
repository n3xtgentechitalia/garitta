PREFIX ?= /usr/local
SHELL_SCRIPTS := bin/garitta bin/garitta-blocklist install.sh uninstall.sh deploy.sh \
                 packaging/deb/build.sh tests/test_blocklist.sh tests/test_cli.sh tests/stubs/cscli
VERSION := $(shell cat VERSION)

.PHONY: all test test-shell test-python lint check-version deb install uninstall clean

all: test

test: check-version test-shell test-python

test-shell:
	bash tests/test_blocklist.sh
	bash tests/test_cli.sh

test-python:
	python3 -I -W error::ResourceWarning -m unittest discover -s tests -p 'test_*.py' -v

lint:
	@command -v shellcheck >/dev/null && shellcheck -x $(SHELL_SCRIPTS) || echo "shellcheck not installed, skipped"
	@command -v ruff >/dev/null && ruff check --line-length 130 bin/garitta-digest tests/test_digest.py || echo "ruff not installed, skipped"

check-version:
	@for f in bin/garitta bin/garitta-blocklist; do grep -q '^VERSION=$(VERSION)$$' $$f || { echo "$$f: VERSION mismatch"; exit 1; }; done
	@grep -q "^VERSION = '$(VERSION)'$$" bin/garitta-digest || { echo "bin/garitta-digest: VERSION mismatch"; exit 1; }
	@echo "version $(VERSION) consistent"

deb:
	packaging/deb/build.sh

install:
	./install.sh --prefix $(PREFIX)

uninstall:
	./uninstall.sh --prefix $(PREFIX)

clean:
	rm -rf dist tests/__pycache__

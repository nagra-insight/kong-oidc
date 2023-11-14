# common makefiles to include (see available Makefiles: https://github.com/nagra-insight/ci-tools/tree/master/makefiles)
COMMON_MAKEFILES=cd

NAME=kong-oidc
VERSION:=$(shell sed -n 's/version = \"\(.*\)\"/\1/p' $(NAME)-*ni*.rockspec)
KONG_VERSION=3.5.0

.PHONY: test
test: test/unit test/integration ## run all tests tests

.PHONY: test/unit
test/unit: ## run unit tests only
	./bin/run-unit-tests.sh

.PHONY: test/integration
test/integration: ## run integration tests only
	KONG_VERSION=$(KONG_VERSION) pongo run --no-cassandra

.PHONY: test/clean
test/clean: ## shutdown test container and clean tmp directories
	rm -rf servroot
	pongo down

.PHONY: build
build: ## build binary
	luarocks build --pack-binary-rock

.PHONY: check-release
check-release: ## check if the current version can be released
	@# check that the version has been bumped
	@if [ $$(git tag -l $(NAME)@$(VERSION)) ]; then \
		echo "Tag $(NAME)@$(VERSION) already exists. Exit."; \
		exit 1; \
	fi
	@# check that the rockspec file name matched the version in it
	@# see: https://github.com/luarocks/luarocks/wiki/Creating-a-rock#writing-a-rockspec
	@if [ ! -f "$(NAME)-$(VERSION).rockspec" ]; then \
		echo "rockspec file name not found for version $(VERSION). Did you forget to rename it?"; \
		exit 1; \
	fi
	@echo "$(NAME)@$(VERSION) not released yet, all good!"

.PHONY: release
release: ## create new Github release
	@if [ ! -f "$(NAME)-$(VERSION).all.rock" ]; then \
		echo "no binary rock file found for version $(VERSION) in $(shell pwd):"; \
		ls -al; \
	fi
	@make cd/release NAME=$(NAME) VERSION=$(VERSION) FILE=$(NAME)-$(VERSION).all.rock

##### DO NOT MODIFY BELOW - BEGIN #####################
SELF=$(MAKE)

ifndef CI_DIR
CI_REPO?=git@github.com:nagra-insight/ci-tools.git
CI_DIR?=ci-tools

FETCH_CI := $(shell [ ! -d $(CI_DIR) ] && git clone $(CI_REPO) $(CI_DIR) > /dev/null)
endif

# include default targets
include $(CI_DIR)/makefiles/Makefile.helpers

# include extra makefiles
MODULES?=$(COMMON_MAKEFILES)
$(foreach module,$(MODULES),$(eval include $(CI_DIR)/makefiles/Makefile.$(module)))
##### DO NOT MODIFY BELOW - END #####################

VERSION=$(shell (grep version kong-oidc-*ni*.rockspec | awk '{print $$3}'))
TAG=v$(VERSION)

.PHONY: help
help: ## this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: check-release
check-release: ## check if the current version can be released
	@# check that the version has been bumped
	@if [ $$(git tag -l $(TAG)) ]; then \
		echo "Tag $(TAG) already exists. Exit."; \
		exit 1; \
	fi
	@# check that the filename matches the current version
	@if [ ! -f "kong-oidc-$(VERSION).rockspec" ]; then \
		echo "Rockspec file not found for version $(VERSION). Exit."; \
		exit 1; \
	fi

.PHONY: release
release: check-release ## tag current version
	git tag $(TAG)
	git push --tags

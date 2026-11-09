# Makefile
# Build and validation targets for the ansible-acm-dr collection.
# Run 'make help' for a summary of available targets.

.DEFAULT_GOAL := help
.PHONY: help lint ansible-lint yamllint markdownlint shellcheck syntax-check molecule test collection-build clean

# Collects all playbook files under playbooks/ for syntax-check.
PLAYBOOKS := $(wildcard playbooks/*.yml)

##@ Linting

lint: ansible-lint yamllint markdownlint shellcheck  ## Run all linters (ansible-lint, yamllint, markdownlint, shellcheck)

ansible-lint:  ## Run ansible-lint against the full repository
	ansible-lint .

yamllint:  ## Run yamllint against all YAML files
	yamllint .

markdownlint:  ## Run markdownlint-cli2 against all Markdown files
	npx markdownlint-cli2 "**/*.md"

shellcheck:  ## Run ShellCheck against all shell scripts in examples/scripts/
	find examples/scripts/ -name '*.sh' -exec shellcheck {} +

##@ Validation

syntax-check:  ## Syntax-check every entrypoint playbook under playbooks/
	@for pb in $(PLAYBOOKS); do \
		echo "Checking $$pb..."; \
		ansible-playbook "$$pb" --syntax-check || exit 1; \
	done

molecule:  ## Run the molecule default scenario (offline: no cluster needed)
	molecule test

##@ Combined

test: lint syntax-check molecule  ## Run all checks: lint + syntax-check + molecule

##@ Build

collection-build:  ## Build the Ansible collection tarball
	ansible-galaxy collection build --force

##@ Cleanup

clean:  ## Remove build artifacts (tarballs, context build dirs)
	rm -f *.tar.gz
	rm -rf context/_build/

##@ Help

help:  ## Show this help message
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

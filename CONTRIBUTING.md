# Contributing

Thanks for considering a contribution. This document covers the development setup, code conventions, and the pull request workflow.

## Development setup

Clone the repository and install the toolchain:

```bash
# Python dependencies (use a virtualenv or pipx, never sudo pip)
pip install ansible-core ansible-lint yamllint molecule molecule-plugins

# Ansible collection dependencies
ansible-galaxy collection install -r collections/requirements.yml

# Markdown linter (requires Node.js)
npm install -g markdownlint-cli2

# Shell script static analysis (Fedora/RHEL)
sudo dnf install ShellCheck
```

## Code conventions

[*`CLAUDE.md`*](CLAUDE.md) is the full reference for every convention in this project. The summary below covers what you will hit most often.

### FQCN on all modules

Every task uses fully qualified collection names. No bare module names, ever.

```yaml
# correct
- name: Get the ManagedCluster list
  kubernetes.core.k8s_info:
    kind: ManagedCluster

# wrong
- name: Get the ManagedCluster list
  k8s_info:
    kind: ManagedCluster
```

### Task naming

Tasks follow the **`"[STAGE NN - Name] | N.N.N) Description"`** pattern so that **`-v`** output and AAP job logs are scannable stage by stage:

```yaml
- name: "[STAGE 00 - Preflight] | 0.1.2) Validate required variables"
```

Name every task, block, and handler.

### Variable naming

Role variables are prefixed with the role name (**`acm_dr_failover_manager_*`**, **`acm_dr_hub_cleanup_*`**). Numeric values carry an inline comment with the unit and purpose:

```yaml
acm_dr_failover_manager_restore_timeout: 1800  # seconds (30 minutes), wait for OADP Restore to complete
acm_dr_failover_manager_spoke_retry_count: 20  # retry count, polls for Spoke reconnection
```

### Assert messages

Every **`ansible.builtin.assert`** uses both **`fail_msg`** and **`success_msg`** with the standard prefixes:

```yaml
fail_msg: "❌ FAILED! Oh. No! => k8s_target_context is empty; pass it with -e"
success_msg: "✅ PASSED! Oh. Yes! => target context resolved: {{ k8s_target_context }}"
```

Never omit **`success_msg`**.

### Credential handling

Set **`no_log: true`** on any task that touches tokens, client secrets, PATs, or kubeconfig content. This includes **`debug`** tasks used for troubleshooting.

### Status emojis

These are a project convention, not decoration:

| Symbol | Meaning |
|--------|---------|
| ✅ | Success |
| ❌ | Hard failure |
| ⚠️ | Non-blocking warning |
| 🔎 | Dry-run notice |
| 🛡️ | Safety-guard check |

## Running tests

The [*`Makefile`*](Makefile) wraps all validation targets:

```bash
# Run everything: linters + syntax-check + molecule
make test

# Individual checks
make lint            # ansible-lint + yamllint + markdownlint + shellcheck
make syntax-check    # all playbooks under playbooks/
make molecule        # molecule default scenario

# Build the collection tarball
make collection-build
```

Run **`make help`** for the full list of targets.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
feat|fix|docs|refactor|chore|test(scope): imperative summary
```

The body explains *why* the change was made, not a restatement of the diff. One logical change per commit.

Examples:

```
feat(spoke_manager): add EKS distribution auto-detection

fix(failover_manager): resolve wrong backup when both Hubs share storage

docs(lab_setup): add Azure Storage reuse flag to README

chore: update kubernetes.core collection to 6.6.0
```

## Pull request process

1. One logical change per PR. Keep diffs small and reviewable.
2. All checks must pass (**`make test`**).
3. If you add new variables, declare them in the role's **`defaults/main.yml`** with an inline comment (unit + purpose) and document them in the role's **`README.md`**.
4. If you add stages or change behavior, update the role's README.
5. Never commit secrets, **`.env`** files, kubeconfig content, `*.tfstate`, or `*.retry` files.
6. Internal file references in Markdown prose must be clickable links (see [*`CLAUDE.md`*](CLAUDE.md) for the format).

## License

This project is licensed under GPL-3.0-or-later. By submitting a contribution, you agree to license your work under the same terms.

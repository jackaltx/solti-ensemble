# GitHub Workflow Guide - solti-ensemble

## Branch Strategy

This collection uses a two-branch workflow:

- **dev**: Development/integration branch
- **main**: Production-ready branch

## Development Workflow

```
feature branch → dev → main (via PR)
```

### Working on Features

1. **Create feature branch from dev**:
   ```bash
   git checkout dev
   git pull
   git checkout -b feature/my-feature
   ```

2. **Develop with checkpoint commits**:
   ```bash
   git add -A
   git commit -m "checkpoint: description"
   # Run tests, iterate
   ```

3. **Push to dev branch**:
   ```bash
   git checkout dev
   git merge feature/my-feature
   git push origin dev
   ```

4. **Monitor dev branch workflows**:
   - lint.yml: Fast feedback (~5 min)
   - superlinter.yml: Comprehensive validation (~10 min)

5. **When ready, create PR dev → main**:
   - GitHub UI: Create Pull Request
   - Triggers ci.yml: Full 3-platform testing (~60 min)
   - Review artifacts before merging

## Workflow Triggers

| Workflow | dev branch | main branch | What it does |
|----------|------------|-------------|--------------|
| **lint.yml** | ✅ push/PR | ✅ push/PR | YAML, Markdown, Ansible lint + syntax |
| **superlinter.yml** | ✅ push/PR | ❌ | Comprehensive validation (Super-Linter) |
| **ci.yml** | ❌ | ✅ PR only | Full molecule tests (3 platforms) |

## Testing Locally Before Push

### Lint checks
```bash
# YAML
yamllint .

# Markdown
markdownlint "**/*.md" --ignore node_modules

# Ansible
ansible-lint

# Syntax check
ansible-playbook --syntax-check <playbook.yml>
```

### Molecule tests
```bash
# Install dependencies
pip install molecule molecule-plugins ansible-core

# Test single platform
MOLECULE_PLATFORM_NAME=uut-ct1 MOLECULE_TEST_ROLE=mariadb molecule test -s github

# Test specific role
MOLECULE_TEST_ROLE=acme molecule test -s github
```

## CI Configuration

### Platform Matrix

| Platform | Container Image | SSH Port | Distro |
|----------|----------------|----------|--------|
| uut-ct0 | ghcr.io/jackaltx/testing-containers/debian-ssh:12 | 2223 | Debian 12 |
| uut-ct1 | ghcr.io/jackaltx/testing-containers/rocky-ssh:9 | 2222 | Rocky Linux 9 |
| uut-ct2 | ghcr.io/jackaltx/testing-containers/ubuntu-ssh:24 | 2224 | Ubuntu 24.04 |

### Environment Variables

**ci.yml accepts**:
- `MOLECULE_TEST_ROLE`: Which service to test (default: mariadb)

**Example manual trigger**:
1. Go to Actions → CI workflow
2. Click "Run workflow"
3. Select branch: main
4. Enter test_role: acme
5. Run

## Artifacts

### Test Results (ci.yml)
- **Name**: ensemble-test-results-{platform}
- **Path**: verify_output/
- **Retention**: 5 days
- **Contains**: Test reports, verification output

### Logs (ci.yml, on failure)
- **Name**: ensemble-logs-{platform}
- **Path**: log/
- **Retention**: 2 days
- **Contains**: Debug logs, error traces

## Troubleshooting

### Lint failures
Check the failing job in GitHub Actions, fix locally, push again.

### Molecule test failures
1. Download artifacts from failed run
2. Review verify_output/{distro}/consolidated_test_report.md
3. Fix issue locally
4. Test with: `molecule test -s github`
5. Create checkpoint commit and push

### Superlinter too strict
Superlinter runs only on dev branch - use it for early feedback.
If a check is problematic, disable it in [superlinter.yml](workflows/superlinter.yml).

## Branch Protection (Recommended)

Configure on GitHub:
- **dev branch**: No restrictions (direct push allowed)
- **main branch**:
  - Require pull request reviews
  - Require status checks: lint.yml jobs
  - Do not allow force push
  - Do not allow deletions

## Migration from Manual Testing

Current workflow uses molecule for testing shared services.
The molecule workflows integrate with the existing patterns:

```yaml
# molecule/github/converge.yml
- include_role:
    name: jackaltx.solti_ensemble.{{ test_service }}
  vars:
    service_state: present
```

Your existing verify.yml tasks are preserved and called by molecule verify phase.

## Next Steps

1. **Push dev branch to GitHub**:
   ```bash
   git push -u origin dev
   ```

2. **Test superlinter** on dev branch:
   - Monitor for any lint failures
   - Fix issues before advancing to main

3. **Adapt molecule/shared/verify** playbooks:
   - Customize for shared service testing needs
   - Add MariaDB, HashiVault, ACME verification tasks

4. **Create first PR dev → main**:
   - Triggers full CI pipeline
   - Validates the workflow end-to-end

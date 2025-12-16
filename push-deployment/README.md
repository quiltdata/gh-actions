# Push Deployment Action

Automatically updates the deployment repository's `versions.csv` file and pushes directly to the target branch when a dev tag is pushed.

## Overview

This action simplifies deployment by:
1. Finding the PR associated with the current branch
2. Reading the `deploy:<branch>` label from the PR
3. Updating `versions.csv` in the deployment repository
4. Committing and pushing directly to the target branch
5. The push triggers the actual deployment

## Features

- **Direct push** - No PR creation, changes go directly to target branch
- **Label-based routing** - Deploy label specifies target branch
- **Automatic PR lookup** - Finds PR by source branch name
- **CSV update** - Handles both new and existing components
- **Idempotent** - Skips update if version already set
- **Clear audit trail** - Commit messages include source info

## Usage

### Basic Example

```yaml
- uses: quiltdata/gh-actions/push-deployment@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    deployment-repo: quiltdata/deployment
    component-name: tabulator
    component-version: ${{ steps.tag.outputs.tag_name }}
    source-repo: ${{ github.repository }}
    source-branch: ${{ github.ref_name }}
```

### Complete Workflow Example

```yaml
name: Build and Deploy Dev Image

on:
  push:
    tags:
      - 'dev-*'

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      pull-requests: read

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Extract tag name
        id: tag
        run: |
          TAG_NAME=${GITHUB_REF#refs/tags/}
          echo "tag_name=$TAG_NAME" >> $GITHUB_OUTPUT

      - name: Get branch name from tag
        id: branch
        run: |
          # Get the branch that contains this tag
          BRANCH=$(git branch -r --contains ${{ github.ref }} | grep -v HEAD | sed 's/.*\///' | head -1)
          echo "branch_name=$BRANCH" >> $GITHUB_OUTPUT

      # Build Docker image
      - uses: quiltdata/gh-actions/lambda-deploy-ecr-staging@main
        with:
          dockerfile-path: Dockerfile
          docker-context-path: .
          name: tabulator
          image-tag: ${{ steps.tag.outputs.tag_name }}

      # Update deployment repository
      - name: Push to deployment repository
        uses: quiltdata/gh-actions/push-deployment@main
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          deployment-repo: quiltdata/deployment
          component-name: tabulator
          component-version: ${{ steps.tag.outputs.tag_name }}
          source-repo: ${{ github.repository }}
          source-branch: ${{ steps.branch.outputs.branch_name }}

      - name: Deployment summary
        run: |
          echo "## Deployment Summary" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "- Image: ${{ steps.tag.outputs.tag_name }}" >> $GITHUB_STEP_SUMMARY
          echo "- Branch: ${{ steps.branch.outputs.branch_name }}" >> $GITHUB_STEP_SUMMARY
          echo "- Deployed: ${{ steps.push.outputs.deployed }}" >> $GITHUB_STEP_SUMMARY
          if [ "${{ steps.push.outputs.deployed }}" == "true" ]; then
            echo "- Target: ${{ steps.push.outputs.target-branch }}" >> $GITHUB_STEP_SUMMARY
            echo "- Commit: ${{ steps.push.outputs.commit-sha }}" >> $GITHUB_STEP_SUMMARY
          fi
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `github-token` | GitHub token with repo access | Yes | - |
| `deployment-repo` | Deployment repository (e.g., `quiltdata/deployment`) | Yes | - |
| `component-name` | Component name in versions.csv (e.g., `tabulator`) | Yes | - |
| `component-version` | Version to set (e.g., `dev-test-1`) | Yes | - |
| `source-repo` | Source repository (e.g., `quiltdata/tabulator`) | Yes | - |
| `source-branch` | Source branch name | Yes | - |

## Outputs

| Output | Description |
|--------|-------------|
| `deployed` | Whether deployment was pushed (`true`/`false`) |
| `target-branch` | Target deployment branch that was updated |
| `commit-sha` | Commit SHA of the deployment update |

## How It Works

### 1. Find PR by Branch Name

The action uses `gh pr list` to find the open PR for the source branch:

```bash
gh pr list \
  --repo quiltdata/tabulator \
  --head ignore-extra-columns \
  --state open \
  --json number,labels
```

### 2. Extract Deploy Label

Looks for a label matching the pattern `deploy:<branch>`:

- `deploy:main` → Deploy to main branch
- `deploy:stack/feature-x` → Deploy to stack/feature-x branch
- `deploy:dev` → Deploy to dev branch

### 3. Update versions.csv

Checks out the deployment repository at the target branch and updates `versions.csv`:

```csv
tabulator,dev-test-1
catalog,v1.2.3
api,v2.0.1
```

The action handles both updating existing entries and adding new ones.

### 4. Commit and Push

Creates a commit with detailed information:

```
Deploy tabulator@dev-test-1

Triggered by: quiltdata/tabulator@ignore-extra-columns
PR: #123
Tag: dev-test-1
```

Then pushes directly to the target branch (no PR created).

## Workflow Example

### Developer Workflow

1. **Create PR** with changes
2. **Add deploy label**: `deploy:stack/my-feature`
3. **Create dev tag**: `git tag dev-my-feature-v1 && git push origin dev-my-feature-v1`
4. **GitHub Actions runs**:
   - Builds Docker image
   - Pushes to staging ECR
   - Updates deployment repo
5. **Deployment triggers** automatically when deployment branch is updated

### PR Label Examples

```
deploy:main              # Deploy to main stack
deploy:stack/experiment  # Deploy to experiment stack
deploy:dev               # Deploy to dev environment
deploy:test              # Deploy to test environment
```

## Deployment Repository Structure

The deployment repository should have:

```
deployment/
├── versions.csv          # Component versions
├── stack.py             # Stack configuration
└── deploy.sh            # Deployment script
```

### versions.csv Format

Simple CSV format:

```csv
component,version
tabulator,dev-test-1
catalog,v1.2.3
api,v2.0.1
```

No headers, just component name and version.

## Error Handling

The action gracefully handles various scenarios:

### No PR Found

```
No open PR found for branch ignore-extra-columns
```

Action outputs `deployed=false` and exits successfully.

### No Deploy Label

```
No deploy: label found on PR #123
```

Action outputs `deployed=false` and exits successfully.

### Version Already Set

```
No changes to commit (version already up to date)
```

Action outputs `deployed=false` and exits successfully.

### Missing versions.csv

```
Error: versions.csv not found in deployment repository
```

Action fails with exit code 1.

## Security Considerations

### GitHub Token

The action requires a GitHub token with:
- `repo` scope (to read PRs and push to deployment repo)
- Typically use `${{ secrets.GITHUB_TOKEN }}` which is automatically provided

### Branch Protection

Target deployment branches can still have:
- Required status checks
- Code owners
- Branch protection rules

The action respects all branch protection rules.

## Comparison to PR-Based Approach

### Old Approach (PR Creation)

```
Dev Tag → Build Image → Create Deployment PR → Review → Merge → Deploy
```

**Issues:**
- Extra PR review step
- Manual merge required
- Slower deployment
- More complexity

### New Approach (Direct Push)

```
Dev Tag → Build Image → Push to Deployment Branch → Deploy
```

**Benefits:**
- Immediate deployment
- No manual intervention
- Simpler workflow
- Clear audit trail

## Troubleshooting

### Action doesn't find PR

**Check:**
- PR is open (not draft or closed)
- Branch name matches exactly
- PR is in the source repository

### Deploy label not recognized

**Check:**
- Label starts with `deploy:` (case-sensitive)
- Label has a branch name after the colon
- Label is on the PR (not on an issue)

### Push fails

**Check:**
- GitHub token has repo permissions
- Target branch exists in deployment repo
- Branch protection rules allow push
- versions.csv file exists

### No changes committed

This is normal if the version is already set. The action skips the commit to avoid no-op updates.

## Examples

### Multi-Component Deployment

```yaml
- name: Deploy multiple components
  uses: quiltdata/gh-actions/push-deployment@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    deployment-repo: quiltdata/deployment
    component-name: tabulator,catalog  # Multiple components
    component-version: ${{ steps.tag.outputs.tag_name }}
    source-repo: ${{ github.repository }}
    source-branch: ${{ steps.branch.outputs.branch_name }}
```

### Conditional Deployment

```yaml
- name: Deploy only on specific labels
  if: contains(github.event.pull_request.labels.*.name, 'deploy:')
  uses: quiltdata/gh-actions/push-deployment@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    deployment-repo: quiltdata/deployment
    component-name: tabulator
    component-version: ${{ steps.tag.outputs.tag_name }}
    source-repo: ${{ github.repository }}
    source-branch: ${{ github.event.pull_request.head.ref }}
```

## Related Actions

- `lambda-deploy-ecr-staging` - Builds and pushes Docker images
- `lambda-deploy-ecr` - Production ECR deployment

## Support

For issues or questions:
- Check workflow logs for detailed error messages
- Verify PR labels and branch names
- Review deployment repository structure
- Check GitHub token permissions

## License

MIT

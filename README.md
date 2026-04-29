# gh-actions

Reusable GitHub Actions and composite actions for quiltdata repos.

## Actions

### [deploy-ecr](./deploy-ecr)

Unified ECR image action. Builds a Docker image from the caller's checked-out
workspace, pushes it to a configurable subset of ECR targets, and optionally
forces ECS Fargate deployments for deployable targets.

Targets:

- `prod` - account 730278974607, us-east-1
- `mp` - Marketplace account 709825985650, us-east-1, push-only
- `govcloud` - account 313325871032, us-gov-east-1

`push_targets: '[]'` builds only. Empty `image_tag` resolves to
`git rev-parse HEAD`, which keeps image tags correct when a dispatch workflow
checks out a different branch than the dispatching ref.

```yaml
- uses: actions/checkout@v6
  with:
    ref: ${{ inputs.ref || github.ref }}
- uses: quiltdata/gh-actions/deploy-ecr@deploy-ecr
  with:
    image_name: quiltdata/catalog
    push_targets: ${{ inputs.push_targets || '["prod","mp","govcloud"]' }}
    mp_image_name: quilt-data/quilt-payg-catalog
    role_name: Quilt
```

For ECS services, pass `cluster_name` and `service_name`; deployments run for
pushed `prod` and `govcloud` targets only.

```yaml
- uses: quiltdata/gh-actions/deploy-ecr@deploy-ecr
  with:
    image_name: quiltdata/services/foo
    cluster_name: my-cluster
    service_name: my-service
    push_targets: ${{ inputs.push_targets || '["prod","govcloud"]' }}
```

For Lambda-style image fanout, set `multi_region: 'true'` to push to every
enabled region in each selected target account.

Use `additional_tags` when a workflow must preserve extra tags such as
`latest`:

```yaml
    additional_tags: '["latest"]'
```

Use `docker_platform` and `build_args` when a workflow already pins build
architecture or embeds build metadata:

```yaml
    docker_platform: linux/amd64
    build_args: |
      VERSION=${{ steps.git.outputs.sha }}
```

## Conventions

- All ECR-pushing actions assume the consumer repo has an IAM role at
  `arn:aws:iam::<account>:role/github/GitHub-<role_name>` (and the GovCloud
  equivalent), where `<role_name>` defaults to the repo name and can be
  overridden via the `role_name` input.
- The `push_targets` JSON-array pattern - default `["prod","govcloud"]` for
  push events, `["prod"]` or `[]` for `workflow_dispatch` - lets
  `workflow_dispatch` produce dev images without pushing to release-channel
  registries.
- Callers are responsible for `actions/checkout` before calling `deploy-ecr`
  so setup and pre-build steps can populate the workspace first.

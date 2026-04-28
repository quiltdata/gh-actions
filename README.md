# gh-actions

Reusable GitHub Actions and composite actions for quiltdata repos.

## Actions

### [build-and-push-ecr](./build-and-push-ecr)

Build a Docker image and push to a configurable subset of ECR targets:
`prod` (account 730278974607, us-east-1), `mp` (Marketplace, cross-account
709825985650), `govcloud` (account 313325871032, us-gov-east-1).

`push-targets: '[]'` builds only — useful for dev iteration via
`workflow_dispatch` without polluting any ECR.

```yaml
- uses: actions/checkout@v6
- uses: quiltdata/gh-actions/build-and-push-ecr@main
  with:
    image-name: quiltdata/catalog
    push-targets: ${{ inputs.push-targets || '["prod","govcloud","mp"]' }}
    mp-image-name: quilt-data/quilt-payg-catalog
    role-name: Quilt
```

### [fargate-deploy-ecr](./fargate-deploy-ecr)

Same build + push flow, plus `aws ecs update-service --force-new-deployment`
per target for ECS Fargate services. Targets: `prod`, `govcloud` (no MP —
Marketplace is a distribution registry, not a deploy target).

```yaml
- uses: actions/checkout@v6
- uses: quiltdata/gh-actions/fargate-deploy-ecr@main
  with:
    image-name: quiltdata/services/foo
    cluster-name: my-cluster
    service-name: my-service
    push-targets: ${{ inputs.push-targets || '["prod","govcloud"]' }}
```

### [lambda-deploy-ecr](./lambda-deploy-ecr)

Legacy lambda image build + push. Pushes to all enabled regions per account
(needed because Lambda functions are region-scoped). Kept for back-compat;
new lambda workflows can use `build-and-push-ecr` if multi-region push is
not required.

### [lambda-upload-s3](./lambda-upload-s3)

Build a lambda zip via the lambda builder image and upload to S3.

## Conventions

- All ECR-pushing actions assume the consumer repo has an IAM role at
  `arn:aws:iam::<account>:role/github/GitHub-<role-name>` (and the GovCloud
  equivalent), where `<role-name>` defaults to the repo name and can be
  overridden via the `role-name` input.
- The `push-targets` JSON-array pattern — default `["prod","govcloud"]` for
  push events, `["prod"]` or `[]` for `workflow_dispatch` — is the org
  convention for letting `workflow_dispatch` produce dev images without
  pushing to release-channel registries (Marketplace, GovCloud).
- Callers are responsible for `actions/checkout` before calling
  `build-and-push-ecr` or `fargate-deploy-ecr` (so a pre-build step like
  `npm run build` can populate the workspace first). The legacy
  `lambda-deploy-ecr` does its own checkout.

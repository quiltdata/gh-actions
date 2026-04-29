#!/usr/bin/env bash

set -euo pipefail

: "${REGISTRY:?REGISTRY is required}"
: "${IMAGE_NAME:?IMAGE_NAME is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"

ACCOUNT_ID="${REGISTRY%%.*}"
SOURCE="${SOURCE_IMAGE:-$IMAGE_NAME:$IMAGE_TAG}"
MULTI_REGION="${MULTI_REGION:-false}"
ADDITIONAL_TAGS="${ADDITIONAL_TAGS:-[]}"

additional_tags() {
  node -e '
    const input = process.env.ADDITIONAL_TAGS || "[]";
    const tags = JSON.parse(input);
    if (!Array.isArray(tags)) {
      throw new Error("ADDITIONAL_TAGS must be a JSON array");
    }
    for (const tag of tags) {
      if (typeof tag !== "string" || tag.length === 0) {
        throw new Error("ADDITIONAL_TAGS entries must be non-empty strings");
      }
      console.log(tag);
    }
  '
}

push_to_region() {
  local region="$1"
  local docker_url="$ACCOUNT_ID.dkr.ecr.$region.amazonaws.com"
  local remote="$docker_url/$IMAGE_NAME:$IMAGE_TAG"

  echo "Logging in to $docker_url..."
  aws ecr get-login-password --region "$region" |
    docker login -u AWS --password-stdin "$docker_url"

  echo "Pushing $SOURCE to $remote..."
  docker tag "$SOURCE" "$remote"
  docker push "$remote"
  echo "uri=$remote" >> "$GITHUB_OUTPUT"

  local tags
  tags="$(additional_tags)"
  while IFS= read -r tag; do
    if [ -z "$tag" ]; then
      continue
    fi
    local additional_remote="$docker_url/$IMAGE_NAME:$tag"
    echo "Pushing $SOURCE to $additional_remote..."
    docker tag "$SOURCE" "$additional_remote"
    docker push "$additional_remote"
  done <<< "$tags"
}

if [ "$MULTI_REGION" = "true" ]; then
  regions="$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)"
  for region in $regions; do
    push_to_region "$region"
  done
else
  region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  if [ -z "$region" ]; then
    echo "::error::AWS_REGION or AWS_DEFAULT_REGION is required for single-region push"
    exit 1
  fi
  push_to_region "$region"
fi

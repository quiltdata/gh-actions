#!/bin/bash

set -e

error() {
    echo "$@" >&2
    exit 1
}

[[ $# == 3 ]] || error "Usage: $0 account_id image_name regions"

account_id=$1
image_name=$2
regions=$3

# Convert comma-separated regions to array
IFS=',' read -ra region_array <<< "$regions"

for region in "${region_array[@]}"
do
    region=$(echo "$region" | xargs)  # trim whitespace
    docker_url=$account_id.dkr.ecr.$region.amazonaws.com

    echo "Logging in to $docker_url..."
    aws ecr get-login-password --region "$region" | \
      docker login -u AWS --password-stdin "$docker_url"

    echo "Ensuring ECR repository exists in $region..."
    aws ecr describe-repositories \
      --repository-names "$(echo $image_name | cut -d: -f1)" \
      --region "$region" 2>/dev/null || \
    aws ecr create-repository \
      --repository-name "$(echo $image_name | cut -d: -f1)" \
      --region "$region"

    echo "Pushing to $region..."
    remote_image_name="$docker_url/$image_name"
    docker tag "$image_name" "$remote_image_name"
    docker push "$remote_image_name"

    echo "Successfully pushed to $remote_image_name"
done

echo ""
echo "All regions completed successfully!"

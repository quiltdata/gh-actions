#!/bin/bash

set -e

error() {
    echo $@ 2>&1
    exit 1
}

[[ $# == 4 || $# == 5 ]] || error "Usage: $0 zip_file lambda_name hash region [tag_prefix]"

zip_file=$1
lambda_name=$2
hash=$3
primary_region=$4
tag_prefix=${5:-}

# Restrict tag_prefix to a safe character set so it stays within the
# filename segment of the S3 key — e.g. `/` would change the effective
# key path, landing artifacts at `<name>/dev/<sha>.zip` instead of
# `<name>/dev-<sha>.zip`. `*` (vs `+`) lets the empty default pass.
if [[ ! "$tag_prefix" =~ ^[A-Za-z0-9._-]*$ ]]; then
    error "tag_prefix must match [A-Za-z0-9._-]* (got: '$tag_prefix')"
fi

s3_key="$lambda_name/${tag_prefix}${hash}.zip"

regions=$(aws ec2 describe-regions --query "Regions[].{Name:RegionName}" --output text)

echo "Uploading to $primary_region..."
aws s3 cp --acl public-read "$zip_file" --region "$primary_region" "s3://quilt-lambda-$primary_region/$s3_key"

for region in $regions
do
    if [[ $region != $primary_region ]]
    then
        echo "Copying to $region..."
        aws s3 cp --acl public-read \
            --source-region "$primary_region" --region "$region" \
            "s3://quilt-lambda-$primary_region/$s3_key" "s3://quilt-lambda-$region/$s3_key"
    fi
done

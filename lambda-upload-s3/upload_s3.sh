#!/bin/bash

set -e

error() {
    echo $@ 2>&1
    exit 1
}

[[ $# == 3 ]] || error "Usage: $0 zip_file lambda_name hash region"

zip_file=$1
lambda_name=$2
hash=$3
primary_region=$4

s3_key="$lambda_name/$hash.zip"

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

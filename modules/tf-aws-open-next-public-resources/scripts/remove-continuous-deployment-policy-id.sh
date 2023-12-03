#!/bin/bash

set -e

ETAG=$(aws cloudfront get-distribution --id $CDN_PRODUCTION_ID --query 'ETag' --output text)

aws cloudfront get-distribution --id $CDN_PRODUCTION_ID | \
    jq '.Distribution.DistributionConfig.ContinuousDeploymentPolicyId=""' | \
    jq .Distribution.DistributionConfig > config.json
aws cloudfront update-distribution --id $CDN_PRODUCTION_ID --distribution-config "file://config.json" --if-match $ETAG > /dev/null

rm config.json

DESIRED_STATE="Deployed"
INTERVAL=60

while true; do
    STATUS=$(aws cloudfront get-distribution --id $CDN_PRODUCTION_ID --query 'Distribution.Status' --output text)

    if [ "$STATUS" == "$DESIRED_STATE" ]; then
        echo "Distribution $CDN_PRODUCTION_ID reached state $DESIRED_STATE."
        break
    else
        echo "Current status of $CDN_PRODUCTION_ID is $STATUS. Waiting for $DESIRED_STATE..."
    fi

    sleep $INTERVAL
done

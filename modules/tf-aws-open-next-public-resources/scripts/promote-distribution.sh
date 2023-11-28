#!/bin/bash

set -e

aws cloudfront update-distribution-with-staging-config --id $CDN_PRODUCTION_ID --staging-distribution-id $CDN_STAGING_ID --if-match "$CDN_PRODUCTION_ETAG,$CDN_STAGING_ETAG" > /dev/null

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


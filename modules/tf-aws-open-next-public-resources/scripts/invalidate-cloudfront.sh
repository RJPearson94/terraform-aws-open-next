#!/bin/bash

set -e

INVALIDATION_ID=$(aws cloudfront create-invalidation --distribution-id $CDN_ID --paths "/*" --query 'Invalidation.Id' --output text)
DESIRED_STATE="Completed"
INTERVAL=30

while true; do
    STATUS=$(aws cloudfront get-invalidation --id $INVALIDATION_ID --distribution-id $CDN_ID --query 'Invalidation.Status' --output text)

    if [ "$STATUS" == "$DESIRED_STATE" ]; then
        echo "Distribution $CDN_ID reached state $DESIRED_STATE."
        break
    else
        echo "Current status of $CDN_ID is $STATUS. Waiting for $DESIRED_STATE..."
    fi

    sleep $INTERVAL
done

ETAG=$(aws cloudfront get-distribution --id $CDN_ID --query 'ETag' --output text)
echo "{\"etag\": $ETAG}"
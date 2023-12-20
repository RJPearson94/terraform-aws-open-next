#!/bin/bash

## Setup

set -e

## Validation

exitcode=0

if [ ! -x "$(command -v aws)" ]; then
   exitcode=1
   echo "Error: AWS CLI not found. See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install the CLI"
fi

if [ -z $CDN_ID ]; then
   exitcode=1
   echo "Error: CDN ID was not supplied"
fi

if [ $exitcode -ne 0 ]; then
   exit $exitcode
fi

## Script

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
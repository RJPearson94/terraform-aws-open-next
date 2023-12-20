#!/bin/bash

## Setup

set -e

## Validation

exitcode=0

if [ ! -x "$(command -v aws)" ]; then
   exitcode=1
   echo "Error: AWS CLI not found. See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install the CLI"
fi

if [ -z $CDN_PRODUCTION_ID ]; then
   exitcode=1
   echo "Error: production CDN ID was not supplied"
fi

if [ -z $CDN_STAGING_ID ]; then
   exitcode=1
   echo "Error: staging CDN ID was not supplied"
fi

if [ -z $CDN_PRODUCTION_ETAG ]; then
   exitcode=1
   echo "Error: production CDN ETag was not supplied"
fi

if [ -z $CDN_STAGING_ETAG ]; then
   exitcode=1
   echo "Error: staging CDN ETag was not supplied"
fi

if [ $exitcode -ne 0 ]; then
   exit $exitcode
fi

## Script

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

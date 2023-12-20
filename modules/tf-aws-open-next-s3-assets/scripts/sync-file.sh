#!/bin/bash

## Setup

set -e

## Validation

exitcode=0

if [ ! -x "$(command -v aws)" ]; then
   exitcode=1
   echo "Error: AWS CLI not found. See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install the CLI"
fi

if [ -z $SOURCE ]; then 
   exitcode=1
   echo "Error: source was not supplied"
fi

if [ -z $BUCKET_NAME ]; then
   exitcode=1
   echo "Error: bucket name was not supplied"
fi

if [ -z $KEY ]; then
   exitcode=1
   echo "Error: key was not supplied"
fi

if [[ -z $CONTENT_TYPE ]]; then 
   exitcode=1
   echo "Error: content type was not supplied"
fi

if [ $exitcode -ne 0 ]; then
   exit $exitcode
fi

## Script

if [ -z "$CACHE_CONTROL" ]
then 
    aws s3 cp $SOURCE s3://$BUCKET_NAME/$KEY --cache-control "$CACHE_CONTROL" --content-type "$CONTENT_TYPE"
else 
    aws s3 cp $SOURCE s3://$BUCKET_NAME/$KEY --content-type "$CONTENT_TYPE"
fi

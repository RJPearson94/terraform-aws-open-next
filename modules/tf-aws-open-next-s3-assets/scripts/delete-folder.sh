#!/bin/bash

## Setup

set -e

## Validation

exitcode=0

if [ ! -x "$(command -v aws)" ]; then
   exitcode=1
   echo "Error: AWS CLI not found. See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install the CLI"
fi

if [ -z $BUCKET_NAME ]; then
   exitcode=1
   echo "Error: bucket name was not supplied"
fi

if [ -z $FOLDER ]; then
   exitcode=1
   echo "Error: folder was not supplied"
fi

if [ $exitcode -ne 0 ]; then
   exit $exitcode
fi

## Script

aws s3 rm s3://$BUCKET_NAME/$FOLDER/*
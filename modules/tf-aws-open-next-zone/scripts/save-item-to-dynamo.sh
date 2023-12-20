#!/bin/bash

## Setup

set -e

## Validation

exitcode=0

if [ ! -x "$(command -v aws)" ]; then
   exitcode=1
   echo "Error: AWS CLI not found. See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install the CLI"
fi

if [ -z $TABLE_NAME ]; then
   exitcode=1
   echo "Error: table name was not supplied"
fi

if [ -z $ITEM ]; then
   exitcode=1
   echo "Error: item was not supplied"
fi

if [ $exitcode -ne 0 ]; then
   exit $exitcode
fi

## Script

aws dynamodb put-item --table-name $TABLE_NAME --item $ITEM
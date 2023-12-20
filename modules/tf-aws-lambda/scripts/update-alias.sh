#!/bin/bash

## Setup

set -e

## Validation

exitcode=0

if [ ! -x "$(command -v aws)" ]; then
   exitcode=1
   echo "Error: AWS CLI not found. See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install the CLI"
fi

if [ -z $FUNCTION_NAME ]; then
   exitcode=1
   echo "Error: function name was not supplied"
fi

if [ -z $FUNCTION_ALIAS ]; then
   exitcode=1
   echo "Error: function alias was not supplied"
fi

if [ -z $FUNCTION_VERSION ]; then
   exitcode=1
   echo "Error: function version was not supplied"
fi

if [ $exitcode -ne 0 ]; then
   exit $exitcode
fi

## Script

aws lambda update-alias --function-name $FUNCTION_NAME --name $FUNCTION_ALIAS --function-version $FUNCTION_VERSION

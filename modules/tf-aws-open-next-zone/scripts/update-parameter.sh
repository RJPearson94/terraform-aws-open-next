#!/bin/bash

## Setup

set -e

## Validation

exitcode=0

if [ ! -x "$(command -v aws)" ]; then
   exitcode=1
   echo "Error: AWS CLI not found. See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html to install the CLI"
fi

if [ -z $PARAMETER_NAME ]; then
   exitcode=1
   echo "Error: parameter name was not supplied"
fi

if [ -z $VALUE ]; then
   exitcode=1
   echo "Error: value was not supplied"
fi

if [ $exitcode -ne 0 ]; then
   exit $exitcode
fi

## Script

aws ssm put-parameter --name $PARAMETER_NAME --value $VALUE --overwrite
#!/bin/bash

set -e

aws lambda update-alias --function-name $FUNCTION_NAME --name $FUNCTION_ALIAS --function-version $FUNCTION_VERSION

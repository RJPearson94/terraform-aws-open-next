#!/bin/bash

set -e

aws ssm put-parameter --name $PARAMETER_NAME --value $VALUE --overwrite
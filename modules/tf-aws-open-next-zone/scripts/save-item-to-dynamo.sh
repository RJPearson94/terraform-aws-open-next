#!/bin/bash

set -e

aws dynamodb put-item --table-name $TABLE_NAME --item $ITEM
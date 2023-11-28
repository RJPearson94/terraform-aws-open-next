#!/bin/bash

set -e

if [ -z "$CACHE_CONTROL" ]
then 
    aws s3 cp $SOURCE s3://$BUCKET_NAME/$KEY --cache-control "$CACHE_CONTROL" --content-type "$CONTENT_TYPE"
else 
    aws s3 cp $SOURCE s3://$BUCKET_NAME/$KEY --content-type "$CONTENT_TYPE"
fi

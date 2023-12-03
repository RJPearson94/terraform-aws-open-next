#!/bin/bash

INVALIDATION_ID=$(aws cloudfront create-invalidation --distribution-id $CDN_ID --paths "/*" | jq -r '.Invalidation.Id')
wait_for_invalidation() {
    while [ $(aws cloudfront get-invalidation --id $INVALIDATION_ID --distribution-id $CDN_ID | jq -r '.Invalidation.Status') != "Completed" ]
    do
        aws cloudfront wait invalidation-completed --distribution-id $CDN_ID --id $INVALIDATION_ID                       
    done
        echo "Invalidation Cache Complete";  
}
wait_for_invalidation
aws cloudfront wait distribution-deployed --id $CDN_ID
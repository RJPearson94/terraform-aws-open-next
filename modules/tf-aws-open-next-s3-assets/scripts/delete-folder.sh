#!/bin/bash

set -e

aws s3 rm s3://$BUCKET_NAME/$FOLDER/*

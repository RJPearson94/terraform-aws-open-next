/**
 * adapted from https://github.com/aws-samples/aws-lambda-function-url-secured/blob/main/src/functions/auth/auth.js to use v3 of the aws js sdk
 * blog https://aws.amazon.com/blogs/compute/protecting-an-aws-lambda-function-url-with-amazon-cloudfront-and-lambdaedge/
 *
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: MIT-0
 */
const { createHash, createHmac } = require('crypto');
const { defaultProvider } = require('@aws-sdk/credential-provider-node');
const { HttpRequest } = require("@aws-sdk/protocol-http");
const { SignatureV4 } = require("@aws-sdk/signature-v4");

/**
 * Credit to msaphire on this solution to workaround for the @aws-crypto/sha256-js library not being included https://github.com/aws/aws-sdk-js-v3/issues/3590#issuecomment-1531763656
 */
class Sha256 {
  hash;

  constructor(secret) {
      this.hash = secret ? createHmac('sha256', secret) : createHash('sha256');
  }
  update(array) {
      this.hash.update(array);
  }
  digest() {
      const buffer = this.hash.digest();
      return Promise.resolve(new Uint8Array(buffer.buffer));
  }
}

exports.handler = async (event) => {
  const request = event.Records[0].cf.request;
  const headers = request.headers;

  delete headers["x-forwarded-for"];

  if (!request.origin.custom) {
    throw new Error(`Unexpected origin type. Expected 'custom'. Got: ${JSON.stringify(request.origin)}`);
  }

  const host = request.headers["host"][0].value;
  const region = host.split(".")[2];

  // Parse the query string into an object for proper handling by SignatureV4
  const queryParams = {};
  if (request.querystring) {
    const searchParams = new URLSearchParams(request.querystring);
    for (const [key, value] of searchParams.entries()) {
      if (queryParams[key] === undefined) {
        // First occurrence of this key
        queryParams[key] = value;
      } else if (Array.isArray(queryParams[key])) {
        // Already an array, just push
        queryParams[key].push(value);
      } else {
        // Second occurrence, convert to array
        queryParams[key] = [queryParams[key], value];
      }
    }
  }

  const req = new HttpRequest({
    method: request.method,
    protocol: "https:",
    hostname: host,
    path: request.uri,
    query: queryParams,
    headers: Object.values(headers).map(headers => headers[0]).reduce((previousValue, newValue) => ({ ...previousValue, ...{ [newValue.key]: newValue.value } }), {}),
    body: request.body ? Buffer.from(request.body.data, request.body.encoding) : undefined,
  });

  const signer = new SignatureV4({ credentials: defaultProvider(), region, service: 'lambda', sha256: Sha256 });
  const signedRequest = await signer.sign(req);

  for (const [key, value] of Object.entries(signedRequest.headers)) {
    request.headers[key.toLowerCase()] = [{ key, value }];
  }

  return request;
};
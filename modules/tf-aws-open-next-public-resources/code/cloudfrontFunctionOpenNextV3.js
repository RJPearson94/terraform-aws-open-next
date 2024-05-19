// Adapted from the sst CDK construct https://github.com/sst/sst/blob/1e9a23a61ecdaf96651db9be8af45089eca13fd3/packages/sst/src/constructs/NextjsSite.ts
// Copyright (c) 2020 SST
// SPDX-License-Identifier: MIT

function handler(event) {
  var request = event.request;

  request.headers["x-forwarded-host"] = request.headers.host;

  function getHeader(key) {
    var header = request.headers[key];
    if (header) {
      if (header.multiValue) {
        return header.multiValue.map((header) => header.value).join(",");
      }
      if (header.value) {
        return header.value;
      }
    }
    return "";
  }

  var cacheKey = "";
  if (request.uri.includes("/_next/image")) {
    cacheKey = getHeader("accept");
  } else {
    cacheKey =
      getHeader("rsc") +
      getHeader("next-router-prefetch") +
      getHeader("next-router-state-tree") +
      getHeader("next-url") +
      getHeader("x-prerender-revalidate");
  }
  if (request.cookies["__prerender_bypass"]) {
    cacheKey += request.cookies["__prerender_bypass"]
      ? request.cookies["__prerender_bypass"].value
      : "";
  }

  var crypto = require("crypto");
  var hashedKey = crypto.createHash("md5").update(cacheKey).digest("hex");
  request.headers["x-open-next-cache-key"] = { value: hashedKey };

  if (request.headers["cloudfront-viewer-city"]) {
    request.headers["x-open-next-city"] =
      request.headers["cloudfront-viewer-city"];
  }
  if (request.headers["cloudfront-viewer-country"]) {
    request.headers["x-open-next-country"] =
      request.headers["cloudfront-viewer-country"];
  }
  if (request.headers["cloudfront-viewer-region"]) {
    request.headers["x-open-next-region"] =
      request.headers["cloudfront-viewer-region"];
  }
  if (request.headers["cloudfront-viewer-latitude"]) {
    request.headers["x-open-next-latitude"] =
      request.headers["cloudfront-viewer-latitude"];
  }
  if (request.headers["cloudfront-viewer-longitude"]) {
    request.headers["x-open-next-longitude"] =
      request.headers["cloudfront-viewer-longitude"];
  }

  return request;
}

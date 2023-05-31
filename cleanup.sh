#!/bin/bash

# This script runs after the completion of the pipeline
# $1 contains the repo name
# $2 contains the tag

echo "[Cleanup]: Removing $1:$2 from registry..."
response=$(curl -sS -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -o /dev/null -w '%{http_code}\n%header{Docker-Content-Digest}' localhost:5000/v2/$1/manifests/$2)
http_code=$(head -n1 <<< "$response")
manifest_digest=$(tail -n1 <<< "$response")

if [[ "$http_code" -ne 200 ]] ; then
  echo "[Cleanup]: Error: Could not fetch manifest"
  exit 1
fi

echo "[Cleanup]: Removing manifest $manifest_digest"

response=$(curl -sS -w '%{http_code}' -X DELETE localhost:5000/v2/$1/manifests/$manifest_digest)
http_code=$(head -n1 <<< "$response")

if [[ "$http_code" -ne 202 ]] ; then
  echo "[Cleanup]: Error: Could not remove manifest $manifest_digest"
  exit 1
fi

echo "[Cleanup]: Removed manifest $manifest_digest"

echo "[Cleanup]: Running garbage-collect"
registry garbage-collect --delete-untagged /etc/docker/registry/config.yml

echo "[Cleanup]: Finished"
exit 0
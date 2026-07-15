#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DUMP_DIR="/tmp/mongodump-$TIMESTAMP"
ARCHIVE_PATH="/tmp/mongo-backup-$TIMESTAMP.tar.gz"
BLOB_NAME="mongo-backup-$TIMESTAMP.tar.gz"

mongodump \
  --db appdb \
  --username "${db_app_username}" \
  --password "${db_app_password}" \
  --authenticationDatabase appdb \
  --out "$DUMP_DIR"

tar -czf "$ARCHIVE_PATH" -C "$DUMP_DIR" .

# Ask the Instance Metadata Service for a token for this VM's managed
# identity, scoped to Blob Storage. No stored key, no secret on disk.
ACCESS_TOKEN=$(curl -s -H "Metadata:true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2021-02-01&resource=https://storage.azure.com/" \
  | python3 -c 'import sys, json; print(json.load(sys.stdin)["access_token"])')

curl -s -X PUT \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "x-ms-version: 2021-08-06" \
  -H "x-ms-blob-type: BlockBlob" \
  -H "Content-Length: $(stat -c%s "$ARCHIVE_PATH")" \
  --data-binary @"$ARCHIVE_PATH" \
  "https://${storage_account_name}.blob.core.windows.net/${container_name}/$BLOB_NAME"

rm -rf "$DUMP_DIR" "$ARCHIVE_PATH"

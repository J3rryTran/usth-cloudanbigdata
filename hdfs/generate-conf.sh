#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

set -a
source .env
set +a

: "${TS_IP:?TS_IP is required}"

envsubst '${TS_IP}' \
  < conf/hdfs-site.xml.template \
  > conf/hdfs-site.xml

envsubst '${TS_IP}' \
  < conf/core-site.xml.template \
  > conf/core-site.xml

echo "HDFS configuration generated successfully."
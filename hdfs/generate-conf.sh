#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ -f .env ]]; then
  source .env
fi

: "${MASTER_TS_IP:?Set MASTER_TS_IP in hdfs/.env}"
HDFS_REPLICATION=${HDFS_REPLICATION:-2}
if [[ ! $MASTER_TS_IP =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || ! $HDFS_REPLICATION =~ ^[1-9][0-9]*$ ]]; then
  echo "Set MASTER_TS_IP to an IPv4 address and HDFS_REPLICATION to a positive integer." >&2
  exit 1
fi

for site in core-site hdfs-site; do
  xml=$(<"conf/$site.xml.template")
  xml=${xml//\$\{MASTER_TS_IP\}/$MASTER_TS_IP}
  xml=${xml//\$\{HDFS_REPLICATION\}/$HDFS_REPLICATION}
  printf '%s\n' "$xml" > "conf/$site.xml"
done

echo "HDFS client configuration generated successfully."

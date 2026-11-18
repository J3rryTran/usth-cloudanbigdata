# HDFS

Generate file .xml first
run
```bash
bash generate-conf.sh
```

And then create .env
```
TS_IP=<tailscale_ip>
```
## Start

**Master node:**

```bash
docker compose -f compose-master.yaml build

# Run only once for a new, empty HDFS cluster
docker compose -f compose-master.yaml run --rm --no-deps namenode hdfs namenode -format

docker compose -f compose-master.yaml up -d
```

**Worker node:**

```bash
docker compose -f compose-worker.yaml up -d --build
```

> Do not format an existing NameNode.

## Verify

```bash
docker compose -f compose-master.yaml exec namenode hdfs dfsadmin -report
docker compose -f compose-master.yaml exec namenode hdfs dfs -ls /
```

## Run
```bash
docker compose -f compose-master.yaml up
# or
docker compose -f compose-worker.yaml up
```

## Stop

Run on each respective host:

```bash
docker compose -f compose-master.yaml down
# or
docker compose -f compose-worker.yaml down
```

## Check
```bash
docker compose -f compose-master.yaml ps
```

Persistent storage is retained by the configured bind mounts.

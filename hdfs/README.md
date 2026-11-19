# HDFS

## Single-host setup on Linux

From the `hdfs` directory, start one NameNode and one DataNode with Docker Compose.

```bash
docker compose -f compose-local.yaml up -d --build
```

Allow a few seconds for the NameNode to start and the DataNode to register, then
check the cluster.

```bash
docker compose -f compose-local.yaml exec namenode hdfs dfsadmin -report
docker compose -f compose-local.yaml exec namenode hdfs dfs -ls /
```

Once the report shows `Live datanodes (1)`, applications running directly on the
host can connect to `hdfs://127.0.0.1:9000`. The NameNode UI is at
`http://127.0.0.1:9870`. The cluster uses one replica and binds to loopback.

Docker stores data in named volumes. The NameNode initializes its storage on
first startup. Stop the cluster with `docker compose -f compose-local.yaml down`
and use the same `up` command to restart it with the existing data.

## Multi-host setup over Tailscale

Generate file .xml first
run
```bash
bash generate-conf.sh
```

And then create .env
```
TS_IP=<tailscale_ip>
```
### Start

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

### Verify

```bash
docker compose -f compose-master.yaml exec namenode hdfs dfsadmin -report
docker compose -f compose-master.yaml exec namenode hdfs dfs -ls /
```

### Run
```bash
docker compose -f compose-master.yaml up
# or
docker compose -f compose-worker.yaml up
```

### Stop

Run on each respective host:

```bash
docker compose -f compose-master.yaml down
# or
docker compose -f compose-worker.yaml down
```

### Check
```bash
docker compose -f compose-master.yaml ps
```

Persistent storage is retained by the configured bind mounts.

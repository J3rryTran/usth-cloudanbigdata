# HDFS

## Single-host setup on Linux

From the `hdfs` directory, start one NameNode and one DataNode with Docker Compose.
Without a `MASTER_TS_IP` setting in the environment or `hdfs/.env`, it binds to loopback.

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

Run the commands from the repository root. Use Docker Compose v2.20 or later.

On the **master**, create or update `hdfs/.env`. Use its own Tailscale IP.

```dotenv
MASTER_TS_IP=100.116.4.96
HDFS_REPLICATION=2
```

```bash
bash hdfs/generate-conf.sh
docker compose -f hdfs/compose-master.yaml up -d
```

This starts the NameNode and a local DataNode with the same volumes as the single-host setup. To keep using an existing namespace, run it with the same Compose project name and preserve the NameNode and DataNode volumes. A fresh NameNode volume is initialized automatically.

On **each worker**, create or update `hdfs/.env` with the same master IP and the worker's own address from `tailscale ip -4`.

```dotenv
MASTER_TS_IP=100.116.4.96
NODE_TS_IP=<this-worker-tailscale-ip>
HDFS_REPLICATION=2
```

Start the worker after the master is up.

```bash
bash hdfs/generate-conf.sh
docker compose -f hdfs/compose-worker.yaml up -d --build
```

The NameNode RPC port is `9000`, and the NameNode UI is on `9870`. DataNodes and HDFS clients need to reach each advertised DataNode on TCP `9866`. The worker uses its local address for its DataNode listener and the master address for NameNode RPC.

### Verify and set the storage quota

From the master, check that both remote DataNodes and the local DataNode are live. Apply the quota once to a new cluster after the NameNode leaves safe mode.

```bash
docker compose -f hdfs/compose-master.yaml exec -T namenode hdfs dfsadmin -report -live
docker compose -f hdfs/compose-master.yaml exec -T namenode hdfs dfsadmin -setSpaceQuota 20000000000 /
docker compose -f hdfs/compose-master.yaml exec -T namenode hdfs dfs -count -q /
```

The root HDFS quota caps file data at **20 GB including replicas** and persists in the NameNode volume. With two replicas, it allows roughly 10 GB of logical file data. It covers Spark event logs stored in HDFS. Docker images, NameNode metadata, and container logs use host storage outside the HDFS quota.

Each HDFS container has a 512 MiB RAM limit with swap disabled. Docker rotates its logs.

### Stop

Run on each respective host:

```bash
docker compose -f hdfs/compose-master.yaml down
# or
docker compose -f hdfs/compose-worker.yaml down
```

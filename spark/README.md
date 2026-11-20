# Spark over Tailscale

Start HDFS first and generate its client configuration on each machine using the [HDFS setup](../hdfs/README.md). The Spark Compose files read the same `hdfs/.env` when invoked with `--env-file`. Run the following commands from the repository root.

The Spark image build expects the Spark 4.2.1 Hadoop 3 distribution extracted to `spark/lib/spark-4.2.1-bin-hadoop3/`. Prepare that directory on each host that builds the image, or transfer the built `usth-cloudandbigdata:spark-4.2.1` image and use `--no-build`.

## Start the master

```bash
docker compose --env-file hdfs/.env -f spark/compose-spark-master.yaml up -d --build
docker compose --env-file hdfs/.env -f spark/compose-spark-master.yaml ps
```

The Spark master URL is `spark://100.116.4.96:7077`. The master UI is at `http://100.116.4.96:8082`.

## Start each remote worker

```bash
docker compose --env-file hdfs/.env -f spark/compose-spark-worker.yaml up -d --build
docker compose --env-file hdfs/.env -f spark/compose-spark-worker.yaml logs --tail=30 spark-worker
```

Confirm both workers appear in the master UI. Each worker binds to its `NODE_TS_IP` and registers with Spark at `MASTER_TS_IP`. For jobs submitted from the master, workers must be able to reach the driver on TCP `39000` and `39001`. Spark executors use TCP `39002` for block transfers.

## Run the smoke test

On the master, create the HDFS directories once and grant the container's `root` user access. Use the dedicated test directory because the sample job overwrites `/spark-test/output`.

```bash
docker compose -f hdfs/compose-master.yaml exec -T namenode hdfs dfs -mkdir -p /spark-events /spark-test
docker compose -f hdfs/compose-master.yaml exec -T namenode hdfs dfs -chown root /spark-events /spark-test
docker compose --env-file hdfs/.env -f spark/compose-spark-master.yaml run --rm spark-client \
  spark-submit --master spark://100.116.4.96:7077 /opt/spark/jobs/test.py
```

## Resource limits

| Host | Container limits | Sum of container limits |
| --- | --- | --- |
| Master | 512 MiB NameNode, 512 MiB DataNode, 384 MiB Spark master | 1,408 MiB |
| Master running one Spark client | Same services plus a 640 MiB Spark client | 2,048 MiB |
| Each worker | 512 MiB DataNode and 1,536 MiB Spark worker | 2,048 MiB |

Docker enforces these limits with swap disabled. Spark reserves one core and a 512 MiB executor heap per worker. Spark scratch and work files use bounded temporary filesystems, and Docker rotates service logs. Large jobs can exhaust these limits even if there is room in HDFS.

For a shared cap of exactly 2 GB per host, install the resource slice on hosts using cgroup v2 with Docker's `systemd` cgroup driver. Both HDFS and Spark use the same slice, including one-off `spark-client` containers.

```bash
sudo install -m 644 usthcluster.slice /etc/systemd/system/usthcluster.slice
sudo systemctl daemon-reload
sudo systemctl start usthcluster.slice
```

Add `USTH_CGROUP_PARENT=usthcluster.slice` to `hdfs/.env` and run the Compose startup commands again to place the containers in the slice. Check the shared cap with `systemctl show usthcluster.slice -p MemoryMax -p MemorySwapMax`.

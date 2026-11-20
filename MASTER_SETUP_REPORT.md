# USTH master node setup report

20 November 2026

The Linux master runs Hadoop 3.5.0 HDFS and Spark 4.2.1 Standalone in Docker Compose. The NameNode, local DataNode, and Spark Master listen on the master's Tailscale address, `100.116.4.96`. The project containers on the master share a 2 GB RAM cap, and HDFS has a 20 GB storage quota. A Spark job completed against HDFS using a temporary worker on the master. Both remote workers still need to register and pass the same test from their own hosts.

## Initial connectivity diagnosis

The worker reported that SSH on port `22` was open while `9000`, `9870`, `7077`, and `8080` returned `Connection refused`. Tests from the master against its own Tailscale IP reproduced all four refusals. `ss` showed that the NameNode RPC and web UI listened on `127.0.0.1`. HDFS itself reported one live local DataNode. No Spark Master was running, and another Docker service already used `127.0.0.1:8080`.

## Tailscale and service addresses

Tailscale was already running and the master was enrolled in the tailnet. `tailscale ip -4` and `ip -4 addr show dev tailscale0` confirmed `100.116.4.96`. During diagnosis, `tailscale ping` reached the one visible peer through a DERP relay. Peer reachability and application port reachability were tested separately. For a fresh Linux host, install Tailscale, enroll it in the same tailnet, and run `tailscale status` and `tailscale ip -4` before starting Compose. [Tailscale Linux setup](https://tailscale.com/docs/install/linux) · [Tailscale TCP troubleshooting](https://tailscale.com/docs/reference/troubleshooting/network-configuration/tcp-connection-two-devices)

The HDFS and Spark services use host networking and bind to the configured Tailscale IP. `MASTER_TS_IP` is the shared destination for HDFS and Spark. Each remote worker sets `NODE_TS_IP` to its own Tailscale address so other machines can reach that worker's DataNode and Spark process. A single `TS_IP` setting previously served both roles and could point a worker to itself or cause it to bind to an address it did not own.

| Service on the master | Tailnet endpoint |
| --- | --- |
| HDFS NameNode RPC | `hdfs://100.116.4.96:9000` |
| HDFS NameNode UI | `http://100.116.4.96:9870` |
| Local DataNode block transfer | `100.116.4.96:9866` |
| Local DataNode HTTP and IPC | `100.116.4.96:9864` and `100.116.4.96:9867` |
| Spark Standalone Master RPC | `spark://100.116.4.96:7077` |
| Spark Master UI | `http://100.116.4.96:8082` |

## Master deployment

1. The master kept the Compose project name `usth-hdfs-local`, so the switch from loopback reused the existing NameNode and DataNode volumes. The NameNode's cluster ID matched before and after the restart. The local DataNode then registered at its Tailscale address. [Master Compose file](hdfs/compose-master.yaml) · [HDFS service definitions](hdfs/compose-local.yaml)
2. The master uses `MASTER_TS_IP=100.116.4.96`, `HDFS_REPLICATION=2`, and `USTH_CGROUP_PARENT=usthcluster.slice` in its local `hdfs/.env`. The configuration script generates `core-site.xml` and `hdfs-site.xml` for Spark's HDFS client. The environment file and generated XML are local deployment files covered by `.gitignore`. [HDFS setup](hdfs/README.md)
3. Spark was built from the Spark 4.2.1 Hadoop 3 distribution. The master UI uses `8082` because `8080` was occupied. HDFS directories `/spark-events` and `/spark-test` were created and assigned to the user that runs the Spark client container. [Spark setup](spark/README.md)

With the images available and the memory slice installed, these commands recreate the configured master services from the repository root.

```bash
bash hdfs/generate-conf.sh
docker compose -f hdfs/compose-master.yaml up -d --no-build
docker compose --env-file hdfs/.env -f spark/compose-spark-master.yaml up -d --no-build
```

## Storage and RAM limits

The NameNode enforces a space quota of `20,000,000,000` bytes on `/`. The quota applies across all DataNodes and counts replicas, so replication by two leaves about 10 GB for logical file contents. Spark event logs also count toward the quota. Docker images, container logs, and NameNode metadata use host storage outside the HDFS quota. The quota persists with the NameNode volume and can be checked with `hdfs dfs -count -q /`. [HDFS quota guide](https://hadoop.apache.org/docs/r3.5.0/hadoop-project-dist/hadoop-hdfs/HdfsQuotaAdminGuide.html)

The master has Docker's `systemd` cgroup driver and cgroup v2. The installed `usthcluster.slice` sets `MemoryMax=2000000000` and `MemorySwapMax=0` for the project's containers, including one-off Spark clients. Docker also caps the NameNode and local DataNode at 512 MiB each, the Spark Master at 384 MiB, and each Spark client at 640 MiB. The remote worker configuration assigns 512 MiB to its DataNode and 1,536 MiB to its Spark worker. Installing the same slice on a compatible worker gives that worker a shared 2 GB cap. Spark scratch space uses bounded temporary filesystems, and Docker rotates service logs. [Memory slice](usthcluster.slice) · [Resource setup](spark/README.md#resource-limits)

## Verification and worker status

| Check | Result |
| --- | --- |
| Master TCP and HTTP | The master accepted TCP on `9000`, `9870`, `9866`, `7077`, and `8082` at its Tailscale IP. Both web UIs returned HTTP 200. |
| HDFS quota | The root quota remained at 20 GB after restart. A write that exceeded a smaller temporary directory quota was rejected. |
| HDFS worker configuration | A temporary DataNode with its own loopback address registered with an isolated NameNode and passed a file write and read. |
| Spark and HDFS | A temporary Spark worker registered with the deployed master. The submitted job processed 100,000 records and read back all 100,000 from Parquet in HDFS. |
| Master memory | The three running service containers were in `usthcluster.slice`, with the shared memory and swap limits confirmed on the host. |

As of 20 November, the deployed master reported one live DataNode and zero live Spark workers. Only one remote peer was visible to the master during troubleshooting, and its SSH port refused the connection. On each remote machine, use the updated Compose files, set its `NODE_TS_IP`, and start the HDFS and Spark workers. Verify three live DataNodes including the master's local DataNode, two live Spark workers, and a successful distributed read and write. [HDFS worker setup](hdfs/README.md#multi-host-setup-over-tailscale) · [Spark worker setup](spark/README.md#start-each-remote-worker)

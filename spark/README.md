# Build Spark Docker Image

Build the Spark image locally for the USTH Spark Standalone cluster. A Docker Hub login is **not required**.

## 1. Build the image on the Master

Change directory to spark/ then build images

```bash
sudo docker build --network=host -t usth-cloudandbigdata:spark-4.0.1_v0 -f Dockerfile .
```

## 2. Verify the build

```bash
sudo docker run --rm --entrypoint /opt/spark/bin/spark-submit usth-cloudandbigdata:spark-4.0.1_v0 --version
```

## 3. Start Spark on the Master

Build the image **before** starting Compose. If `spark-worker-1` declares only `usth-cloudandbigdata:spark-4.0.1_v0`, Compose may otherwise attempt to pull that tag from Docker Hub.

```bash
sudo docker compose -f compose-spark-master.yaml up -d --no-build
sudo docker compose -f compose-spark-master.yaml ps
sudo docker compose -f compose-spark-master.yaml logs --tail=50 spark-master spark-worker-1
```

Check the Spark Master UI at `http://<MASTER_TAILSCALE_IP>:8080` (when networking permits).

## 4. Build and start Spark on the second machine (option)

The second machine has its own Docker image store, so build the same image there unless you have transferred or published it.

```bash
cd /path/to/CloudandBigdata/spark
sudo docker build --network=host -t usth-cloudandbigdata:spark-4.0.1_v0 -f Dockerfile .
sudo docker compose -f compose-spark-worker.yaml up -d --no-build
sudo docker compose -f compose-spark-worker.yaml ps
```

Configure `TS_IP` in each machine's `.env` before starting Compose.

## Troubleshooting: `pull access denied for usth-spark`

This usually means `usth-cloudandbigdata:spark-4.0.1_v0` is missing locally while a Compose service only specifies `image:`.

```bash
sudo docker image inspect usth-cloudandbigdata:spark-4.0.1_v0
```

If it is missing, run the build command in step 1 (on the affected machine) and retry `up -d --no-build`. Ensure the `image:` tag in the Compose YAML exactly matches `usth-cloudandbigdata:spark-4.0.1_v0`.

**Note:** These steps build and start Spark only; the existing HDFS cluster must already be running and reachable. Do not format HDFS when building Spark.

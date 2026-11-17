# HDFS

## Configuration

Configure the NameNode address and DataNode advertised address in the Hadoop configuration files. Set the storage bind-mount path in the Compose files for each host.

```bash
# Check the local Tailscale address (if using Tailscale)
tailscale ip -4

# Create the DataNode storage directory
mkdir -p /path/to/hdfs/datanode
```

## Tailscale on WSL2: install and fix connectivity

Use this section **inside the Ubuntu/Debian WSL2 distro that will join the tailnet**. It covers Tailscale itself; the HDFS setup below stays unchanged.

> **Important for WSL2:** Do not run independent Tailscale instances on both the Windows host and its WSL2 distro as a default setup. They can interfere with networking. If multiple WSL distros share a network namespace, avoid running multiple `tailscaled` instances that each try to create `tailscale0`. Choose the location where Tailscale should run before configuring the HDFS endpoint. Tailscale's [WSL2 guide](https://tailscale.com/docs/install/windows/wsl2) discusses this limitation.

### 1. Enable systemd in WSL2 (if needed)

Check inside the target distro:

```bash
ps -p 1 -o comm=
systemctl is-system-running
```

If PID 1 is not `systemd`, edit `/etc/wsl.conf` and **preserve other existing settings**, adding:

```ini
[boot]
systemd=true
```

Then run **in Windows PowerShell** (this stops all running WSL distros, including their containers):

```powershell
wsl --shutdown
```

Open the distro again and confirm `ps -p 1 -o comm=` shows `systemd`.

### 2. Install Tailscale and start the daemon

Inside the WSL distro:

```bash
# Official Tailscale Linux installation script
curl -fsSL https://tailscale.com/install.sh | sh

sudo systemctl enable --now tailscaled
sudo systemctl status tailscaled --no-pager -l

# Only required to log in / join the tailnet for the first time
sudo tailscale up

tailscale status
tailscale ip -4
```

The node must be authorized in the same tailnet as the other machines. When it is already authenticated, a daemon restart normally does **not** require `tailscale up` again.

### 3. Fix `tailscale0: device or resource busy`

Symptom in `journalctl`:

```text
TUN device tailscale0 is busy
... tstun.New("tailscale0"): device or resource busy
```

A previous process may still hold `/dev/net/tun`, or another Tailscale instance in a shared WSL network namespace may own the interface. Find the owner first:

```bash
sudo systemctl stop tailscaled
sudo lsof -n /dev/net/tun
sudo pgrep -a tailscaled
ip link show tailscale0
```

If the owner is a **stale `tailscaled` process** (not a daemon still needed by another distro), stop that exact PID:

```bash
sudo kill -TERM <STALE_PID>
# Check again; use kill -KILL only if that same stale process will not exit
sudo lsof -n /dev/net/tun
sudo pgrep -a tailscaled
```

If no process holds the device but the old interface remains, delete it **only after verifying it is orphaned**:

```bash
sudo ip link delete tailscale0
```

Then restart:

```bash
sudo systemctl reset-failed tailscaled
sudo systemctl start tailscaled
sudo systemctl status tailscaled --no-pager -l
```

If WSL cannot release a stuck process or reports cgroup I/O errors, close active jobs, then use `wsl --shutdown` in Windows PowerShell and restart the distro. **Do not delete `/var/lib/tailscale/tailscaled.state`**: it contains the node's identity/state and deletion can require reauthentication.

### 4. Fix TSMP success but ICMP/TCP timeout

A successful `tailscale ping` or `tailscale ping --tsmp` verifies connectivity between Tailscale peers, **not** application-level TCP connectivity. For a WSL node, run:

```bash
tailscale status
tailscale ip -4
ip -4 addr show dev tailscale0
ip rule show
ip route show table 52
sudo journalctl -u tailscaled -n 80 --no-pager
```

In normal kernel-TUN mode, the interface should carry the node's tailnet IPv4 (for example, `inet 100.x.y.z/32`). If `tailscale ip -4` reports an address but `ip -4 addr show dev tailscale0` does not show it, reset the daemon-managed interface first:

```bash
sudo systemctl restart tailscaled
sudo tailscale set --shields-up=false
ip -4 addr show dev tailscale0
```

**Do not manually hard-code the Tailscale IP or add a broad `100.64.0.0/10` route as a permanent fix.** Tailscale manages device addresses and policy routes. If the IPv4 address is still absent, inspect daemon logs, WSL/TUN support and competing instances rather than changing Hadoop settings.

Check the TUN device when relevant:

```bash
ls -l /dev/net/tun
lsmod | grep '^tun' || true
# Only if the TUN device/module is missing and the WSL kernel supports it:
sudo modprobe tun
```

From another machine logged in to **the same tailnet**, replace the example IP with the target WSL node's `tailscale ip -4`:

```bash
tailscale ping 100.x.y.z
tailscale ping --tsmp 100.x.y.z
tailscale ping --icmp 100.x.y.z
nc -vz -w 5 100.x.y.z 9000
```

If TSMP works but ICMP/TCP fail, also check **Tailscale access controls** and host firewall; TSMP alone does not prove those data packets are permitted. In the [Tailscale Admin Console](https://login.tailscale.com/admin/acls), allow the source node to reach the destination on `tcp:9000` if existing policy does not already allow it. If UFW is enabled on the target WSL distro, a narrow example rule is:

```bash
# Replace with the actual source node's Tailscale IP
sudo ufw allow in on tailscale0 from <CLIENT_TAILSCALE_IP> to any port 9000 proto tcp
```

When TCP is still blocked, observe packets at the WSL interface while retrying the connection from the other machine:

```bash
sudo tcpdump -ni tailscale0 'tcp port 9000 or icmp'
```

**Interpretation:** no SYN seen means investigate the tailnet policy/routing before WSL; SYN seen with no reply means inspect WSL firewall or Docker forwarding; successful TCP only proves the port is reachable, not that HDFS DataNodes registered or file reads/writes work.

> **Docker/HDFS note:** `0.0.0.0:9000` in `docker compose ps` means Docker publishes the port on all host IPv4 interfaces. It does **not** mean the Tailscale address is absent. Verify that NameNode RPC works internally before changing Compose networking. Never reformat an existing NameNode to fix a connectivity issue.

Useful references: [Tailscale for Linux](https://tailscale.com/docs/install/linux), [Tailscale CLI](https://tailscale.com/docs/reference/tailscale-cli), [Tailscale on WSL2](https://tailscale.com/docs/install/windows/wsl2), [WSL systemd](https://learn.microsoft.com/windows/wsl/systemd).

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

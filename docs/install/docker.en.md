# Backpeer keeper node in Docker

A keeper node (`node`) gives disk space to other people's backups. The client
encrypts data on its own device and splits it into fragments, so the node sees
neither the contents nor the file names and keeps no account keys. The
container runs this role only: the app, scheduled backups and account sign-in
stay on the owner's device.

This guide is for any machine with Docker: a server, a home computer, a NAS or
a Raspberry Pi. It covers installation, pairing the node with an account and
day-to-day management: checks, pause, speed limits, updates, backups and
leaving the network.

## Requirements

- Docker Engine 24 or newer and Compose v2 (`docker compose`), 64-bit Linux.
  Docker Desktop works too, but a permanent node is better on a machine that
  runs around the clock.
- At least 100 GB for fragments: by default the coordinator does not accept
  nodes with less capacity. Used space grows gradually; the whole disk is not
  needed at once.
- Outbound HTTPS to the coordinator. Direct connections to clients work best
  with port 7340 TCP and UDP open; if you cannot open it, the node works
  through a relay.
- Clock synchronisation (NTP): coordinator tickets allow five minutes of
  clock skew.
- Root on the host is needed only to install Docker, forward the port and
  prepare the fragment directory. The node itself runs in the container as the
  unprivileged `fs-node` user (uid and gid 10003).

## Quick start

Create a directory and two files next to it:

```sh
mkdir -p backpeer-node
cd backpeer-node
```

`.env` — the image version and the coordinator address (given with a beta
invitation):

```text
BACKPEER_VERSION=latest
BACKPEER_COORDINATOR_URL=https://coordinator.example
```

`compose.yaml`:

```yaml
services:
  node:
    image: ghcr.io/3davinci/backpeer/node:${BACKPEER_VERSION:-latest}
    restart: unless-stopped
    # The daemon finishes current transfers for up to 30 seconds; Docker
    # kills the container after 10 by default, so give it time.
    stop_grace_period: 40s
    environment:
      FS_NODE_COORDINATOR_URL: ${BACKPEER_COORDINATOR_URL:?Set the coordinator address in .env}
      # How much space to give to fragments. 1 TB; at least 100 GB.
      FS_NODE_STORAGE_QUOTA_BYTES: "1000000000000"
    volumes:
      - node-data:/var/lib/fs-node
    ports:
      - "7340:7340/tcp"
      - "7340:7340/udp"

  # Management only: the node image has no `cli`. Starts on demand
  # (`--profile tools`), not as part of a plain `up`.
  cli:
    image: ghcr.io/3davinci/backpeer/cli:${BACKPEER_VERSION:-latest}
    profiles: ["tools"]
    # Same user as the node: otherwise the node's local API refuses it.
    user: "10003:10003"
    environment:
      FS_HOME: /tmp/backpeer-cli
    volumes:
      - node-data:/var/lib/fs-node
    entrypoint: ["cli"]

volumes:
  node-data:
    name: backpeer-node-data
```

Pair the node with an account. The container creates the keys, prints a code
and a QR code and waits for confirmation:

```sh
docker compose run --rm node pair
```

On the device where you are already signed in, run
`cli node pair <code>` (or open the Keeper section in the app) and check the
node fingerprint against the one printed in the container. The code is valid
for 10 minutes; if it expires, start pairing again. After "Node paired", start
the service:

```sh
docker compose up -d
docker compose ps
```

Within half a minute the `STATUS` column shows `healthy`: the daemon answers
on its local API. If `ps` shows `unhealthy` or the container keeps restarting,
read the log:

```sh
docker compose logs -f --tail=100 node
```

## Settings

Settings are `FS_NODE_*` environment variables: the name is the `node.yaml`
key path in upper case with `_` (`storage.quota_bytes` →
`FS_NODE_STORAGE_QUOTA_BYTES`). Variables take precedence over the file. An
unknown key is a startup error, so a typo shows up immediately.

| Variable | Default | Purpose |
|---|---|---|
| `FS_NODE_COORDINATOR_URL` | — | Coordinator address (`https://…`). Without it the node does not register and accepts no fragments |
| `FS_NODE_STORAGE_QUOTA_BYTES` | `100000000000` | How much space to give to fragments (100 GB is the coordinator minimum) |
| `FS_NODE_STORAGE_FREE_RESERVE_BYTES` | `2000000000` | How much free disk space to keep: a fragment that would leave less is not accepted |
| `FS_NODE_STORAGE_DIR` | data directory | Where to keep fragments and the index, for example on another disk (see "Disk and data") |
| `FS_NODE_LISTEN_PORT` | `7340` | TCP and UDP listening port; there is no reason to change it inside the container |
| `FS_NODE_LISTEN_ENDPOINTS` | — | `host:port` addresses the node always reports to the coordinator; needed when the external port is not 7340 (see "Ports, NAT and relay") |
| `FS_NODE_LISTEN_PORT_MAPPING` | `off` in the image | Router port mapping over UPnP, PCP or NAT-PMP. Disabled in the container: from the Docker network the node cannot see the router |
| `FS_NODE_LISTEN_RELAY` | `auto` | Relay reception: `auto` when the node has no addresses, `on` always, `off` never |
| `FS_NODE_LIMITS_UPLOAD_BYTES_PER_SECOND` | `0` | Upload limit, bytes per second; `0` means no limit |
| `FS_NODE_LIMITS_DOWNLOAD_BYTES_PER_SECOND` | `0` | Download limit, bytes per second; `0` means no limit |
| `FS_NODE_LOG_LEVEL` | `info` | `fine`, `info`, `warning`, `severe` |
| `FS_NODE_COORDINATOR_CHANNEL` | `true` | Keep the coordinator command channel; `false` means commands (repair, audit, rendezvous) do not reach the node |
| `FS_NODE_SHUTDOWN_GRACE_SECONDS` | `30` | How long to wait for current transfers on shutdown |
| `FS_NODE_CERT_FILE` | — | Image entrypoint only: a node certificate mounted into the container (see "Pairing") |
| `FS_NODE_CONFIG` | `<data>/node.yaml` | A YAML settings file instead of variables; mount it into the container and set the path |

Other keys — the speed schedule, integrity checks, connection limits — are
listed in the project documentation; in Docker the variables above are almost
always enough.

**Permanent and temporary limits.** Values from variables apply after the
container is recreated. `cli node limits` changes limits until the next
restart, which is handy for slowing a node down quickly. A "slower during the
day" schedule is set in `node.yaml` under `limits.schedule` and survives
restarts; the schedule applies on top of the main limits.

## Ports, NAT and relay

The node must accept incoming connections: over TCP and, after rendezvous
through the coordinator, over UDP as well. The example publishes both ports on
the same number, 7340.

- **Router port.** Port mapping is disabled in the image: from the Docker
  network the node cannot see a UPnP router. Forward 7340 TCP and UDP to the
  container host manually; Docker publishes them into the container.
- **External port is not 7340.** If the router's external port differs, the
  coordinator probes a different port than the node listens on, and the node
  stays "unreachable from outside". Report the address explicitly, for
  example `FS_NODE_LISTEN_ENDPOINTS=home.example.org:8340` (several addresses
  can be comma-separated). The coordinator does not verify such addresses but
  gives them to clients.
- **Reachability check.** If the external port is 7340, the node asks the
  coordinator to check the address the request came from. The result appears
  in `cli node status` as «доступен извне (адрес)» (reachable) or
  «извне недоступен» (not reachable).
- **No external address.** A node behind symmetric NAT, double NAT or without
  port forwarding works through a relay: connections go through a public
  server, and the relay sees ciphertext only. `FS_NODE_LISTEN_RELAY=auto`
  enables this automatically when the node has no addresses.
- **Firewall.** Allow incoming 7340 TCP and UDP and outbound HTTPS to the
  coordinator. UDP is needed for rendezvous with nodes behind NAT; without it
  only TCP and relay remain.

Check how the node sees the network:

```sh
docker compose --profile tools run --rm cli \
  node status --node-data /var/lib/fs-node
```

The «Приём соединений» line shows the port, mapping and reachability result;
the coordinator line shows whether the command channel is open. A node marked
`needs_relay` will accept connections through a relay: that is normal, only
slower than direct ones.

## Pairing with an account

The node cannot accept fragments without a certificate signed by the owner's
device. There are two ways.

**One-time code (the usual way).** Stop the node if it is running and run
`docker compose run --rm node pair`. The container prints the code, its
expiry, the fingerprint and a QR code. On the device with the account run
`cli node pair <code>` or open Keeper in the app, compare the fingerprint and
confirm. After the container prints «Узел привязан к учётной записи» (node
paired), start the service: `docker compose up -d`.

**Certificate (when the code is not available).** On the owner's device issue
a certificate for the node's keys:

```sh
docker compose run --rm node init --json   # prints node_id and node_dh
cli node-cert --node-id … --node-dh … --out node.cert
```

Put `node.cert` next to `compose.yaml` and add to the `node` service:

```yaml
    environment:
      FS_NODE_CERT_FILE: /run/secrets/node.cert
    volumes:
      - node-data:/var/lib/fs-node
      - ./node.cert:/run/secrets/node.cert:ro
```

The image entrypoint imports the certificate on every start. A certificate is
accepted only for this node's keys: a foreign one or one with a bad signature
is rejected and the container exits with an error.

After pairing, restart the node if it was running without a certificate:
`docker compose up -d --force-recreate node`. A revoked device no longer
completes the handshake with nodes, so revocation in the app applies here too.

## Checking the node

```sh
docker compose ps                                  # healthy: the daemon answers
docker compose exec node node health               # exit code 0: local API is alive
docker compose logs -f --tail=100 node             # JSON Lines log
docker compose --profile tools run --rm cli \
  node status --node-data /var/lib/fs-node          # node state
```

A healthy start has `started`, `listening`, `registered` and `channel_opened`
events in the log. After that heartbeats run every few minutes (over the
channel or HTTP); connection errors do not bring the node down, it retries
with a pause.

The text output of the CLI is in Russian; the same values are in the
machine-readable `--json` output. What to look at in `cli node status`:

- `usedBytes`, `quotaBytes` and `freeBytes` — used space and how much more the
  node will accept;
- `fragments` and `damagedFragments` — how many are stored and how many are
  damaged (damaged ones are not served and are reported to the coordinator);
- `listen`, `portMapping` and `reachability` — port, mapping and reachability
  from outside;
- `coordinator` — registration, last contact time, command channel.

Counters of the background integrity check are in `cli node stats`.

## Management

In the table the long prefix `docker compose --profile tools run --rm cli` is
shortened to `…`.

| Task | Command |
|---|---|
| State | `docker compose --profile tools run --rm cli node status --node-data /var/lib/fs-node` |
| Statistics since start | `docker compose --profile tools run --rm cli node stats --node-data /var/lib/fs-node` |
| Pause (no new transfers, heartbeats continue) | `… node pause --node-data /var/lib/fs-node` |
| Resume | `… node resume --node-data /var/lib/fs-node` |
| Limits until restart | `… node limits --upload 2000000 --download 4000000 --node-data /var/lib/fs-node` |
| Restart | `docker compose restart node` |
| Stop | `docker compose stop node` |
| Start | `docker compose up -d node` |
| Log | `docker compose logs -f --tail=100 node` |
| Update the image | `docker compose pull && docker compose up -d` |
| Leave the network | `… node exit --node-data /var/lib/fs-node` (see "Leaving the network") |

`cli node stop` stops the daemon but not the container: with
`restart: unless-stopped` Docker starts it again. To really stop the node, stop
the container: `docker compose stop node`.

Changes to `environment` and `volumes` apply only when the container is
recreated: `docker compose up -d` (not `restart`). Data and keys live in the
`backpeer-node-data` volume, so recreation does not touch them.

**Limits and pause.** `pause` is useful when you need the bandwidth for
something else: current transfers finish, new ones do not start, and the node
stays connected. Limits are in bytes per second and shared by all connections.
Permanent limits go in `environment` (`FS_NODE_LIMITS_*`), temporary ones with
`limits`; after a restart the permanent values return.

## Disk and data

The `backpeer-node-data` volume holds the node keys, certificate, logs, the
fragment index and the fragments themselves. Recreating the container and
updating the image leave the volume alone; deleting it (`docker compose down
-v` or `docker volume rm`) destroys the node permanently — for the coordinator
this is a lost node, and repair restores its fragments on other nodes.

**Backup.** Node keys are stored in the volume without a password (the daemon
runs unattended), so a volume copy is the node itself: treat it as a secret.
Do not restore a copy on another machine while the original node is running:
two nodes with the same key would appear on the network.

```sh
docker compose stop node
docker run --rm -v backpeer-node-data:/data -v "$PWD":/backup alpine \
  tar czf "/backup/backpeer-node-$(date +%F).tar.gz" -C /data .
docker compose start node
```

Restore on a stopped node:

```sh
docker compose stop node
docker run --rm -v backpeer-node-data:/data -v "$PWD":/backup alpine \
  sh -c 'rm -rf /data/* && tar xzf /backup/backpeer-node-2026-11-07.tar.gz -C /data'
docker compose start node
```

**Fragments on another disk.** Keys can stay on the system disk while
fragments go to a large one. Mount a host directory and point
`FS_NODE_STORAGE_DIR` at it:

```sh
sudo mkdir -p /srv/backpeer/fragments
sudo chown 10003:10003 /srv/backpeer/fragments
sudo chmod 700 /srv/backpeer/fragments
```

```yaml
    environment:
      FS_NODE_STORAGE_DIR: /srv/backpeer/fragments
    volumes:
      - node-data:/var/lib/fs-node
      - /srv/backpeer/fragments:/srv/backpeer/fragments
```

The directory must belong to uid 10003; another owner means the node will not
start or cannot write. Move already collected fragments while the node is
stopped: copy `fragments/` and `fragments.db` to the new directory with their
permissions and only then change the setting. Otherwise the index and files
diverge and the coordinator receives damaged-fragment reports.

**Out of space.** The node rejects a fragment if it would leave less than
`FS_NODE_STORAGE_FREE_RESERVE_BYTES` on disk. Used space is shown by
`cli node status`; free it by lowering the quota (the coordinator moves extra
fragments away) or by adding a disk.

## Updating

Images are published with a version tag and as `latest`. For a permanent node
it is better to pin a version in `.env` (`BACKPEER_VERSION=v0.0.3`) and update
deliberately:

```sh
docker compose pull
docker compose up -d
```

Updating recreates the container; data and keys stay in the volume. To roll
back, restore the previous tag in `.env` and run `docker compose up -d` again;
keys and fragments do not change and protocol compatibility is checked when
peers connect. Before updating it is worth backing up the volume and reading
`docker compose logs` after the start.

## Leaving the network

If the node is no longer needed, do not delete the volume at once: announce
the departure first. The coordinator stops placing fragments on the node and
moves the stored ones to other nodes.

```sh
docker compose --profile tools run --rm cli \
  node exit --node-data /var/lib/fs-node
docker compose --profile tools run --rm cli \
  node status --node-data /var/lib/fs-node
```

Relocation runs while the node is up; `cli node status` shows how many fragments
remain. Do not switch the node off before relocation finishes: a node that is
off for 72 hours is considered lost and repair restores its fragments. When
nothing is left to move, the daemon deletes the fragments, stops and never
starts again with this data directory. Then remove the container and volume:

```sh
docker compose stop node
docker compose down
docker volume rm backpeer-node-data
```

`node exit --cancel` cancels the departure; fragments already moved stay on
the new nodes. To participate again, create a new volume and pair a new node:
`docker compose run --rm node pair` (the old node cannot be restored).

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| The container restarts every few seconds | Missing `FS_NODE_COORDINATOR_URL`, wrong volume permissions, port 7340 already in use | `docker compose logs --tail=100 node`; check `.env`, volume owner (uid 10003) and the port |
| `unhealthy` in `docker compose ps` | The daemon does not answer on the local API | `docker compose logs`; make sure the container is not killed by the stop timeout (`stop_grace_period`) |
| `docker compose pull` returns `401` | GHCR images are not published yet or are private | Build the image from source (`docker build -f packages/node/Dockerfile -t … .`) or use your own registry |
| Pairing does not show a code | The coordinator is unreachable or pairing is disabled there | Check the address and `docker compose run --rm node pair`; use a certificate if needed |
| The pairing code is rejected | The 10 minutes have expired | Run `pair` again and enter the new code |
| «Узел привязан», but no fragments arrive | No access from outside and relay is not enabled | Check port forwarding and `FS_NODE_LISTEN_ENDPOINTS`; keep `FS_NODE_LISTEN_RELAY=auto` |
| «ёмкость меньше 100000000000 байт» in the log | `FS_NODE_STORAGE_QUOTA_BYTES` is below the coordinator minimum | Increase the quota and disk space |
| `permission denied` in the log | The volume or fragment directory belongs to another user | `sudo chown -R 10003:10003` on the fragment directory; no need to recreate the volume |
| `node.lock` and the node does not start | Another container is using the same volume | Stop the extra container: `docker ps` |
| Tickets are rejected (signature check fails) | The host clock has drifted | Enable NTP and restart the node |

If nothing helps, the log records the error type but never keys or fragment
contents. For analysis use `docker compose logs --since 1h node` and the
machine-readable
`docker compose --profile tools run --rm cli --json node status
--node-data /var/lib/fs-node`.

## Security

- The container runs as non-root (uid 10003) with a volume owned and readable
  only by that user.
- Node keys are stored in the volume without a password: they cannot decrypt
  client data, but they can impersonate the node and harm storage. Protect the
  volume, backups and Docker access on the host.
- Only port 7340 needs to be public; do not publish the coordinator port or
  the Docker API.
- The node never sees file names or contents: encryption happens on the
  client device.
- Keep the image and the host updated: the node makes decisions based on
  coordinator signatures, not on a password.

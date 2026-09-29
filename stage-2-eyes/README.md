# Stage 2 — Eyes (security telemetry and visibility)

Adds Wazuh (manager, indexer, dashboard) on top of Stage 1, and installs a
Wazuh agent on the endpoint, so activity on the endpoint becomes visible as
telemetry. No detections/alerting logic yet — that's Stage 3. The goal here
is purely: **activity → endpoint event → telemetry → Wazuh**.

```
   ATTACKER (10.10.10.20)
          │
   range-net (isolated, no internet - same as Stage 1)
          │
   ENDPOINT (10.10.10.10) ───── wazuh-net ─────  WAZUH MANAGER
     - sshd, web service               (telemetry only,        │
     - wazuh-agent installed            endpoint-only,      WAZUH INDEXER
       and enrolled                     not internet-      (OpenSearch, stores
                                         isolated)           events/alerts)
                                                                 │
                                                            WAZUH DASHBOARD
                                                           (https://localhost:443)
```

The attacker stays only on the isolated `range-net` — it has no path to the
Wazuh stack. Only the endpoint is dual-homed, onto both the range network
(for attack traffic) and the Wazuh network (for telemetry). That's a
deliberate change from Stage 1's "attacker + endpoint, fully isolated"
model: the *attack surface* is still isolated, but the *endpoint* now has a
second interface out to the monitoring stack, and therefore isn't
internet-isolated any more. Worth being upfront with students about that
trade-off.

## Why Wazuh is vendored, not hand-built

Wazuh's own single-node Docker stack (SSL certs between manager/indexer/
dashboard, OpenSearch memory settings, internal user config) is non-trivial
and actively maintained by Wazuh. Rather than reconstruct and maintain a
shadow copy of that ourselves, `deploy.sh` clones the **official
wazuh-docker repo at a pinned tag** (`WAZUH_TAG` at the top of the script)
and runs it unmodified, using Docker Compose's normal mechanisms (an
override file, network discovery) to plug our endpoint into it. Bumping to
a newer Wazuh release for a future cohort is a one-line change to
`WAZUH_TAG`, not a rewrite.

The same `WAZUH_TAG` also pins the endpoint's **agent** package (passed
through as the `WAZUH_VERSION` build arg). Wazuh refuses agents newer than
the manager, so leaving the agent unpinned would silently break enrollment
the first time a student rebuilds after Wazuh ships a new 4.x release.
Bumping the tag moves both together; after a bump, rebuild the endpoint
(`./reset.sh`, or `docker compose build --no-cache endpoint`) so it picks up
the new agent.

## Prerequisites

- Everything from Stage 1 (Docker Desktop, terminal).
- **Docker Desktop given at least 6–8GB RAM** (Settings → Resources →
  Advanced). The Wazuh indexer (OpenSearch) is the memory-hungry part;
  under-provisioning here is the most common cause of a stack that never
  goes healthy.
- `git`, available in the terminal (`git --version` to check) — used to
  fetch the pinned Wazuh release.
- Internet access at deploy time (to clone wazuh-docker and pull its
  images). Note this is a step back from Stage 1, which needed no internet
  once images were built.

## Quick start

```bash
./deploy.sh      # clones Wazuh (first run only), starts everything
./validate.sh    # checks containers, and that the agent has connected
./reset.sh       # wipes everything, including Wazuh, and rebuilds
```

First deploy takes several minutes (cloning Wazuh, pulling three sizeable
images, generating certificates, indexer startup). Re-running `deploy.sh`
after that reuses the cloned repo.

`deploy.sh` is safe to re-run at any time, and clears the usual blockers
itself before starting:

- **Stage 1 still running.** Both stages use `10.10.10.0/24` and Docker
  refuses to create a second network with the same range, so Stage 2 stops
  Stage 1 first.
- **Leftovers from earlier attempts** (old containers, networks and Wazuh
  volumes) are removed.
- **Stale agent registrations.** Every deploy gives the endpoint a fresh
  start, and removes any old `endpoint01` registration from the manager
  first, so the new one isn't rejected as a duplicate.
- **Certificate problems on macOS** (see Troubleshooting).

On macOS it may ask for your computer password while fixing certificate
file permissions. That's expected; it's only used for files inside
`vendor/`.

**Dashboard:** `https://localhost:443` — login `admin` / `SecretPassword`.
That's the wazuh-docker single-node project's own default (baked into its
compose file) — fine for a disposable teaching lab, not something to reuse
anywhere real. See Wazuh's ["changing the default
password"](https://documentation.wazuh.com/current/deployment-options/docker/changing-default-password.html)
docs if you want to change it.

## How agent enrollment works here

The wazuh-docker single-node stack's manager runs `wazuh-authd` with no
enrollment password required by default. Rather than fight to enable one
(it requires state that turned out not to persist reliably across
container recreation in testing), Stage 2 matches that: the endpoint's
`ossec.conf` has its `MANAGER_IP` placeholder swapped for the manager's
container hostname (`wazuh.manager`, resolvable because they share the
Wazuh network) and an `<enrollment>` block pointing at it, with no
password. `wazuh-agentd` handles the actual enrollment handshake on first
connect, and keeps retrying in the background if the manager isn't
reachable yet - so container start order isn't critical.

This is a deliberate simplification for a disposable teaching lab: the
Wazuh network is only reachable by containers we've explicitly joined to
it, so there's no meaningful population of "untrusted" agents that could
enroll. It would be the wrong call for anything internet-facing.

## Known limitations (by design, for a PoC)

- Only the endpoint is instrumented — Stage 1's attacker box has no agent
  and isn't meant to (it's not something you'd monitor in real life).
- Dashboard/indexer/API credentials are the wazuh-docker project's fixed
  defaults, not per-deployment secrets.
- `internal: true` isolation from Stage 1 now only holds for the attacker;
  the endpoint has a route out via the Wazuh network.
- No detection rules, alerting, or ATT&CK mapping yet — an event existing
  in Wazuh is not the same as Wazuh *noticing* it. That's Stage 3.
- `reset.sh` removes Wazuh's containers **and** its Docker volumes (the
  manager keeps agent registrations in them), plus the whole
  `vendor/wazuh-docker` directory with its generated certificates, then
  redeploys. That's what makes it a genuine return to baseline. The
  certificate generator leaves `vendor/` read-only, so on some machines
  `reset.sh` asks for your password to delete it.
- `vendor/` and `.env` are git-ignored, so deploying and resetting never
  touch tracked files - `git pull` to pick up course updates works without
  needing a separate working copy.
- No enrollment password (see above) — acceptable for an isolated
  disposable lab, not a pattern to carry into anything else.

## Troubleshooting

- **Indexer never goes healthy / keeps restarting**, logs mention
  `vm.max_map_count`: OpenSearch needs the host kernel setting
  `vm.max_map_count >= 262144`. Docker Desktop usually sets this
  automatically; if not, on Windows run
  `wsl -d docker-desktop sysctl -w vm.max_map_count=262144` and restart
  Docker Desktop. On Mac this is normally already handled.
- **"Pool overlaps with other one on this address space"** or similar IP
  address errors: another Docker network is using `10.10.10.0/24`.
  `deploy.sh` stops Stage 1 automatically and names any other network that
  clashes - remove that one and re-run.
- **macOS: "error while creating mount source path ... root-ca-manager.pem"**:
  the certificate generator can't finish its last step on Docker Desktop
  for macOS, so Docker created a folder where a file should be.
  `deploy.sh` now detects and repairs this; if you still see it, run
  `./reset.sh`.
- **"Duplicate agent name: endpoint01"** in the agent's log: the manager
  still holds an old registration. Re-run `./deploy.sh`, which removes it
  and recreates the endpoint.
- **Agent never shows "Connected to the server"**: check
  `docker exec stage2-endpoint tail -30 /var/ossec/logs/ossec.log` for the
  actual error, and confirm the manager container is healthy
  (`docker ps`). A password mismatch shows up as an authentication error
  in that log.
- **`deploy.sh` fails at the network-discovery step**: run
  `docker network ls` and confirm a network exists whose name starts with
  `stage2-eyes-wazuh`. If Wazuh's containers didn't start at all, that
  step never created one — check `docker compose logs` from
  `vendor/wazuh-docker/single-node` (with `COMPOSE_PROJECT_NAME=stage2-eyes-wazuh`
  set) first.

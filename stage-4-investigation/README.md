# Stage 4 — Investigation

Adds **Velociraptor** (live endpoint investigation / DFIR) on top of the
running `delab` lab. Wazuh tells you *that* something happened; Velociraptor
is how you go and find out *what actually happened* on the machine.

```
   ATTACKER ──► ENDPOINT ──► Wazuh        ──► alerts        (detect)
                    │
                    └──────► Velociraptor ──► artefacts      (investigate)
```

## Wazuh vs Velociraptor — why both

| Wazuh | Velociraptor |
| --- | --- |
| Continuous monitoring | Targeted investigation |
| "Something happened" | "What exactly happened, in detail" |
| Alerting, always on | Querying / artefact collection, on demand |

A Wazuh alert is a *lead*. It doesn't hand you the process tree, the user
list, or recently-changed files at that moment — you go and get those with
Velociraptor, starting from the alert. Keeping the two tools separate
(rather than one doing both badly) mirrors how real SOCs are structured,
and it's the heart of this stage: **pivot from an alert into an
investigation.**

## Layered on the delab lab

Like Stage 3, Stage 4 owns **no** Wazuh and **no** endpoint/attacker. It
reuses the running `delab` stack and only adds:

- a **`delab-velociraptor`** server container on the shared Wazuh network;
- a **Velociraptor client** on the existing `delab-endpoint`.

`deploy.sh` ensures Stages 2 + 3 are up (it runs Stage 3's deploy, which is
idempotent), then starts the server and wires up the client.

## How the client gets onto the endpoint

Velociraptor's server and client are the **same binary** — which one it is
depends only on the config you hand it. `deploy.sh`:

1. starts the official Velocidex server image (pinned in `deploy.sh`);
2. once the server has generated its config, extracts a ready-to-use
   `client.config.yaml` from it (`velociraptor … config client`);
3. copies that config **and the server's own binary** onto the endpoint
   (copying the server's binary guarantees the architecture matches the
   host — the image's internal layout isn't documented, so it's found with
   `command -v` rather than guessed);
4. **restarts the endpoint**, so its entrypoint launches the client as a
   proper child of PID 1 (the Stage 2 entrypoint has a guarded block for
   this). That's also why the client comes back automatically after any
   endpoint restart — we don't rely on a detached `docker exec`.

`deploy.sh` then waits and confirms the client has actually **enrolled**
before it reports success.

## Quick start

```bash
./deploy.sh      # ensures Stages 2-3, adds Velociraptor, enrols the client
./validate.sh    # pipeline + client enrolled + live host evidence
./reset.sh       # wipes Velociraptor + rebuilds the whole lab from baseline
```

- **Wazuh dashboard:** `https://localhost:443` — `admin` / `SecretPassword`
- **Velociraptor dashboard:** `https://localhost:8889` — `admin` /
  `VelociraptorLab123!`

Both use self-signed certs for the local lab — click through the browser
warning (same as Wazuh). These are fixed teaching-only defaults.

## Doing an investigation

1. Trigger the Stage 3 alert for real — from the attacker:
   `docker exec -it delab-attacker ssh student@10.10.10.10` (password
   `password123`).
2. Confirm it in the Wazuh dashboard (**Threat Hunting**).
3. Switch to the Velociraptor dashboard, search for the client
   (`endpoint01`), and run a collection. Good starting artefacts:
   - `Generic.Client.Info` — basic host info (confirm you've got the right
     machine)
   - `Linux.Sys.Users` — who exists on this box
   - `Generic.System.Pstree` — what's running
   - `Linux.Search.FileFinder` (under `/home/student`) — what's in the
     account that was logged into
4. Ask what Velociraptor told you that the alert alone did not — and, for
   Part 2, what it *couldn't* tell you (the gaps).

## Headless VQL (for scripts and the "hunt" stretch)

Everything the GUI does is VQL underneath, and you can run VQL from the
command line against the **running** server through its API. (A plain
`query --config server.config.yaml` runs in a throwaway context that can't
see enrolled clients — you must go through the API.) The lab's `admin` user
already has the administrator role, so:

```bash
# one-time: issue an API cert for admin (deploy/validate do this for you)
docker exec delab-velociraptor velociraptor \
  --config /etc/velociraptor/server.config.yaml \
  config api_client --name admin --role administrator \
  /etc/velociraptor/admin.api.yaml

# then query the live server:
docker exec delab-velociraptor velociraptor \
  --api_config /etc/velociraptor/admin.api.yaml \
  query --format jsonl "SELECT client_id, os_info.hostname AS host FROM clients()"
```

This is the reachable route to the Part 2 "hunt it with custom VQL"
distinction avenue — write a query that finds *your* technique's footprint,
rather than only running a canned artefact.

## Known limitations (by design, for a PoC)

- The client is wired up by `deploy.sh` at runtime (and relaunched by the
  endpoint entrypoint), not baked into the endpoint image — neither Wazuh
  enrolment nor Velociraptor enrolment can be done until its server exists.
- One server, one client — no hunting across many endpoints, which is where
  Velociraptor really shines. Scope for a PoC.
- No automatic Wazuh-alert-to-Velociraptor pivot — the **manual** pivot *is*
  the exercise. (Automating it would be Stage 5 territory.)
- Fixed teaching-only credentials, not per-deployment secrets.

## Troubleshooting

- **Client shows "No certificate found for destination" once, then sleeps:**
  normal on the *first* poll — the client fetches and pins the server cert,
  backs off, and enrols on the next poll. `deploy.sh` waits for this.
- **`validate.sh` / `deploy.sh` say the client isn't enrolled, but the GUI
  shows it:** make sure the enrolment check is going through the API
  (`--api_config`), not `query --config server.config.yaml` — the latter
  always returns no clients, even when enrolment is fine.
- **Client not enrolling at all:** check its log —
  `docker exec delab-endpoint tail -30 /var/log/velociraptor-client.log` —
  for a repeating connection/cert error (as opposed to the one-off first
  poll), and confirm the endpoint resolves the server:
  `docker exec delab-endpoint getent hosts velociraptor`.
- **Port 8889 already in use:** something else is publishing it; free that
  port or remap `8889` in `docker-compose.yml`.

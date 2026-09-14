# Stage 1 — Environment

Provides the underlying cyber range: an attacker box, a Linux victim endpoint,
and an isolated network between them, with basic users/files/services and
realistic background activity — no monitoring or detection yet (that's
Stage 2+).

```
   ATTACKER (10.10.10.20)
          │
   isolated bridge network (10.10.10.0/24, no internet egress)
          │
   ENDPOINT (10.10.10.10)
     - sshd, port 22
     - simple web service, port 80
     - users: admin (sudo), student (intentionally weak password), websvc
     - baseline_activity.sh runs every minute via cron, simulating a
       real user and producing auth-log noise
```

## Quick start

```bash
./deploy.sh      # build + start
./validate.sh    # check attacker -> endpoint connectivity and baseline logs
./reset.sh       # wipe everything and rebuild from a clean baseline
```

Students only ever need `deploy.sh` (and `reset.sh` if something breaks) —
they don't need to touch the Dockerfiles or compose file to use the range.

## Trying an attack

From the attacker container:

```bash
docker exec -it stage1-attacker bash
./port_scan.sh                 # nmap sweep of the endpoint
./ssh_bruteforce.sh            # hydra against the weak 'student' account
```

## Why it's built this way

- **Debian Linux endpoint, plain Docker Compose** — no Windows containers or
  a hypervisor needed; runs anywhere Docker does. Windows endpoints are a
  later addition once Stage 1's pattern is proven out.
- **`internal: true` network** — the range has no route to the host's other
  networks or the internet at runtime, satisfying "isolated" without a VPN
  or firewall rules to maintain.
- **Everything (users/files/services) is created by `entrypoint.sh` on
  every container start**, not baked once into the image — so `reset.sh`
  (`down -v` + rebuild) always produces the identical baseline, satisfying
  "reproducible" and "disposable" without a separate state-management layer.
- **`baseline_activity.sh`** exists so the endpoint isn't silent — it's
  what later stages need to tell real activity apart from an attack.

## Acceptance test

> Attacker → Endpoint communication works and the environment can be
> reset/recreated.

`validate.sh` checks: both containers running, attacker can reach the
endpoint, the web and SSH services respond, and baseline activity is being
logged. Run it once after `deploy.sh`, and again after `reset.sh` to confirm
the reset produces a working environment.

## Known limitations (by design, for a PoC)

- Containers share the host kernel — this isolates the *range* from your
  other networks, not from the host itself. Don't run this on a machine
  with anything sensitive on it.
- Passwords are hardcoded and deliberately weak on the `student` account —
  that's the point, not an oversight.
- No Windows endpoint yet — planned as a later addition, not part of
  Stage 1.

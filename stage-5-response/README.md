# Stage 5 — Response

Closes the incident-response loop. Stages 2–4 let you **detect** (Wazuh) and
**investigate** (Velociraptor); Stage 5 adds **automated response** — when a
detection fires, the lab acts on it without waiting for a human.

```
   ATTACKER ──► ENDPOINT ──► Wazuh  ──► alert (rule 5763)
                    ▲                        │
                    │                        ▼
                    └──────── firewall-drop ◄── active response   (respond)
```

Stage 5 is **native Wazuh active response**: a detected SSH brute force
automatically firewalls the attacker off the endpoint, then lifts the block
after a timeout. Light, reliable, no new containers — it completes the
**detect → investigate → respond** pipeline.

> This stage is **outside the standard assessed basis (Stages 1–4)**. It's the
> "active response" extension credited for higher grades in Part 2.

> **Going further (optional, separate add-on).** A SOAR platform such as
> *Shuffle* can turn a Wazuh alert into a multi-step playbook — for example,
> auto-starting a Velociraptor collection the moment a detection fires. That's
> an optional extension beyond Stage 5 (and a heavier thing to run); it's noted
> here as the orchestration avenue for anyone chasing the top band, not part of
> the core lab.

## Layered on the delab lab

Like Stages 3 and 4, Tier 1 owns **no** Wazuh, endpoint, attacker or
Velociraptor. It reuses the running `delab` stack and only adds a few lines of
active-response config to the manager. `deploy.sh` ensures Stages 2–4 are up
(it runs Stage 4's deploy, which chains down to Stage 2), then applies the
response.

## How it works

Two pieces of config, in `active-response/local_ar.conf`, injected into the
manager's `ossec.conf` by `reload-response.sh`:

| Piece | Does |
| --- | --- |
| `<command>` `firewall-drop-delab` | names the responder script that ships with the agent (`firewall-drop` → an iptables DROP), with `timeout_allowed` so Wazuh can auto-undo it |
| `<active-response>` | binds that command to a trigger: run it **locally** on the agent that saw rule **5763** (the Stage 3 brute-force rule), for a **60-second** block |

When the attacker trips rule 5763, the manager tells the endpoint's agent to
run `firewall-drop`. The script reads the attacker's IP from the alert and adds
`iptables -I INPUT -s <attacker> -j DROP` on the endpoint — so the attacker is
cut off **on the machine it's attacking**, not on the manager. Sixty seconds
later Wazuh calls the same script with `delete` and the block lifts.

This needs two things on the endpoint, both added in Stage 2:
- the `iptables` binary, and
- the `NET_ADMIN` capability (so the agent may change the firewall).

## Quick start

```bash
./deploy.sh            # ensures Stages 2-4, applies the active response
./validate.sh          # proves: brute force -> real block -> auto-recover
./reload-response.sh   # fast re-apply after editing local_ar.conf (no rebuild)
./reset.sh             # full rebuild of the lab, then re-apply (slow)
```

- **Wazuh dashboard:** `https://localhost:443` — `admin` / `SecretPassword`

## See it live

```bash
# from the attacker, brute-force the student account:
docker exec -it delab-attacker ssh student@10.10.10.10     # wrong password, repeatedly

# watch the response on the endpoint:
docker exec delab-endpoint tail -f /var/ossec/logs/active-responses.log
docker exec delab-endpoint iptables -S INPUT               # the DROP appears, then goes
```

In the Wazuh dashboard (**Threat intelligence → Threat Hunting**) the brute-force
alert (rule 5763) is the trigger; the `active-responses.log` on the endpoint is
the ground truth that the response actually ran.

## Your task (the student exercise)

Add a **second** response, tied to a different technique from your incident.
Edit `active-response/local_ar.conf`, add another `<active-response>` block
bound to a different `rules_id`, and `./reload-response.sh`. Think about:

- Which detections *should* trigger an automated response, and which are too
  risky to automate (what happens if it fires on a false positive)?
- Is `firewall-drop` the right response, or would a different action fit better?
- What's a sensible timeout — long enough to matter, short enough to recover?

## Known limitations (by design, for a PoC)

- One response, one worked example — the rest is the student task.
- `firewall-drop` blocks the whole source IP, not just the offending service.
  Fine for this lab; real deployments weigh that bluntness.
- The block is time-boxed and local to the endpoint — there's no central record
  of "who is currently blocked" beyond the agent's log. That coordination is
  exactly what a SOAR orchestration layer (the optional Shuffle add-on) is for.
- Fixed teaching-only settings, not a tuned production policy.

## Troubleshooting

- **Block never appears / `validate.sh` fails at Level 2:** check the attack
  actually raised rule 5763 — `docker exec delab-wazuh-wazuh.manager-1 tail -5
  /var/ossec/logs/alerts/alerts.json` — and that the agent received the command
  — `docker exec delab-endpoint tail -30 /var/ossec/logs/active-responses.log`.
- **`firewall-drop` logs a permission/iptables error:** the endpoint is missing
  `NET_ADMIN` or `iptables`. Rebuild it with Stage 2's `./deploy.sh` (both were
  added there).
- **The attacker's own SSH fails with "REMOTE HOST IDENTIFICATION HAS CHANGED":**
  the endpoint was rebuilt and its host key changed. `deploy.sh`/`reset.sh`
  clear this automatically; to do it by hand:
  `docker exec delab-attacker ssh-keygen -f /root/.ssh/known_hosts -R 10.10.10.10`.
- **Re-running `validate.sh` immediately shows a lingering block:** a previous
  run's 60-second block is still active; the script waits it out, or just re-run
  in a minute.

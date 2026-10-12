# Stage 3 — Detections

Same running environment as Stage 2 (attacker, endpoint, Wazuh manager/
indexer/dashboard, agent enrolled) — what's new is a **custom detection
rule**, added the way Wazuh itself expects custom rules to be added,
without touching anything in Wazuh's own shipped ruleset.

```
   ATTACKER ──► ENDPOINT ──► telemetry ──► WAZUH MANAGER
                                              │
                                    default ruleset (shipped)
                                              +
                                    rules/local_rules.xml  ◄── you edit this
                                              │
                                              ▼
                                          ALERTS
```

## Stage 3 is layered on Stage 2 — it doesn't run its own Wazuh

This is the big change from how the earlier stages were structured. Stage 3
does **not** bring up a second copy of Wazuh. It uses the one Stage 2
already started, and just loads a rule onto it. So:

- `deploy.sh` checks whether the Stage 2 stack is running. If it is, loading
  the rule takes seconds. If it isn't, it runs Stage 2's `deploy.sh` first
  (the slow 10–20 minute first-run), then loads the rule.
- There is only ever **one** set of containers — shared, with stage-neutral
  names: `delab-endpoint`, `delab-attacker`, and the Wazuh stack under the
  `delab-wazuh` compose project (`delab-wazuh-wazuh.manager-1`, etc.).
- This is why Stage 2 and Stage 3 never clash on ports, the `10.10.10.0/24`
  range, or RAM — there's only one stack, not two. (Running two Wazuh
  indexers in 8 GB was never going to work anyway.)

## What's in `rules/local_rules.xml`

One worked example: **a successful SSH login to the `student` account**
(rule `100010`). Not "detect SSH bruteforce" — Wazuh's default ruleset
already does that (rule `5763`, built on the per-failure rule `5760`) — but
something specific to *this* lab that the default ruleset has no way to
know: that `student` is a deliberately weak account nobody should routinely
be logging into. That's the actual point of custom detection engineering —
encoding what's normal or abnormal for *your* environment, not
re-detecting what a vendor ruleset already covers.

It builds on Wazuh's own rule `5715` ("sshd: authentication success") with
`<if_sid>`, rather than re-parsing SSH logs from scratch — layering a
specific rule on top of a general one Wazuh already provides is the normal
way to write detections. ATT&CK mapping: **T1078 (Valid Accounts)**.

> **A note on rule IDs**, since they're easy to get wrong from memory. On
> this pinned Wazuh (v4.14.7): `5715` = auth success; `5760` = a single SSH
> auth failure; `5763` = brute-force correlation (8 failures from one IP in
> 120s); `5712` is a *different* brute-force rule that keys off attempts to
> log in as a **non-existent** user, so it does **not** fire for failed
> `student` logins (`student` exists). Always confirm an ID with
> `wazuh-logtest` rather than trusting a number from a blog post.

## Loading rules safely — `reload-rules.sh`

`deploy.sh` and `reload-rules.sh` copy the file into the running manager
(`docker cp`) and restart Wazuh's services, rather than using a Compose
bind-mount (which was flaky for this stack in Stage 2).

The important part is that `reload-rules.sh` **validates the ruleset before
restarting**:

1. backs up the manager's current `local_rules.xml`;
2. copies your new file in;
3. runs `wazuh-analysisd -t` to check it parses;
4. if it's valid, restarts Wazuh; if not, **puts the old file back** and
   leaves the manager running.

That matters because a single XML typo would otherwise stop the manager
coming back up and knock the agent offline — the same kind of confusing
breakage we hit in Stage 2. Here a bad edit gives you an error message and
a still-working manager. Run it any time you edit the rules:

```bash
./reload-rules.sh
```

## Testing a rule without waiting for a real attack — `test-rules.sh`

Wazuh ships `wazuh-logtest`, which takes a raw log line and tells you which
rule (if any) it matches — no live agent or real login needed.
`test-rules.sh` runs a whole file of cases through it:

```bash
./test-rules.sh
```

Cases live in `tests/*.cases`, one per line as `EXPECT|RULE_ID|LOG LINE`
(`EXPECT` is `MATCH` or `NOMATCH`). The shipped `tests/rule-100010.cases`
checks that a `student` login fires `100010`, that an `admin` login does
**not**, and that a *failed* `student` login does **not** (it's a different
event). Every rule you write should get at least one `MATCH` and one
`NOMATCH` case — a rule you've only tested with the "yes" case is a rule
whose boundaries you don't actually know.

## Quick start

```bash
./deploy.sh        # ensures Stage 2 is up, then loads the rule
./validate.sh      # pipeline health + rule tests + a real end-to-end attack
./reload-rules.sh  # re-apply rules/local_rules.xml after editing (seconds)
./reset.sh         # full rebuild of the whole lab, then reload the rule
```

## Seeing it fire for real

```bash
./scenarios/bruteforce-then-login.sh
```

This runs from the attacker: ~12 failed `student` logins (→ `5760`/`5763`)
then one successful one (→ your `100010`). Wait ~30s, then in the dashboard
open **Threat intelligence → Threat Hunting** and look for the alert
"Successful SSH login to the monitored 'student' account". `validate.sh`
runs this same scenario and confirms the alerts actually land.

## The acceptance test

`validate.sh` proves, rather than asserts, the stage's goal:

1. **Pipeline health** — manager, endpoint and agent are up.
2. **Rule tests** — `test-rules.sh` (wazuh-logtest) passes.
3. **End-to-end** — a benign `admin` login raises **no** `100010` alert,
   then the bruteforce+login scenario **does** raise `100010` (and the
   built-in `5763`), checked against the manager's `alerts.json`.

Benign baseline noise can't trip the rule by construction: the once-a-minute
baseline activity logs in via `su`, not `sshd`, so it never reaches rule
`5715` (and therefore never reaches `100010`).

## Writing your own detection

1. Pick something to detect that's specific to this lab. Good candidates:
   the `admin` account being used interactively (should be rare), a new
   user being created on the endpoint, or a file appearing somewhere it
   shouldn't.
2. Work out what log line that behaviour produces — SSH into the endpoint
   and watch `/var/log/auth.log`, or `docker logs` the relevant service.
3. Find out whether Wazuh already decodes that log and which rule it lands
   on — feed a sample line to `wazuh-logtest` and read the `id:` and
   `description:` it reports.
4. Add a `<rule>` to `rules/local_rules.xml` with an ID ≥ 100000, usually as
   an `<if_sid>` child of the base rule you found in step 3.
5. `./reload-rules.sh`, then `./test-rules.sh`.
6. Add a `MATCH` and a `NOMATCH` case to `tests/` for your rule, and write
   down: what it detects, which log shows it, why it's written that way,
   and one thing that should **not** trigger it.

## Known limitations (by design, for a PoC)

- One worked example plus the test framework, not a rule library. Breadth
  is the Stage 3 *exercise*, not something pre-built for students.
- The single `NOMATCH` case per rule is illustrative, not a rigorous
  false-positive analysis against a large benign corpus.
- `wazuh-control restart` briefly drops the manager↔agent connection; it
  self-heals within a few seconds (same behaviour noted in Stage 2).

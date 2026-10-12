# Stage 3 Tour — Writing a Detection

**Time:** ~45 minutes for the tour itself.
**Before this session:** run `./deploy.sh` in `stage-3-detections/` ahead of
time and confirm `./validate.sh` passes. If Stage 2 is already up, Stage 3
deploys in seconds; if it isn't, the first run brings the whole Wazuh stack
up and takes 10–20 minutes — not worth spending in class.

**You'll need:** Stage 3 deployed and passing `./validate.sh`, a text
editor, a terminal, and the dashboard login from Stage 2
(`https://localhost:443`, `admin` / `SecretPassword`).

Stage 2 was about seeing telemetry exist. Today is the other half: turning
telemetry into something that tells a human "look at this." By the end
you'll have read, tested, triggered, broken, and modified a real detection
rule — the same edit → validate → reload → test loop a detection engineer
uses every day.

> 💡 **Note:** background info — read it, don't skip it.
>
> 🧪 **Try it yourself:** optional extra if you finish early.

---

## Part 0 — Orientation (3 min)

```bash
cd DELab/stage-3-detections
./validate.sh
```

Watch it work through three levels: the pipeline is healthy, the rule tests
pass, and — the real proof — a benign login raises no alert while a real
attack does. A detection that never fires is useless; one that fires on
everything is worse than useless. The acceptance test checks both.

> 💡 **Note:** Stage 3 doesn't run its own Wazuh. It uses the one Stage 2
> started and loads a rule onto it. That's why the containers are named
> `delab-...` rather than `stage3-...` — there's a single shared lab, and
> each stage adds to it.

---

## Part 1 — Read the rule before you run it (8 min)

Open `rules/local_rules.xml`. Read the comments, then the rule:

```xml
<rule id="100010" level="10">
  <if_sid>5715</if_sid>
  <user>^student$</user>
  <description>Successful SSH login to the monitored 'student' account</description>
  <mitre>
    <id>T1078</id>
  </mitre>
  <group>local_detection,valid_accounts,</group>
</rule>
```

Work out, before reading on, what each line does:

- `if_sid` — this rule only evaluates against events that already matched
  another rule. Which one, and what does *that* rule already tell you?
- `<user>` — a condition on a field Wazuh extracted from the log. What
  pattern is it matching?
- `level="10"` — severity. Wazuh's scale runs roughly 0–16; the base rule
  `5715` is only level 3, and we're deliberately raising this specific case.

> 💡 **Note:** this builds on rule `5715` (Wazuh's built-in "sshd:
> authentication success") instead of parsing the SSH log itself. Layering a
> specific rule on a general one Wazuh already provides is the normal way to
> write detections — you very rarely start from a blank log line.

> 🧪 **Try it yourself:** find rule `5715` in the shipped ruleset:
> `docker exec delab-wazuh-wazuh.manager-1 grep -A5 'id="5715"' /var/ossec/ruleset/rules/0095-sshd_rules.xml`

---

## Part 2 — Test it without attacking anything (10 min)

Test a rule the way a detection engineer actually does — feed it a sample
log line:

```bash
echo "Jan  1 00:00:00 endpoint01 sshd[1234]: Accepted password for student from 10.10.10.20 port 54321 ssh2" \
  | docker exec -i delab-wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-logtest
```

In the output, find `Rule id: '100010'` and the description, alongside the
base rule `5715` it builds on.

Now the negative case — the same line, but for `admin`:

```bash
echo "Jan  1 00:00:00 endpoint01 sshd[1234]: Accepted password for admin from 10.10.10.20 port 54321 ssh2" \
  | docker exec -i delab-wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-logtest
```

Confirm `100010` does **not** appear — `5715` still fires (a login
happened), but not your custom rule.

That's exactly what `./test-rules.sh` automates, reading its cases from
`tests/rule-100010.cases`. Run it:

```bash
./test-rules.sh
```

> 💡 **Note:** every rule should have a line that *should* trigger it and
> one that *shouldn't*. A rule you've only tested with the "yes" case is a
> rule whose boundaries you don't actually know.

---

## Part 3 — Trigger it for real (8 min)

Generate the real event instead of a synthetic one:

```bash
./scenarios/bruteforce-then-login.sh
```

This runs a burst of failed `student` logins and then one successful one,
from the attacker container. Wait ~30 seconds, then in the dashboard open
**Threat intelligence → Threat Hunting** and look for "Successful SSH login
to the monitored 'student' account". Click in and read the fields —
`agent.name`, `rule.id`, `rule.mitre.id` — and compare them to what
`wazuh-logtest` showed you in Part 2. Same rule, same fields, this time from
a real login.

> 💡 **Note:** you'll also see the built-in bruteforce alert (`5763`) from
> the failed attempts that came first. That's Wazuh's own ruleset doing its
> job — Stage 3 is about adding the detection it *couldn't* already have:
> the one that knows `student` specifically matters here.

> 🧪 **Try it yourself:** log in as `admin` from the attacker
> (`docker exec -it delab-attacker ssh admin@10.10.10.10`, password
> `AdminP@ssw0rd!`) and check Threat Hunting again. You get the base
> "authentication success", but **not** your custom alert — the real-world
> version of Part 2's negative test.

---

## Part 4 — Break it on purpose, and watch the reload catch it (6 min)

In Stage 2, a bad config could take the manager down. Stage 3's
`reload-rules.sh` validates before it restarts, so a typo can't. See it:

1. In `rules/local_rules.xml`, deliberately break the XML — e.g. delete the
   closing `</rule>` tag.
2. Reload:

   ```bash
   ./reload-rules.sh
   ```

   It should **refuse**, print the validation error, and tell you it rolled
   back. Confirm the manager is still up:
   `docker exec delab-wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status`
3. Put the `</rule>` back and reload again — this time it succeeds.

> 💡 **Note:** this is the safety net that was missing in Stage 2. The rule
> file is validated with `wazuh-analysisd -t` before any restart, so a
> mistake gives you an error message and a working manager, not a dead one.

---

## Part 5 — Change it, reload, test (6 min)

Detections get tuned as you learn more. Practise the loop on a small change:
raise the severity.

1. Change `level="10"` to `level="12"` on rule `100010`.
2. `./reload-rules.sh`
3. Re-run the Part 2 `wazuh-logtest` command and confirm the reported level
   is now `12`.

> 🧪 **Try it yourself:** add a second condition — restrict the rule to a
> source IP with `<srcip>10.10.10.20</srcip>` — then add a matching
> `tests/` case and re-run `./test-rules.sh`. If you get a tag name wrong,
> that's normal: check Wazuh's rule-syntax reference rather than guessing.

---

## Part 6 — Wrap-up (4 min)

Jot down brief answers:

1. Why does this rule build on `5715` instead of parsing the SSH log
   itself? What would you have had to write if `5715` didn't exist?
2. Name one behaviour in this lab — something the attacker or the baseline
   does — that nothing currently detects. You don't need to write the rule,
   just name the gap.
3. In Part 4, how did you know the reload had *refused* your bad rule rather
   than quietly loading it?

---

## Command cheat sheet

| What you want to do | Command |
|---|---|
| Full check (pipeline + tests + real attack) | `./validate.sh` |
| Just the rule tests | `./test-rules.sh` |
| Reload rules after editing (validated) | `./reload-rules.sh` |
| Test one log line | `echo "LOGLINE" \| docker exec -i delab-wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-logtest` |
| Fire a real attack | `./scenarios/bruteforce-then-login.sh` |
| Manager service status | `docker exec delab-wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status` |
| SSH in as student / admin | `docker exec -it delab-attacker ssh student@10.10.10.10` / `... admin@10.10.10.10` |
| Stop the lab when done (frees RAM, keeps state) | `../stop.sh` |
| Resume the lab next time (no rebuild) | `../start.sh` |
| Full rebuild of the whole lab | `./reset.sh` (slow — same as Stage 2) |

> ⚠️ **Don't run `./reset.sh` casually today** — it rebuilds the entire
> Wazuh stack from scratch, the same 10–20 minute cost as the pre-work step.
> Editing `rules/local_rules.xml` and running `./reload-rules.sh` is all you
> need for the rest of this tour.

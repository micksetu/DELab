# Stage 2 Tour — Watching the Telemetry Flow

**Time:** ~45 minutes for the tour itself.
**Before this session:** run `./deploy.sh` in `stage-2-eyes/` ahead of time
(ideally the night before, or first thing when you sit down) and leave it
running. First-time deploy clones and builds several images and can take
10–20 minutes depending on your internet connection — none of that is part
of the 45 minutes below, and there's nothing to learn from watching a
progress bar. If `./validate.sh` passes before this session starts, you're
ready.

**You'll need:** Stage 2 already deployed and passing `./validate.sh`, a
web browser, and a terminal.

This tour picks up where Stage 1 left off. The environment (attacker,
endpoint, network) is the same — what's new is a Wazuh manager, indexer,
and dashboard watching the endpoint. The goal today is to trace one idea
all the way through:

> **Activity on the endpoint → an event → Wazuh sees it → you can find it.**

As before:

> 💡 **Note:** background info — read it, don't skip it.
>
> 🧪 **Try it yourself:** optional extra if you finish early.

---

## Part 0 — Orientation (3 min)

```bash
cd DELab/stage-2-eyes
./validate.sh
```

Confirm everything passes — endpoint, attacker, manager, indexer,
dashboard all running, and the agent connected. If anything fails, sort it
out before continuing (ask for help rather than burning your 45 minutes on
troubleshooting).

Take a look at the diagram in this folder's `README.md`. The key thing
that changed from Stage 1: the endpoint now has **two** network
connections — one to the attacker (unchanged), and a new one to the Wazuh
manager, carrying telemetry only.

---

## Part 1 — Log into the dashboard (5 min)

Open a browser to:

```
https://localhost:443
```

Your browser will warn you the certificate isn't trusted — that's
expected (it's self-signed for a local lab), click through it (usually
"Advanced" → "Proceed").

Log in:

- **Username:** `admin`
- **Password:** `SecretPassword`

> 💡 **Note:** this is a fixed default baked into the Wazuh project's own
> quickstart setup, not something unique to your deployment. Fine for a
> disposable local lab; never reuse it anywhere real.

Once you're in, open the menu (☰, top-left) and find **Agents management
→ Summary**. You
should see one agent: `endpoint01`, with a green "Active" status. This
confirms what `validate.sh` already told you from the command line — now
you're seeing the same fact from the other end of the pipeline.

---

## Part 2 — Confirm the agent from both sides (5 min)

You've now seen the agent is "Active" from the manager's point of view.
Check the agent's own point of view too, back in the terminal:

```bash
docker exec stage2-endpoint /var/ossec/bin/wazuh-control status
```

You should see `wazuh-agentd`, `wazuh-logcollector`, and a few other
processes all running.

```bash
docker exec stage2-endpoint tail -20 /var/ossec/logs/ossec.log
```

Now check *what* the agent has been told to read. Wazuh only sees log
files listed in its config:

```bash
docker exec stage2-endpoint grep -B1 -A1 '/var/log/auth.log' /var/ossec/etc/ossec.conf
```

You should see a `<localfile>` entry for `/var/log/auth.log`, the file
where Linux records SSH logins and `sudo` use.

> 💡 **Note:** Wazuh's installer only adds entries for log files that
> exist when it's installed. Inside a freshly built container that file
> doesn't exist yet, so the entry was missing and SSH attacks never reached
> Wazuh. This lab's endpoint now adds it on start-up. It's a good example
> of a real monitoring gap: the agent was running and "Active" the whole
> time, it just wasn't looking at the right file.

> 💡 **Note:** `ossec.log` is the exact file (and the exact command) used to
> debug this environment's own enrollment problems while it was being
> built — troubleshooting a "why isn't this agent connecting" problem
> starts here nearly every time in a real Wazuh deployment.

---

## Part 3 — Find baseline activity in the dashboard (10 min)

Back in the dashboard, open the menu (☰) and go to **Explore → Discover**.
This is a raw search over everything the manager has received.

In the search bar, try:

```
agent.name:endpoint01
```

You should see a stream of events. Click into a few of them and expand
the fields — look for:

- `agent.name` / `agent.id`
- `rule.description` or `full_log`
- `timestamp`

> 💡 **Note:** Stage 1's `baseline_activity.sh` cron job has been quietly
> running the whole time. Somewhere in this stream are the `student` user
> logins it generates every minute. See if you can find one — search for:

```
agent.name:endpoint01 AND full_log:*student*
```

> 💡 **Note on time zones:** the containers log in UTC, but the
> dashboard shows times in your browser's local time. In Ireland in
> summer (UTC+1), an event logged at `10:00` inside the endpoint appears as
> `11:00` in the dashboard. Nothing is wrong. Keep it in mind whenever you
> line up a dashboard event with a log file.

> 🧪 **Try it yourself:** narrow the time range (top-right of the
> dashboard) to the last 15 minutes and count how many baseline events you
> see. Does the number roughly match "once a minute"?

---

## Part 4 — Generate an attack and go find it (12 min)

Time to put something deliberate into the pipeline. From a terminal:

```bash
docker exec -it stage2-attacker bash
./ssh_bruteforce.sh
exit
```

Wait about 30 seconds for the events to arrive, then back in the
dashboard's Discover view, search:

```
agent.name:endpoint01 AND full_log:*sshd*
```

You're looking for failed password attempts against `student`. Expand a
few and look at the same fields as before.

> 💡 **Note:** Wazuh ships with a large set of **built-in** detection
> rules out of the box — including ones that already recognize SSH
> authentication failures. So you may see some of these show up as actual
> **alerts**, not just raw events, even though nobody on this course wrote
> a detection rule yet. That's the built-in ruleset doing its job.
>
> This matters for what's coming next: Stage 3 isn't about detecting
> *anything* — it's about detecting the things that **aren't** already
> covered, and understanding what a rule actually does by writing your
> own instead of only relying on someone else's.

Check **Threat intelligence → Threat Hunting** (menu ☰) rather than raw
Discover, and see if the bruteforce shows up there as a triggered alert,
with a rule ID and description.

> 🧪 **Try it yourself:** run `./port_scan.sh` from the attacker too. Does
> a port scan show up as an event on the endpoint? Think about *why* it
> might not (hint: what would actually have to log something for Wazuh to
> see it — and does a scan touch the endpoint's own logs at all?).

---

## Part 5 — See it break, on purpose (5 min)

Stop the agent and watch what happens:

```bash
docker exec stage2-endpoint /var/ossec/bin/wazuh-control stop
```

Back in the dashboard's **Agents management → Summary**, refresh — `endpoint01`
should now show as "Disconnected" after a short delay.

Start it again:

```bash
docker exec stage2-endpoint /var/ossec/bin/wazuh-control start
```

and confirm it goes back to "Active".

> 💡 **Note:** this is worth internalizing now, cheaply, rather than
> discovering it during an assessment: an agent going quiet doesn't mean
> "nothing is happening" — it might mean the *monitoring itself* has
> stopped. A real SOC watches for this too.

---

## Part 6 — Wrap-up (5 min)

Jot down brief answers:

1. Trace one specific event from Part 3 or 4 all the way through: what
   happened on the endpoint, what process picked it up, and where did you
   find it in the dashboard?
2. What's the difference between an **event** and an **alert**? Did
   everything you found in Part 4 count as both?
3. In Part 5, how did you know the agent had actually stopped, versus just
   being slow to report? What would you check to be sure?

---

## Command cheat sheet

| What you want to do | Command |
|---|---|
| Check the whole environment is healthy | `./validate.sh` |
| Check the agent's own status | `docker exec stage2-endpoint /var/ossec/bin/wazuh-control status` |
| Stop / start the agent | `docker exec stage2-endpoint /var/ossec/bin/wazuh-control stop` / `... start` |
| Tail the agent's log | `docker exec stage2-endpoint tail -20 /var/ossec/logs/ossec.log` |
| Tail the manager's log | `docker exec stage2-eyes-wazuh-wazuh.manager-1 tail -20 /var/ossec/logs/ossec.log` |
| Run the recon scan | (inside `stage2-attacker`) `./port_scan.sh` |
| Run the bruteforce | (inside `stage2-attacker`) `./ssh_bruteforce.sh` |
| Wipe and rebuild everything | `./reset.sh` (takes a while — see note below) |

> 🧪 **If you finished early:** open **Threat Hunting** and look for a
> rule with a name involving "SCA" or "Security Configuration Assessment"
> — that's a separate built-in module quietly auditing the endpoint's
> configuration against a CIS benchmark, running the whole time, that we
> haven't talked about yet. See what it's flagged.

> ⚠️ **Don't run `./reset.sh` casually today** — it rebuilds the entire
> Wazuh stack from scratch (cloning, building, certs, indexer startup all
> over again), the same 10–20 minute cost as the pre-work step. Only run
> it if you've genuinely broken something and need a clean baseline.

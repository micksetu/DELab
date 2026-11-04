# Stage 5 Tour — From Detection to Response

**Time:** ~40 minutes for the tour itself.
**Before this session:** run `./deploy.sh` in `stage-5-response/` ahead of time
and confirm `./validate.sh` passes. If Stages 2–4 are already up, Stage 5 adds
its response config in seconds; from cold it brings the whole stack up and can
take 10–20 minutes — not worth spending in class.

**You'll need:** Stage 5 deployed and passing `./validate.sh`, a terminal, and
the Wazuh dashboard login:
- Wazuh: `https://localhost:443` — `admin` / `SecretPassword`

So far the lab has watched and investigated. Today it *acts*. A detection stops
being a notification you read after the fact and becomes the trigger for an
automatic defence — the attacker gets locked out while the attack is still
happening.

> 💡 **Note:** background info — read it, don't skip it.
>
> 🧪 **Try it yourself:** optional extra if you finish early.

---

## Part 0 — Orientation (3 min)

```bash
cd DELab/stage-5-response
./validate.sh
```

Everything should pass: the response path is in place, a brute force produces a
**real block** (the attacker can't even ping the endpoint), and the block
**lifts itself** after 60 seconds. That last part matters — a response that
never undoes itself would leave the next person with a half-broken lab.

---

## Part 1 — Read the response before you run it (6 min)

Open `active-response/local_ar.conf`. It's two small blocks:

- a **`<command>`** naming `firewall-drop` — a script that ships with the Wazuh
  agent and runs an `iptables` DROP;
- an **`<active-response>`** binding that command to **rule 5763** (the SSH
  brute-force rule from Stage 3), set to run **locally** (on the agent that saw
  the attack) for **60 seconds**.

> 💡 **Note:** the responder runs on the *endpoint*, not the manager. The manager
> detects and decides; the agent that saw the attack is where the block lands.
> That's why the attacker is cut off from the machine it's actually hitting.

---

## Part 2 — Trigger it and watch the block land (10 min)

Open two terminals. In the first, tail the endpoint's response log:

```bash
docker exec delab-endpoint tail -f /var/ossec/logs/active-responses.log
```

In the second, brute-force the `student` account from the attacker (wrong
password, several times in a row):

```bash
docker exec -it delab-attacker ssh student@10.10.10.10
```

(try a few wrong passwords; `exit` or Ctrl-C between tries). After ~8 failures
the first terminal shows `firewall-drop … "command":"add"` with the attacker's
IP. Now prove it's real — from a third shell, or after leaving the ssh attempt:

```bash
docker exec delab-attacker ping -c2 10.10.10.10     # now fails - you're blocked
docker exec delab-endpoint iptables -S INPUT        # the DROP rule for 10.10.10.20
```

> 🧪 **Try it yourself:** before the 60 seconds are up, try to SSH to the
> endpoint from the attacker again. What happens, and why — did your password
> even get checked this time?

---

## Part 3 — Watch the lab heal (5 min)

Keep the first terminal tailing. About a minute after the block, you'll see
`firewall-drop … "command":"delete"`, and:

```bash
docker exec delab-attacker ping -c2 10.10.10.10     # reachable again
docker exec delab-endpoint iptables -S INPUT        # the DROP rule is gone
```

> 💡 **Note:** auto-expiry is a deliberate design choice, not laziness. A
> permanent block is a denial-of-service you inflict on yourself the moment the
> response fires on a false positive. Think about where you'd want permanent vs
> temporary in a real estate.

---

## Part 4 — The defender's view (6 min)

In the Wazuh dashboard (**Threat intelligence → Threat Hunting**), find the
rule 5763 alert that triggered all this. Line it up with the `active-responses.log`
you watched:

- the **alert** is the decision ("this is a brute force");
- the **log** is the action ("I blocked 10.10.10.20, then released it").

> 🧪 **Try it yourself:** can you tell, from the dashboard alone, that a response
> was taken? Where would an analyst look to confirm the block actually happened
> on the endpoint?

---

## Part 5 — Write your own response (8 min)

The core exercise, and the one that earns marks in the assessment. Pick a
different technique from your incident and automate a response to it.

1. Identify a rule that fires for your technique (use Stage 3's approach, or an
   existing Wazuh rule id).
2. In `active-response/local_ar.conf`, add another `<active-response>` block
   bound to that `rules_id`.
3. `./reload-response.sh`, then trigger your technique and watch the log.

Write down, in your own words:

- Why is this detection one you'd be comfortable responding to **automatically**?
- What's the blast radius if it fires on benign activity?
- Would you choose a different timeout, or a different action than firewall-drop?

> 💡 **Note:** not every detection should auto-respond. Part of the skill is
> deciding which ones are safe to automate and which need a human in the loop.

---

## Part 6 — Where this goes next (2 min)

`firewall-drop` is one action, triggered by one rule, on one host. Real SOCs
chain responses across tools — block, *then* automatically collect evidence,
*then* notify. That orchestration is where a **SOAR platform** (such as
*Shuffle*) comes in: a Wazuh alert triggers a playbook that, for example, kicks
off a Velociraptor collection automatically. It's an optional add-on beyond
Stage 5 — if you're chasing the top band, building that is your avenue.

---

## Command cheat sheet

| What you want to do | Command |
|---|---|
| Check everything (block + recovery) | `./validate.sh` |
| Re-apply after editing the response | `./reload-response.sh` |
| Trigger the response (brute force) | `docker exec -it delab-attacker ssh student@10.10.10.10` |
| Watch responses live | `docker exec delab-endpoint tail -f /var/ossec/logs/active-responses.log` |
| See the firewall block | `docker exec delab-endpoint iptables -S INPUT` |
| Prove you're blocked | `docker exec delab-attacker ping -c2 10.10.10.10` |
| Full wipe and rebuild | `./reset.sh` (slow — same as Stage 2/3/4) |

> ⚠️ **Don't run `./reset.sh` casually today** — it rebuilds Wazuh *and*
> Velociraptor from scratch (10–20 min). Nothing in this tour needs it.

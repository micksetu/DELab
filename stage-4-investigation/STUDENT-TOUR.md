# Stage 4 Tour — From Alert to Investigation

**Time:** ~45 minutes for the tour itself.
**Before this session:** run `./deploy.sh` in `stage-4-investigation/`
ahead of time and confirm `./validate.sh` passes. If Stages 2–3 are already
up, Stage 4 adds Velociraptor in a minute or two; from cold it brings the
whole stack up and can take 10–20 minutes — not worth spending in class.

**You'll need:** Stage 4 deployed and passing `./validate.sh`, a terminal,
and both dashboard logins:
- Wazuh: `https://localhost:443` — `admin` / `SecretPassword`
- Velociraptor: `https://localhost:8889` — `admin` / `VelociraptorLab123!`

> **Apple Silicon Mac:** if the Velociraptor server crashes when you deploy,
> turn on Docker Desktop → Settings → General → "Use Rosetta for x86/amd64
> emulation" and redeploy. See Stage 4's `README.md` for why.

Every stage so far has added one capability. Today you connect them: an
alert from Stage 3 becomes the *starting point* of an investigation, not
the end of the story. Wazuh tells you something happened; Velociraptor is
how you find out what it actually means.

> 💡 **Note:** background info — read it, don't skip it.
>
> 🧪 **Try it yourself:** optional extra if you finish early.

---

## Part 0 — Orientation (3 min)

```bash
cd DELab/stage-4-investigation
./validate.sh
```

Everything should pass: the pipeline is healthy, the Velociraptor client is
**enrolled**, and the server already has live host facts from the endpoint.
Re-read the Wazuh-vs-Velociraptor table in this folder's `README.md` if it
isn't settled in your head — one watches continuously and alerts, the other
answers specific questions about one machine on demand.

---

## Part 1 — Log into Velociraptor and find your endpoint (5 min)

Open `https://localhost:8889`, click through the certificate warning, and
log in. In the search box, look for `endpoint01` and click into it — the
same machine you've attacked and defended since Stage 1, through a new lens:
not "what alerts fired" but "what does this machine look like right now."

> 💡 **Note:** there's no "Security events" feed here the way there was in
> Wazuh. Velociraptor doesn't generate alerts on its own — it waits for you
> to ask. Less noise, but nothing happens until an investigator drives it.

---

## Part 2 — Generate the alert, then go find it (7 min)

From the attacker:

```bash
docker exec -it delab-attacker ssh student@10.10.10.10
```

(password `password123`). `exit` once to leave the SSH session.

In the Wazuh dashboard (**Threat intelligence → Threat Hunting**), confirm
the Stage 3 alert fired: "Successful SSH login to the monitored 'student'
account". That's your **lead**. Everything from here answers: *given this
alert, what actually happened on the box?*

---

## Part 3 — Run your first collection (8 min)

Back on the `endpoint01` client page in Velociraptor, find **Collected
Artifacts** → the "+" / **New Collection** button (wording varies by
version), and run:

- **`Generic.Client.Info`** — hostname, OS, IPs. Confirms you've got the
  right machine. Boring, but "confirm identity before you trust the data"
  is a habit worth building.
- **`Linux.Sys.Users`** — the full user list on the endpoint.

> 🧪 **Try it yourself:** before you look, predict what users you expect
> (from having built the lab in Stages 1–3). Then check the collection.

---

## Part 4 — Investigate the actual login (10 min)

The core exercise. Using Velociraptor, answer these about the login you
triggered in Part 2 — you choose which artefacts to run:

1. **What processes were running around the login?** Try
   `Generic.System.Pstree`.
2. **What's in the `student` account's home directory?** Try
   `Linux.Search.FileFinder`, searching under `/home/student`.
3. **Anything that looks like it shouldn't be there** — files, timestamps,
   anything inconsistent with "an account that's barely used"?

Write down, in your own words: **what did Velociraptor show you that the
Wazuh alert alone did not?**

> 💡 **Note:** you already know some answers (the `baseline_activity.sh`
> cron job, `notes.txt`) because you built this box. Real investigations
> work the same way — separating "known/expected" from "unexplained." Note
> which artefacts would have told you this even if you *hadn't* known.

---

## Part 5 — A taste of VQL (7 min)

Every collection above is **VQL** (Velociraptor Query Language) underneath.
Driving it yourself is where investigation becomes *hunting*. In the client
page, open a **Notebook** (or the VQL cell on the Hunt/Notebook view) and
run:

```sql
SELECT Name, Pid, Ppid, CommandLine FROM pslist()
```

That's the live process list as a query. Now make it *answer a question* —
narrow it to something interesting:

```sql
SELECT Name, Pid, CommandLine FROM pslist() WHERE Name =~ "ssh"
```

> 💡 **Note:** the same VQL runs headlessly against the server's API — see
> `README.md`'s "Headless VQL" section. That's the route to writing a query
> that finds a *specific* technique's footprint rather than running a canned
> artefact — exactly the kind of independent work that earns higher marks in
> the assessment.

> 🧪 **Try it yourself:** write one VQL query that would show a *new file*
> appearing under `/home/student` in the last hour (hint: look at the
> `glob()` plugin and file modification times).

---

## Part 6 — The two tools together, and the gaps (5 min)

Open the alert in Wazuh and your Velociraptor collections side by side (two
tabs).

> 🧪 **Try it yourself:** find one fact about the incident **only**
> Velociraptor could tell you, and one thing Wazuh surfaced that your
> collections did **not**. If you can't find one of these, that's worth
> noting too — it might mean you need a different artefact, or that the
> activity left no trace either tool can see.

This "what did the defender **not** see?" question is exactly what the
assessment rewards — hold onto your answer.

---

## Part 7 — Wrap-up (4 min)

Jot down brief answers:

1. If you had only Wazuh's alert, what could you **not** have concluded
   about this incident?
2. Which single Velociraptor artefact (or VQL query) gave you the most
   useful evidence, and why that one?
3. This lab has one endpoint. What would change about the *process* — not
   the tools — if you were investigating the same alert across 50 machines?

---

## Command cheat sheet

| What you want to do | Command |
|---|---|
| Check everything (pipeline + client enrolled) | `./validate.sh` |
| Trigger the Stage 3 alert | `docker exec -it delab-attacker ssh student@10.10.10.10` |
| Velociraptor client log | `docker exec delab-endpoint tail -20 /var/log/velociraptor-client.log` |
| Wazuh agent log | `docker exec delab-endpoint tail -20 /var/ossec/logs/ossec.log` |
| List enrolled clients (headless VQL) | `docker exec delab-velociraptor velociraptor --api_config /etc/velociraptor/admin.api.yaml query "SELECT client_id, os_info.hostname FROM clients()"` |
| Wipe and rebuild everything | `./reset.sh` (slow — same as Stage 2/3) |

> ⚠️ **Don't run `./reset.sh` casually today** — it rebuilds Wazuh *and*
> Velociraptor from scratch (10–20 min). Nothing in this tour needs it.

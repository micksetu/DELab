# Stage 1 Tour — Kicking the Tyres

**Time:** ~30–45 minutes (go at your own pace — some parts have optional extras if you finish early)
**You'll need:** Docker Desktop running, and this repo unzipped somewhere on your machine.
**Where to work:** Docker Desktop's built-in **Terminal** (not a separate app) — open Docker Desktop, then use its terminal panel, or open a normal terminal and confirm `docker` works by typing `docker --version`.

This tour has two goals: get comfortable with basic Docker/command-line workflow, and get familiar with the layout of the range you'll be using for the rest of the module. You don't need to understand *everything* you see today — just enough to navigate confidently.

Throughout, boxes like this flag things worth noticing:

> 💡 **Note:** background info — read it, don't skip it.

> 🧪 **Try it yourself:** an optional extra if you want to push further.

---

## Part 0 — Orientation (3 min)

Open a terminal and move into the Stage 1 folder:

```bash
cd detection-engineering-lab/stage-1-environment
ls
```

You should see `docker-compose.yml`, `deploy.sh`, `reset.sh`, `validate.sh`, and two folders: `attacker/` and `endpoint/`.

> 💡 **Note:** `docker-compose.yml` is the single file that describes this whole environment — what containers exist, what network they're on, what IP addresses they get. You'll never need to edit it, but it's worth a quick look:

```bash
cat docker-compose.yml
```

---

## Part 1 — Deploy the environment (5 min)

```bash
./deploy.sh
```

Watch the output. The first run will take a minute or two — Docker is building two images from scratch (downloading a base Linux image, installing packages).

Once it finishes, switch to **Docker Desktop's graphical view** and look at the **Containers** tab. You should see two containers running: `stage1-endpoint` and `stage1-attacker`. Click into `stage1-endpoint` and look at the **Logs** tab in the GUI — this is the same thing `docker logs` shows you from the command line, just with a UI wrapped around it.

Back in the terminal, the command-line equivalent of that container list is:

```bash
docker ps
```

> 💡 **Note:** `docker ps` only shows *running* containers. `docker ps -a` shows everything, including stopped ones — useful later if a container crashes and you need to see it in the list to investigate why.

---

## Part 2 — Look inside the endpoint (7 min)

This is the "victim" machine. Get a shell inside it:

```bash
docker exec -it stage1-endpoint bash
```

You're now *inside* the container, as root. Have a look around like you would on any Linux box:

```bash
whoami
hostname
cat /etc/os-release
```

Check who lives here:

```bash
cat /etc/passwd | grep -E "admin|student|websvc"
id admin
id student
```

Look at the basic files that were planted:

```bash
ls -la /home/student
cat /home/student/notes.txt
cat /opt/baseline/readme.txt
ls /var/www/html
```

Check what services are actually running:

```bash
ps aux
```

You should be able to spot `sshd`, a Python process serving the website, and `cron`.

Now look at the baseline activity log — this has been quietly building up since the container started:

```bash
tail -20 /var/log/baseline.log
```

> 💡 **Note:** that log is a cron job firing every minute, simulating the `student` user logging in and doing small things. This is deliberate background noise — later stages will need to tell this apart from an actual attacker. Also have a look at:

```bash
tail -20 /var/log/auth.log
```

This is where Linux logs authentication activity — logins, sudo use, and (later) failed SSH attempts. Remember this file; it matters a lot from Stage 2 onwards.

When you're done exploring, leave the container without stopping it:

```bash
exit
```

> 🧪 **Try it yourself:** create a file inside `/home/student` while you're in there, then run `./reset.sh` later in Part 6 and check whether it survives. (Spoiler: it won't — that's the point.)

---

## Part 3 — Look inside the attacker (5 min)

```bash
docker exec -it stage1-attacker bash
```

```bash
ls /opt/scripts
cat port_scan.sh
cat ssh_bruteforce.sh
```

Run the recon scan against the endpoint:

```bash
./port_scan.sh
```

You should see port 22 (SSH) and port 80 (web) reported as open, along with what service `nmap` thinks is running on each.

Now try the bruteforce script against the intentionally weak `student` account:

```bash
./ssh_bruteforce.sh
```

`hydra` will work through the wordlist and should report a valid password for `student`.

> 💡 **Note:** this isn't a trick — the `student` account really does have a weak password on purpose, so there's something for an attack script to succeed against. Go back to the endpoint's `/var/log/auth.log` afterwards (Part 2) and see if you can spot the failed login attempts this just generated.

Now use the password hydra found to log in manually:

```bash
ssh student@10.10.10.10
```

Have a poke around as `student`, then:

```bash
exit
```

to leave the SSH session, and

```bash
exit
```

again to leave the attacker container.

> 🧪 **Try it yourself:** run `./port_scan.sh` a second time and compare — does anything change? What would you expect a defender to notice about *two* scans close together versus one?

---

## Part 4 — The network in between (5 min)

Back on your host machine (not inside a container):

```bash
docker network ls
```

Find the one that isn't the default Docker networks (it'll be named something like `stage-1-environment_range-net`). Inspect it:

```bash
docker network inspect stage-1-environment_range-net
```

Look for the `"Containers"` section — you'll see both `stage1-endpoint` and `stage1-attacker` listed with their IP addresses (`10.10.10.10` and `10.10.10.20`).

> 💡 **Note:** this network is deliberately cut off from the internet and from your host's other networks (`internal: true` in the compose file). That's what "isolated" means here in practice — attack traffic generated inside the range has nowhere else to go.

---

## Part 5 — Validate and reset (5 min)

Run the automated check:

```bash
./validate.sh
```

Read through what it's actually checking — container status, network reachability, the web and SSH services, and the baseline log. This is the same kind of thinking you'll be doing manually in later stages, just automated.

Now destroy the environment and rebuild it from scratch:

```bash
./reset.sh
```

Once it's back up, run `./validate.sh` again to confirm it passes on a freshly rebuilt environment. If you made a file inside `/home/student` in Part 2, check now — it should be gone.

> 💡 **Note:** this reset-to-baseline behaviour is the whole point of the design. Nothing you do to a running container is precious — if you break something experimenting, `./reset.sh` gets you back to a known-good starting point in under a minute.

---

## Part 6 — Wrap-up (5 min)

Before you finish, jot down brief answers to these (you'll want them later, and they're good practice for the write-ups you'll be doing from Stage 3 onward):

1. What are the three main "moving parts" of this environment, and how do they relate to each other?
2. Where did you see evidence of the SSH bruteforce attempt, and where did you see evidence of the baseline "normal user" activity? What's different about how they'd look in a log?
3. Why does resetting wipe your changes but not the environment's overall structure? What's actually being thrown away versus what's being rebuilt?

---

## Command cheat sheet

| What you want to do | Command |
|---|---|
| See running containers | `docker ps` |
| See all containers, including stopped | `docker ps -a` |
| Get a shell inside a container | `docker exec -it <container> bash` |
| See a container's logs | `docker logs <container>` |
| Follow logs live | `docker logs -f <container>` |
| List Docker networks | `docker network ls` |
| Inspect a network | `docker network inspect <name>` |
| Start the environment | `./deploy.sh` |
| Check the environment is healthy | `./validate.sh` |
| Wipe and rebuild from baseline | `./reset.sh` |
| Leave a container shell | `exit` |

> 🧪 **If you finished early:** try `docker stats` while both containers are running to see live CPU/memory use, or `docker inspect stage1-endpoint` and skim the JSON it dumps out — most of it won't mean much yet, but the shape of it (config, network settings, mounts) will become more familiar as the module goes on.

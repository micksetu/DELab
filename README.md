# Detection Engineering & Incident Response Teaching Lab

This package contains the confirmed-working versions of Stages 1 to 3.

| Stage | Name          | Status      |
|-------|---------------|-------------|
| 1     | Environment   | ✅ included, validated |
| 2     | Eyes (Wazuh)  | ✅ included, validated |
| 3     | Detections    | ✅ included, validated |
| 4     | Investigation (Velociraptor) | not yet built |
| 5     | Incident      | not yet built |

## Getting the lab

```bash
git clone https://github.com/micksetu/DELab.git
cd DELab
```

Start with [`stage-1-environment/`](./stage-1-environment/README.md), then
[`stage-2-eyes/`](./stage-2-eyes/README.md), then
[`stage-3-detections/`](./stage-3-detections/README.md).

Stages 2 and 3 share one running environment (containers named `delab-*`):
Stage 2 brings the Wazuh stack up, and Stage 3 layers a custom detection
rule onto it rather than starting a second copy.


## Stopping and resuming

When you're done for a session, free the RAM without losing state:

```bash
./stop.sh    # stop the lab's containers (keeps them; frees RAM/CPU)
./start.sh   # resume next time, no rebuild
```

Both act only on the lab's own `delab-*` containers. Use a stage's
`./reset.sh` only when you want a clean baseline rebuilt from scratch.

**Note on isolation:** containers share the host kernel. "Isolated" here
means a private Docker bridge network cut off from your other networks
and the internet at runtime — it is a teaching sandbox, not a hardened
security boundary. Don't run this on a machine with anything sensitive on
it.

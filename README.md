# Detection Engineering & Incident Response Teaching Lab

A staged, disposable cyber range for teaching detection engineering and DFIR.
Built stage-by-stage; each stage must work before the next is added.

| Stage | Name          | Status      |
|-------|---------------|-------------|
| 1     | Environment   | ✅ this repo |
| 2     | Eyes (Wazuh)  | not yet built |
| 3     | Detections    | not yet built |
| 4     | Investigation (Velociraptor) | not yet built |
| 5     | Incident      | not yet built |

Start with [`stage-1-environment/`](./stage-1-environment/README.md).

**Note on isolation:** containers share the host kernel. "Isolated" here means
a private Docker bridge network cut off from your other networks and the
internet at runtime — it is a teaching sandbox, not a hardened security
boundary. Don't run this on a machine with anything sensitive on it.

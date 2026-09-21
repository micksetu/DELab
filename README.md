# Detection Engineering & Incident Response Teaching Lab

This package contains the confirmed-working versions of Stages 1 and 2.

| Stage | Name          | Status      |
|-------|---------------|-------------|
| 1     | Environment   | ✅ included, validated |
| 2     | Eyes (Wazuh)  | ✅ included, validated |
| 3     | Detections    | not included in this package |
| 4     | Investigation (Velociraptor) | not yet built |
| 5     | Incident      | not yet built |

Start with [`stage-1-environment/`](./stage-1-environment/README.md), then
[`stage-2-eyes/`](./stage-2-eyes/README.md).

**Note on isolation:** containers share the host kernel. "Isolated" here
means a private Docker bridge network cut off from your other networks
and the internet at runtime — it is a teaching sandbox, not a hardened
security boundary. Don't run this on a machine with anything sensitive on
it.

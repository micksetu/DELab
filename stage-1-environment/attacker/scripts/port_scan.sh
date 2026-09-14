#!/bin/bash
# Example Stage 1 activity: reconnaissance scan of the endpoint.
TARGET=${1:-10.10.10.10}
echo "[*] Scanning $TARGET..."
nmap -sV -p- "$TARGET"

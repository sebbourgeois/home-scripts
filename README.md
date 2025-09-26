# home-scripts

Collection of small, task-focused scripts for home LAN and desktop automation. Each script lives in its own folder with its own README and (optionally) a Makefile.

## Available Scripts
- nordlayer-allow-local-lan/fix-nordlayer-local-lan.sh — Re-route your local LAN outside a NordLayer full-tunnel on Ubuntu 24.04. The script sets up a dedicated policy routing table (`lan`, id 100) and a high-priority rule so traffic destined for your LAN subnet uses your local interface instead of the VPN. Your NordLayer organization must allow Local Network Access for this to work.

---

To add a new script, create a folder at the repo root with its own README and optionally a Makefile, then run `make sync-readme` to refresh this list.

# CZBot

Fork of LUA TrotsBot which is a fork of Woobs Modbot

Base documentation: [README](docs/README.md)

**Development:** To have the version string updated on each commit, install the pre-commit hook: `cp scripts/git-hooks/pre-commit .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit` (or run `./scripts/install-hooks.sh` from the repo root).

- Completely refactored to be a state machine based action processing engine
- Removed all dependancy on DanNet and EQBC/NetBots and replaced with MQRemote and MQCharinfo which are Actors based
- CZBot peers coordinate via a dedicated **Actor mailbox** (`lib/czactor.lua`): OT add claims, MA/MT handoff, `/cz followme`, and `/cz camphere`

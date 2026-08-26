# ArenaChillPrep
![banner](docs\curseforge\project-banner.png)

Automatically hands crafted items to your arena partner during **arena preparation** in World of Warcraft: TBC Anniversary (Classic).

Currently supports **Warlock** and **Mage**:

- **Warlock** — auto-passes **Healthstones** (all ranks, default: Major + Master) to your partner.
- **Mage** — runs pre-arena **prep workflows**: conjures food, water and Mana Emeralds, casts buffs (Arcane Intellect/Brilliance, Amplify/Dampen Magic), armors and wards, and opens a Ritual of Refreshment. More classes and items are planned.

> For developers and AI agents: technical docs live in `AGENTS.md` and the `.ai/` directory (context and architecture). `README.md` is for players.

## How it works

While the arena preparation buff is active:

1. Detects your arena bracket (**2v2 / 3v3 / 5v5**) — by default the addon works in **2v2 only** (the other brackets can be enabled in settings; the checkboxes are locked for v0.1).
2. Scans your bags for the configured healthstones.
3. As soon as every selected rank is ready (default: a **Major** and a **Master**), it **automatically opens a trade** with your teammate and places the stones into the window.
4. Remembers who already received items — **one trade per partner per arena**.
5. Stops trading **15 seconds before the gates open** (configurable) so you never send a trade mid-fight.

The addon only acts during arena preparation, never in combat, and never sends gold.

## Prep workflows

For **Mage** (and Warlock) the addon ships a set of **default prep workflows** you can run before the gates open. Each workflow is an ordered list of steps that the addon executes for you:

- **Conjure** food, water and Mana Emeralds (`createItem` steps).
- **Cast** buffs, armors and wards on yourself or party members (`cast` steps, target `player` / `party1`…`party4`).
- **Ritual of Refreshment** to drop a refreshment table.

Defaults cover the common brackets — `2s standard`, `2s with healer`, `3s standard`, `3s pom pyro`, `5s standard` — and you can edit, clone or add your own from Interface Options → **AddOns → ArenaChillPrep → Workflows**. Bind a workflow to a key and fire it once during prep; the engine walks the steps in order and skips anything already active.

## Slash commands

| Command | Action |
|---|---|
| `/acp` | Open settings (Interface Options → AddOns → ArenaChillPrep → Autotrade) |
| `/acp enable` / `/acp disable` | Enable/disable the addon |
| `/acp status` | Show current state: buff active, bracket, remaining time, item counts, partner |
| `/acp debug` | Toggle verbose logging (useful for reporting issues) |

## Configuration

Interface Options → **AddOns → ArenaChillPrep → Autotrade**:

- **General** — master switch, auto-accept (with tooltip).
- **Arena brackets** — which brackets auto-trade is active in (2v2 by default; 3v3/5v5 locked in v0.1).
- **Ranks to pass** — one checkbox per healthstone rank (toggling a rank covers both item-ID variants).
- **Timing** — trade delay after items appear (default 1.5 s); stop trading N seconds before the gates open (default 15).

All settings persist between sessions.

## Requirements

- World of Warcraft: TBC Anniversary (Interface 20506).
- A Warlock (healthstones) or Mage (conjured items + buffs) during arena preparation.
- No libraries required.

## Known limits (v0.1)

- Warlock + Mage only.
- 2v2 only in the UI (3v3/5v5 can be enabled in settings).
- The addon does **not** craft items on its own — Warlock/Mage prep workflows conjure or cast during prep, but you start the workflow.

## Development

See `AGENTS.md` → `.ai/` (context, architecture, and how to add new classes/items).

## Changelog

See `CHANGELOG.md`.

## License

MIT — see `LICENSE`.

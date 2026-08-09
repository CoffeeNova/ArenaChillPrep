# ArenaChillPrep

Automatically hands crafted items to your arena partner during **arena preparation** in World of Warcraft: TBC Anniversary (Classic).

Currently supports **Warlock** — passes **Healthstones** (all ranks, default: Major + Master). More classes and items are planned.

> For developers and AI agents: technical docs live in `AGENTS.md` and the `.github/` directory (context and architecture). `README.md` is for players.

## How it works

While the arena preparation buff is active:

1. Detects your arena bracket (**2v2 / 3v3 / 5v5**) — by default the addon works in **2v2 only** (the other brackets can be enabled in settings; the checkboxes are locked for v0.1).
2. Scans your bags for the configured healthstones.
3. As soon as every selected rank is ready (default: a **Major** and a **Master**), it **automatically opens a trade** with your teammate and places the stones into the window.
4. Optionally auto-accepts the trade (off by default).
5. Remembers who already received items — **one trade per partner per arena**.
6. Stops trading **15 seconds before the gates open** (configurable) so you never send a trade mid-fight.

The addon only acts during arena preparation, never in combat, and never sends gold.

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
- A Warlock with healthstones crafted during arena preparation.
- No libraries required.

## Known limits (v0.1)

- Warlock + healthstones only.
- 2v2 only in the UI (3v3/5v5 can be enabled in settings).
- The addon does **not** craft items — craft them yourself during prep.

## Development

See `AGENTS.md` → `.github/` (context, architecture, and how to add new classes/items). Dev-only sandbox tests live in `Tests/`.

## Changelog

See `CHANGELOG.md`.

## License

MIT — see `LICENSE`.

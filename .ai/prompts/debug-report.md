# Debug report request

Use this template when the addon misbehaves and you need a structured in-game report from the user. Paste it as your message to the user (filling nothing — it's self-contained). The `log-interpreter` agent can then analyze the response.

---

To debug this, I need a structured in-game report. Please do exactly this:

1. **`/reload`** (apply latest code).
2. **`/acp debug`** (enable verbose logging — you should see `ACP: Debug logging: on`).
3. **Reproduce** the issue: [describe the exact steps, e.g. "queue 2v2 skirmish with a partner, wait for the prep buff, craft a Master Healthstone"].
4. **Right after**, run **`/acp status`** and copy its output.
5. Paste back:
   - the **log output** (from step 2 onward, including timestamps — they let me correlate actions with events),
   - the **`/acp status`** output,
   - any **error popups** (the full `Message/Stack/Locals` text).

Useful extra dumps (only if asked or if they seem relevant):
- `/dump ArenaChillPrepDB.items.healthstone.ranks` — current rank settings,
- `/dump ArenaChillPrepDB` — full saved variables.

Notes:
- The 0.5 s ticker produces a LOT of debug lines while the prep buff is active — that's expected.
- If `/acp debug` output resets after `/reload`, re-run it after the reload (the flag is runtime-only).

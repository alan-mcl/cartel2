# Plotlines

**Status:** Runtime plumbing only. Arc content lives in [plotlines.md](../../setting/plotlines.md) as ideas; no shipped plotlines yet.

Plotlines are optional background arcs. Each arc is a small state machine in [`plotlines.json`](../../../data/catalog/plotlines.json). The game stores **instances** (current state, GST timestamp when that state was entered, and string flags) in the save envelope under `subsystems.plotlines`. Definitions are not duplicated in saves.

## State machine

- **`initial`** — starting state id.
- **`states`** — map of state id → state object.
- **`terminal`** — when true on a state, no transitions run.
- **`transitions`** — ordered list; **first match wins** for a given stimulus. After a transition, the same stimulus is re-evaluated on the new state (up to four steps) so a branch can chain in one action.
- **`messages`** — optional flavour lines for ticker channels while in this state.
- **`gigs`** — optional desk offers while in this state (API only until a unified gig UI exists).

### Triggers (`when.kind`)

| Kind | Fired by |
|------|----------|
| `event` | `GameSession.events` / `Simulation.dispatch_event` — requires `type` matching [`SimEvent`](../../../scripts/gameplay/sim_event.gd); optional extra keys must equal the event payload (`habitat_id`, `sector_id`, …). |
| `days_in_state` | `PlotlineSubsystem.on_day` — `days` is the minimum GST days since `entered_gst`. |
| `gig_accepted` | `PlotlineSubsystem.accept_gig(plotline_id, gig_id)` |
| `gig_completed` | `PlotlineSubsystem.complete_gig(plotline_id, gig_id)` |

Optional **`require_flags`** (all keys must match instance flags) and **`set_flags`** on transition. Optional **`require_plotline`** `{ id, state }` waits on another arc's instance state.

Ignoring a gig is simply not accepting it; a later `days_in_state` transition can lapse the arc.

## Hooks

[`PlotlineSubsystem`](../../../scripts/gameplay/plotline_subsystem.gd) is registered on production [`Simulation`](../../../scripts/gameplay/simulation.gd).

- **Messages** — `contribute_messages(channel, session, catalog)` supplies weighted templates. [`MessageSubsystem`](../../../scripts/gameplay/message_subsystem.gd) merges them into the same weighted pick as catalog emitters when a `Simulation` is passed (flight HUD **WIRE** and bar **BAR**). Main-menu ticker uses a scratch session and does not see career plotlines.
- **Gigs** — `contribute_gigs(desk, habitat_id, session, catalog)` returns derived records (`source: plotline`, `plotline_id`, `gig_id`, desk, title, text, plus any extra authored fields). [`MissionSubsystem.list_plot_gigs`](../../../scripts/gameplay/mission_subsystem.gd) delegates to `session.bound_plotlines`. Nothing lists them in UI yet.

Player actions that should advance an arc call `accept_gig` / `complete_gig` (or rely on world events already published on the session bus).

## Save

Section id `plotlines`, subsystem `save_version` 1, payload `{ instances: { plotline_id: { state, entered_gst, flags } } }`. Missing section on load resets all catalog plotlines to `initial`. Unknown saved ids are kept but ignored until a matching catalog def appears. An instance whose `state` is no longer in the def resets to `initial`.

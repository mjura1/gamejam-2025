# Winter March — map visual overhaul: bigger/centered icons, spacing, auto-scroll, hover tooltips → features/map-visual-overhaul (awaiting review)

New feature on `features/map-visual-overhaul` (NOT merged — left for review): the
map/floor-select screen was hard to read without zooming in — node icons were
small, weren't visually centered on the connector lines pointing at them, and
floors were packed close together. Also adds a bigger UX change: mouse-edge
auto-scroll (Slay the Spire/RTS-style) and a hover tooltip on each node.
Scroll-wheel zoom and click-drag pan are untouched — Miha may remove them later
once auto-scroll play-tests well, but that's a separate, deferred decision.

- **Bigger icons + centering fix**: `map_node_icon.gd`'s icon scale doubled
  (`3.0` → `6.0`, then → `7.5` after round-2 feedback). Root cause of the
  off-center look: nodes were positioned by their top-left corner
  (`room_node.position = room_resource.position`), so the connector lines drawn
  in `_draw()` pointed at a corner, not the visible icon's center.
  `MapController._visualize_rooms()` now offsets by `room_node.size *
  room_node.scale / 2.0` so the icon's visual center lands exactly on the line
  endpoint, at every zoom level. **Follow-up fix after first playtest**: this
  alone wasn't enough — `_draw()` was still reading `room_node.position` (now
  the icon's shifted top-left corner) for the line endpoints instead of the
  original anchor, so the lines just followed the same offset the icon did.
  `_draw()` now uses `room_resource.position`/`next_room_resource.position`
  directly (the stable grid anchor both the icon's center and the line
  endpoint are meant to share). Confirmed fixed in round-2 feedback.
- **Bigger floor spacing**: `MapGenerator.Y_DISTANCE` `100` → `280` → `350`
  (round 2). `X_DISTANCE` left unchanged — the bigger icons still fit
  comfortably within a row at the existing horizontal spacing, no overlap
  observed. Camera framing/zoom-to-fit code needed no changes (already derives
  from room positions dynamically).
- **Mouse-edge auto-scroll**: new `MapController._process()` — top/bottom 2/5 of
  the screen is a "hot" zone (middle 1/5 dead — widened from the initial 1/5
  hot / 3/5 dead split after round-2 feedback), scroll speed ramps up linearly
  closer to the edge, disabled while a click-drag pan is active. Reuses the
  existing `_clamp_camera_position()` so it respects the same map boundaries as
  drag/zoom.
- **Hover tooltip bubble**: reuses the battle UI's ability-bubble visual pattern
  (same dark `StyleBoxFlat`, same clamped up-and-left positioning), but with a
  new `HoverTimer` per icon (`map_node_icon.tscn`/`.gd`, `wait_time` tuned down
  across two playtest rounds: `3.0` → `1.5` → `1.0`) instead of showing
  instantly, and a new `Room.RoomDescriptions` dict (`map_point.gd`)
  for the per-room-type text (e.g. "Adds a Pawn to the enemy army"). The
  bubble's Label is built lazily in code on first hover rather than baked into
  `map.tscn` — see Deviations below. Repositions every frame while visible so it
  stays glued to its icon during auto-scroll/pan.
  **Follow-up fixes after first playtest**:
  - The bubble always appeared pinned to the screen's top-left corner instead
    of near the hovered icon. Root cause: `MapNodeIcon.get_global_rect()`
    returns *canvas*-space coordinates (composed through the `Node2D` parent
    chain), not actual screen pixels — it does not include the separate
    `canvas_transform` `Camera2D` writes onto the viewport each frame. Since
    `MapBubble` lives under a `CanvasLayer` (screen-space, camera-agnostic),
    feeding it raw canvas coordinates placed it at/near world-origin regardless
    of where the icon actually was on screen. `_reposition_map_bubble()` now
    transforms the icon's rect through `get_viewport().canvas_transform` before
    computing the bubble's position, matching what the camera actually shows.
  - Locked/already-visited room icons never showed a tooltip at all. Root
    cause: `MapNodeIcon.update_look()` set `disabled = true` for those states,
    and a disabled `Button` does not reliably receive `mouse_entered`/
    `mouse_exited` hover signals (the plan's original assumption that it does
    was wrong). `update_look()` no longer touches `disabled` at all — the Button
    stays hover-active in every state, and click-through-to-battle stays
    correctly gated by the pre-existing manual check already in
    `_on_room_pressed()` (`room_resource.is_unlocked and not
    room_resource.selected`), so nothing about click behavior changed.

**Deviation from `plans/MAP_VISUAL_OVERHAUL_PLAN.md`'s M4 spec**: the plan called
for baking `MapBubbleLabel` directly into `map.tscn`. Doing so broke ~20
unrelated smoke tests (`smoke_battle`, `smoke_placement`, `smoke_ai*`, etc.) with
new `ERROR: N RID allocations of type 'DummyTexture'/'FontAdvanced' were leaked
at exit"` failures — bisected to the `Label`'s `autowrap_mode` triggering
TextServer font/glyph RID allocation that never gets released, because
`GameFlow` caches the `MapController` instance for the whole run and it's never
freed before a headless test's forced `--quit-after` shutdown. The identical
`AbilityBubbleLabel` pattern in `battle_ui.tscn` doesn't hit this because that
scene is freed normally when a battle ends. Fixed by constructing the Label in
GDScript (`MapController._ensure_map_bubble_label()`) the first time a hover
tooltip is actually requested, instead of at scene-load time — the
`MapBubble` `PanelContainer` + `StyleBoxFlat` stay in `map.tscn` as planned.

Tests: `./tests/run_all.sh` clean after every milestone except the pre-existing,
unrelated `smoke_ability_ui_pipeline` flake (documented in prior plans, e.g.
`plans/AI_DIFFICULTY_PLAN.md`) — see `plans/MAP_VISUAL_OVERHAUL_PLAN.md` §6 for
the per-milestone log. Manual playtest (icon centering at min/max zoom, spacing,
auto-scroll feel, tooltip behavior) not yet done — left for Miha per repo
convention.

# Winter March — post-battle summary overlays (VICTORY/DEFEAT) → features/post-battle-summary (awaiting review)

New feature on `features/post-battle-summary`: playtesting surfaced that battle end
was silent and confusing for a new player — winning silently dropped you back on
the map, losing silently dumped you at the main menu, with no explanation of what
happened. Adds VICTORY and DEFEAT overlay screens, shown the instant a battle
ends (before the existing automatic scene transition), reusing the pause menu's
blurred-backdrop visual pattern.

- **VICTORY**: a "SUMMARY" section shows both parties (enemy + mine) as rows of
  piece icons — pieces already owned before the battle are grayed out, a piece
  newly recruited/added *this battle* is highlighted with a "+" badge. A generic,
  data-driven "REWARDS" list shows items gained (today just upgrade items,
  computed as a before/after delta so it correctly includes the conditional
  courier_package bonus on top of the win/boss-win constant) — built as
  `{label, amount}` rows so a future reward type (e.g. artifacts, not implemented
  anywhere in this codebase yet) is just another row, not a redesign. CONTINUE
  re-triggers whatever the existing win logic already does (`return_to_map()` or
  `advance_map_tier()`, including the run-ending final-boss case) — no new
  transition logic, the summary is purely a view.
- **DEFEAT**: shows "Final Floor"/"Final Room" (map tier / room depth, captured
  into locals *before* `PlayerManager.reset_floor_number()` zeroes them). BACK
  ends the run and lands directly on the already-implemented game-mode-select
  overlay, skipping the bare main-menu title screen.
- New `PlayerManager.new_friendly_piece`/`new_enemy_piece` track which single
  piece (if any) was added to a roster this battle, set in
  `MapController._handle_event()`; `add_to_friendly_party()` now returns `bool`
  (joined the active roster vs. overflowed to reserve) so a benched piece isn't
  wrongly flagged "new". `GameFlow.game_over()` now returns the instantiated main
  menu `Control` so the defeat handler can chain `open_mode_select()` on it.

Along the way, fixed a latent bug in the shared `tests/framework/battle_boot.gd`
test helper (not a gameplay bug): `BattleBoot.boot()` connected its placement
auto-complete listener *after* adding the battle to the tree, which only worked
because `add_child()` during a `-s` script's `_initialize()` defers `_ready()` a
frame — calling `boot()` again later from `_process()` (needed by the new
multi-battle summary smoke test) runs `_ready()` synchronously instead, so the
listener could miss the PLACEMENT signal entirely and strand the battle forever.
Now connects before `add_child()`. Also widened `complete_placement()`'s
placement-cell search from the bottom 3 rows to the whole map height (still
filtered through the real placement-zone legality check), since randomly-spawned
"House" obstacles could occasionally block all 3 bottom rows.

Tests: `run_all.sh` gained `smoke_post_battle_summary` (victory non-boss/boss
CONTINUE branches, defeat BACK → mode-select, badge/reward/delta assertions) plus
2 new `test_player_manager.gd` unit cases for the `add_to_friendly_party()` return
value. Updated `smoke_battle_end`/`smoke_battle_loss`/`smoke_courier_package` to
drive the new overlay's signals directly before their existing post-transition
assertions. Full rationale, verified code map, and every design decision
documented in `plans/POST_BATTLE_SUMMARY_PLAN.md`.

# Winter March — snow rework: bug fix + risk/reward freeze mechanic → features/snow-rework (awaiting review)

New feature on `features/snow-rework` (NOT merged — left for review): fixes a
long-standing bug where curse-placed snow was never clearable by anything, and
reworks snow from an in-battle click-blocking wall into a risk/reward visual block.

- **Bug fix**: `GridManager.reveal_area()` only ever removed ambient fog, so every
  "clear the snow" path — Pawn's Lantern Signal, Rook's Lookout, the Flare item,
  the `move_reveal`/`battle_start_reveal` skill-tree passives, and Queen's "Scorched
  Earth" node (previously unimplemented entirely) — silently did nothing to
  curse-placed snow. `reveal_area()` now clears both fog systems in one place, so
  every existing ability's description finally matches its behavior. Removed the
  now-redundant `clear_curse_fog_area()` (Rook's Lookout called both back-to-back).
- **Un-walled**: snowed tiles used to silently eat clicks during play (the fog
  tile's `ColorRect` defaulted to `MOUSE_FILTER_STOP`) — now `MOUSE_FILTER_IGNORE`,
  so clicks reach the normal select/move/capture logic. Piece movement and
  turn-start reveal now clear only the single tile a piece stands on (was a 3x3
  auto-clear), so snow stays visually opaque instead of melting on approach.
  Moving/capturing onto snow that hides an enemy is an intended surprise-capture
  risk; inspecting a hidden enemy with nothing selected is blocked so it can't be
  used to peek without that risk.
- **New status — FROZEN**: an allied piece surrounded by snow (either fog system)
  on all 4 orthogonal sides for 1 consecutive player-turn-start freezes (movement
  blocked, abilities still work, still capturable); thaws immediately the moment
  the ring breaks, even mid-turn (e.g. an ally moving next to it); dies if the ring
  never breaks for 3 consecutive turn-starts. New `FrozenBadge` + STUNNED > FROZEN
  > ROOTED status priority in the detail panel.

Fixed a regression this uncovered along the way: ending a battle immediately on a
freeze-death (e.g. the king) required calling `check_battle_end()` at every
turn start, which exposed a pre-existing landmine in `PlayerManager.enemyGone()`/
`activeGone()` (both return true unconditionally for an empty list, with no "never
actually started" guard) — broke the dev-only `test_sandbox.tscn`, fixed by seeding
placeholder roster entries there like a real battle always does.

Tests: `run_all.sh` gained `smoke_snow_freeze` (bug fix, Scorched Earth, single-tile
clear, fog click-transparency, freeze, same-turn thaw, death). Full rationale,
verified code map, and every design decision/deviation documented in
`plans/SNOW_REWORK_PLAN.md`.

# Winter March — AI difficulty (chess-engine tiers, decoupled from curse difficulty) → features/ai-difficulty (awaiting review)

New feature on `features/ai-difficulty`: a second, independent **AI difficulty**
selector (`SettingsManager.ai_difficulty`, NORMAL/HARD/EXTREME/IMPOSSIBLE — no EASY
rung) added right below the existing curse-difficulty row in Settings. Curse
difficulty now controls curse *chance* only; AI difficulty controls the enemy's
move/capture *decision-making*, via a new data-driven `EnemyAIStrategy`
(`Scripts/AI/enemy_ai_strategy.gd`) parametrized per-tier by
`GameParameters/ai_difficulty.json` and loaded through a new `AiStrategyData`
autoload. NORMAL reproduces today's curse-difficulty-NORMAL AI bit-for-bit
(regression-safety anchor).

- **HARD**: danger-avoidance goes deterministic (100%, was a 0/50/100% curve tied to
  curse difficulty), plus `avoid_hanging_pieces` — a value-aware "don't hang a
  piece" filter, now applied to captures too (previously always unconditional).
- **EXTREME**: first tier with real lookahead — alpha-beta minimax (depth 1) over a
  pure board snapshot, plus static-exchange-evaluation-based move ordering and a
  fork/`threat_creation` bonus. Declines "trap" trades (e.g. a defended pawn) that
  HARD's cheaper, pre-move-only heuristic can't see coming.
- **IMPOSSIBLE**: minimax depth 2, plus **curse synergy** — a new
  `BaseCurse.ai_positioning_bonus()` hook (default a no-op) that lets
  `stunning_gaze`/`entangle`/`abduction` steer the AI toward ending its move nearest
  the *highest-value* visible player piece, and lets `frenzy`/`bloodlust`-cursed
  pieces weigh candidates that set up a guaranteed follow-up capture.

Performance: an early perf smoke run surfaced a real problem — IMPOSSIBLE against
this codebase's actual worst-case enemy count (24, the real spawn cap) took
**5.5 seconds**. The plan's own suggested radius bound (`move_range` + opponent's
`move_range`) barely bounds anything when sliding pieces have range 8 on a
~12-wide board — every piece "qualified" at every ply. A tighter radius cap plus
captures-first move ordering (better alpha-beta pruning) brought it down to
**~35-100ms**, no depth reduction needed.

Tests: `run_all.sh` gained `smoke_ai` (updated to drive the new `ai_difficulty`
setting), `smoke_ai_minimax` (defended-pawn trap — proves EXTREME+ actually
searches, not just present-but-inert), `smoke_ai_curse_synergy` (proves the new
curse hook actually steers positioning), and `smoke_ai_perf` (the timing guardrail
above, printed every run). Full rationale, design decisions, and every deviation
from the original plan documented in `plans/AI_DIFFICULTY_PLAN.md`.

# Winter March — play modes (Mode Select + Infinite + Tutorial hub) → features/play-modes (awaiting review)

New feature on `features/play-modes` (NOT merged — left for review): the main menu's
"START GAME" button is now **PLAY** and opens a **Mode Select** overlay (same
instantiate/hide/free overlay pattern as the settings menu) offering **CLASSIC**,
**INFINITE**, **TUTORIAL**, **BACK**, plus one shared EASY/NORMAL/HARD difficulty
selector (a second view of `SettingsManager.difficulty`, with a static `tooltip_text`
bubble quoting what each difficulty actually changes).

- **CLASSIC**: today's 3-tier run, unchanged.
- **INFINITE**: same run, but `GameFlow.advance_map_tier()` only ends the run at tier 3
  when `PlayerManager.game_mode != "infinite"` (new field, set by `setStarting(mode)` —
  signature gained a defaulted param, all other callers are zero-arg). Tier 3+ maps
  silently reuse the tier-2 config forever via `MapGenerator._configure_tier()`'s
  existing clamp — zero generator changes.
- **TUTORIAL**: a real scene (not an overlay) — scrollable hub listing stages from
  `Data/tutorials.json` via the new `TutorialData` autoload, entered/left through
  `GF.start_tutorial_hub()/start_tutorial_stage()/return_to_tutorial_hub()`. One
  concrete stage ("Moving & Capturing", built from `piece_test.tscn`) with the new
  `@export var ai_enabled` on `BattleController`: when false, `start_enemy_turn()`
  immediately hands the turn back, so enemies stand still while the player practices.
  The stage populates `PlayerManager.active_party/active_enemies` itself (no run is
  active) with a `"tutorial_keepalive"` enemy entry so `check_battle_end()` can never
  fire a victory/defeat transition — the stage exits only via BACK.

Tests: `run_all.sh` gained `smoke_mode_select` (overlay open/close contract),
`smoke_infinite_mode` (tier 2→3 keeps generating maps on the clamped tier-2 config,
run not ended) and `smoke_tutorial_ai_disabled` (enemy `grid_pos` frozen across a full
turn cycle). Gotcha caught during this: renaming `_on_start_pressed` →
`_on_play_pressed` silently no-op'd **three** smoke tests, not one —
`smoke_campfire_flow` and `smoke_shop_map_flow` also drove the real Start button via
`has_method("_on_start_pressed")`, which just returns false forever after a rename
(zero errors, no marker, looks like a flaky test). All three now drive the real
two-press flow: `_on_play_pressed()` → overlay `._on_classic_pressed()`.

# Winter March — enemy curses, inspection, difficulty selector, AI improvements → develop

New feature on `features/enemy-curses` (built on top of shop v2): from **floor 2 onward**,
spawned enemies have a chance to carry a random **curse** that makes them stronger, with a
visible board effect so the player can tell.

**Curses** get a framework like pieces/items — one base class (`BaseCurse`), variants apply
effects (`Scripts/Curses/`). Which curse (if any) an enemy gets uses the same
rarity-weighted-roll scheme as the shop (`Data/curses.json`: per-curse `weight` +
`excluded_pieces`, plus `min_floor`/`curse_chance`/`difficulty_chance_mult` config — all
placeholder numbers, Miha balances by hand later). Max one curse per enemy.

- `snowfall`: covers a 3×3 area in fog after it moves (`GridManager.cover_area`, mirrors
  `reveal_area`).
- `frenzy`: acts twice every enemy turn (excludes `queen` by default, an example of the
  exclusion mechanism, not a hard rule).
- `stunning_gaze`: after it moves, stuns the closest visible ally for exactly the player's next
  turn (blocks that piece's moves AND abilities), with its own cooldown so it can't chain-stun
  every turn.

Cursed enemies show an **animated particle effect + pulsing tint** (CPUParticles2D, per-curse
color) normally; when `SettingsManager.reduced_motion` is on, a **static code-drawn diamond +
static tint** instead — nothing animates. No new sprites (everything is code-drawn).

**Enemy inspection**: clicking an enemy piece while no ally is selected shows its reachable
tiles highlighted **all in one distinct red** (never green/gold — can't be confused with an
ally's own moves) and its status/curse in the battle UI detail panel. Display-only — doesn't
touch the existing move/capture selection flow at all.

**Difficulty selector** (Settings menu, EASY/NORMAL/HARD, persisted like reduced_motion, default
NORMAL): scales curse chance (0.5×/1×/1.5×) and gates a new AI danger-avoidance behavior
(off/50%/always).

**AI improvements** (kept mild — every enemy still moves each turn vs. the player's ~1, so the
existing asymmetry means small biases are already a big swing):
- Value-aware captures (always on): when multiple targets are capturable in one move, the AI
  takes the highest-value one (`Data/ai_config.json` `piece_values`) instead of the first found.
- Danger avoidance (difficulty-gated): among equally-good chase moves, prefers one no ally could
  capture next turn — falls back to the normal pick if every option is dangerous, never
  paralyzes. Capture priority itself is untouched; captures stay aggressive.
- Explicitly out of scope: no minimax/lookahead, no coordinated focus fire, no changes to
  spotting/blind-seek/panic.

Two real GDScript/Godot gotchas worth knowing if you touch this code again:
- A `class_name`-declared script (like `base_character.gd`) is eagerly, fully compiled by
  Godot's global class scan in `--script`/headless test runs, **before** autoloads are
  registered — so *any* bare reference to an autoload identifier (`CurseData.foo()`, even fully
  untyped, not just a typed `BaseCurse` parameter) anywhere in such a script's body breaks every
  test that touches it with "Identifier not found". Fixed throughout with the same
  `get_node("/root/CurseData")` pattern already used for `player_manager`/`battle_controller` in
  that file.
- `BattleController.start_enemy_turn()`/`end_player_turn()` `await` real timers; a `--script`
  mode smoke test's own `_process(delta) -> bool` is called directly by the engine's MainLoop,
  not through GDScript's `await` mechanism, so an `await` suspending *inside* `_process()` itself
  just silently stalls forever (zero errors, looks like a `--quit-after` tuning problem, isn't
  one). Anything driving a real enemy turn from a smoke test needs the frame-polled state-machine
  shape (fire the call without `await`, poll `current_state`/`turn_count` across ordinary
  frames) already used by `smoke_enemy_turn_pacing.gd`.

# Winter March — shop v2 (rarity-weighted stock + 9 items) → develop

New feature on `features/shop-v2`: the shop no longer sells "everything that
exists" — it rolls **4 independent slots**, each an item picked by a
JSON-editable rarity chance (`Data/shop_config.json`: `common`/`uncommon`/
`rare` weights, default 50/25/10), rolled once per shop visit. A bought slot
shows `SOLD` and can't be re-bought until the next visit; duplicate rolls
across slots are allowed (owning 2+ copies of a passive has no extra
effect).

9 new items (placeholder sprites + prices, same rule as the item shop v1 —
correct names/numbers to balance by hand later):

- **Common**: `spyglass` (marks tiles the enemy could capture next turn on
  selection), `bloodhounds` (a friendly wolf joins each battle and acts on
  its own right after your turn), `vicious_knights` (a knight capture grants
  +1 move, once per turn), `bounty` (a marked enemy pays out if it's the
  first to die).
- **Uncommon**: `castle` (king can't be captured while a friendly rook has
  line of sight to him), `courier_package` (a marked ally pays out if it
  survives to victory), `divine_intervention` (consumed on a party wipe to
  return to the map instead of game over — floor progress kept).
- **Rare**: `fortress` (enemies can't cross the line between a friendly rook
  and a house in its sight), `mounted_hunters` (queen and bishops can also
  move/capture like a knight).

Most new items are **passive** (always active while owned that run, no
inventory-drawer drag needed) — the item schema gained `rarity` and `kind`
(`consumable`/`passive`) fields; `PlayerManager.has_passive(id)` is the one
check every effect above gates on.

Placeholder sprites for all 9 items + the bloodhounds wolf piece, tracked in
`TEMP_SPRITES.md`. A pre-existing `tests/run_unit_tests.gd` bug was fixed
along the way: autoload `_ready()` (e.g. `ItemData`'s JSON load) doesn't run
until the engine's first frame, which is after `--script` mode's
`_initialize()` — any unit test touching autoload-loaded data was silently
seeing empty dictionaries.

# Winter March — item shop → develop

New feature on `features/item-shop`: a shop room on map tiers 1 and 2 (the
middle floor of each, same "every path passes through it" placement as the
campfire floor; tier 0 has no shop). Currency is the existing upgrade-item
count, no new currency was added.

- **Buy**: one item for now, `extra_move` (single-use, +1 move this turn in
  battle) — proves the item pipeline end to end rather than adding content.
  All prices default to 1 (correct names, placeholder numbers to be balanced
  later).
- **Sell**: both owned items and party pieces (active + reserve). Selling
  the last active piece is refused, same rule as the existing campfire
  party panel's active/reserve swap.
- **In battle**: items live in a slim `<`/`>` drawer between the board and
  the side panel; drag an item onto the board to use it. Hidden during the
  placement phase.
- On tier 2, the friendly-king recruit floor moved from 4 to 3 so the shop
  could take floor 4 (the map's actual middle floor for that tier).
- Placeholder sprites only (`shop.png`, `item_extra_move.png`) — tracked in
  `TEMP_SPRITES.md` for replacement with real art.

# Winter March — cleanup/audit-fixes → develop

Summary of everything that changed on the `cleanup/audit-fixes` branch
(now merged into `develop`), so you don't have to read all ~45 commits.
Grouped by what it means for you, not by commit order.

## TL;DR

A full pass over the jam-submission code: real crash fixes found by
playtesting, a chunk of dead/misleading code cleaned up per a full code
audit, a new test harness so we stop re-breaking things by hand, and one
new feature (the enemy move visualizer). Nothing about how the game
*plays* changed except the new visualizer and a couple of bug fixes below
— piece stats, map generation, and fog rules are otherwise untouched.

## New feature: enemy move visualizer

Enemies used to all move at once, synchronously, in a single frame — you'd
just see the board update with no idea what happened. Now each enemy acts
one at a time: its origin tile, path, and destination tile flash (green =
move, red = capture), with a short pause between enemies. All of a turn's
flashes accumulate and slowly fade out once it's your turn again, so you
can review the whole enemy turn at a glance instead of catching it frame
by frame.

Two real bugs turned up once this was playtested (see below) — both fixed.

## Real bugs fixed (found via playtesting, not just reading code)

- **Crash**: `"Left operand of 'is' a previously freed instance"` during an
  enemy turn. Cause: the enemy-turn loop snapshots all characters once at
  the start, but now that enemies act one at a time with real pauses
  between them, an earlier enemy in that same loop could capture (and free)
  a character that a later iteration still expected to be alive. Fixed by
  checking `is_instance_valid()` before touching anything from that
  snapshot — applied everywhere the game reads that same character list.
- **Highlights looking wrong**: if you moved again before the previous
  enemy turn's highlights had fully faded (5s), old and new flashes mixed
  and the old ones would jump back to full brightness instead of
  continuing to fade. Fixed by clearing leftover highlights the moment a
  new enemy turn starts.
- **AI chasing furniture**: an enemy that had already spotted a real player
  once could get confused by a House sitting near it and treat the House
  as the player to chase — a filter that excluded obstacles existed in one
  place (`can_see_player`) but was missing from a nearby, near-identical
  check. This one predates this branch entirely (present on `main`
  unchanged); nobody had noticed it before. Fixed and covered by a
  regression test.
- Fixed a hardcoded absolute path (`/root/Battle/BattleController`) that
  only worked on one machine's file layout.
- Fixed `GridManager` silently letting two pieces occupy the same tile
  (now errors loudly instead of corrupting state quietly).
- Fixed turn-start fog reveal iterating over string names instead of the
  actual grid, floor-tracking using the wrong axis, and a double battle-init
  bug.
- `GameFlow` now actually frees the detached map on game-over instead of
  leaking it (+ ~50 leaked room icons per loss, before this fix).

## Code-quality cleanup (from a full audit of the jam codebase)

Mostly invisible to gameplay — dead code, misleading names/comments, and
a few rough edges:
- Removed dead node references, empty `_process()` stubs, unreachable code,
  a leftover merge-conflict remnant in `project.godot`, and one dead script
  (`map_behaviour.gd`, confirmed broken/superseded).
- Fixed several stale/wrong comments and error messages that no longer
  matched what the code actually does.
- Renamed variables that shadowed built-ins (`char`, `name`) and a couple
  of misleading names (`min_distance_sq` that wasn't actually squared).
- Piece scenes now `preload()`'d instead of `load()`-ed fresh per spawn.
- Spawned pieces get unique node names (previously all identically named,
  making debugging harder).
- Revived an old, broken dev scene (`node.tscn` → `test_sandbox.tscn`) into
  an actually-working piece-testing sandbox, plus a second clean copy
  (`piece_test.tscn`) for comparing piece move ranges visually.

## Design decisions clarified (not bugs — read before "fixing" these)

A few things the audit flagged as suspicious turned out to be intentional:
- **King's `move_range = 12`**: not a typo. The king was originally meant
  to emit a "hot aura" clearing fog/protecting nearby allies from the cold;
  that never got built, so the oversized move range is standing in as
  compensation (a chess-accurate range-1 king would be useless in a game
  with no check/checkmate). Don't reduce this unless the hot-aura ability
  gets built.
- **Enemies see through fog**: confirmed intentional, not a bug.
- **Campfire/revive, pause menu, party status panel, game-over screen**:
  these look like dead/unused code but are planned features, not abandoned
  prototypes — keep them.
- **`snowCount`/`addSnow`**: also a planned feature (extra fog-coverage per
  floor climbed), not dead code.

## New: automated test harness (`team-berry-game/tests/`)

Didn't exist before this branch. Run everything with:
```
team-berry-game/tests/run_all.sh
```
Covers unit tests (pure logic, no scene needed) and smoke tests (spin up
real scenes headlessly via `godot4 --headless`, drive a scenario, check for
errors/expected output). Every bug fix above that could regress has a
matching regression test. If you fix something and there isn't a test for
it, consider adding one — it takes a few minutes and pays for itself the
next time someone touches that code.

## Final polish pass (a full 8-agent code review of this whole branch, done last)

Before starting new feature work, ran a thorough review of everything
above and fixed all 10 things it found: the two AI/fog-loop bugs already
mentioned above, a few duplicated test-setup blocks collapsed into one
shared helper, the move-highlighter's repeated draw code deduped into a
helper, its fade-alpha simplified from stored state into a computed value,
and its per-frame redraw during a fade split into its own node so it
doesn't also needlessly redraw the (unrelated, unchanging) move-preview
highlights every frame. Also fixed two incidental test-flakiness bugs and
one real bug in `run_all.sh` itself (a shell pipefail/SIGPIPE interaction
that could misreport a passing test as failed under high output volume).

## Still open, not done on this branch

- `get_all_characters()`'s name is misleading (it includes Houses/obstacles
  too) — cosmetic, not touched.
- Map pan/zoom direction is inverted vs. typical convention — needs a
  design call, not a pure bug.
- Campfire/revive, pause menu, party panel, unique piece abilities
  (including the king's hot aura) — planned, not yet built.

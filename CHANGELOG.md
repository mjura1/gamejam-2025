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

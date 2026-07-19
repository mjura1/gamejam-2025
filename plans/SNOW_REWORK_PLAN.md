# SNOW REWORK PLAN — bugfix + risk/reward freeze mechanic

Status: NOT STARTED. Work on branch `features/snow-rework` off `develop` (create it first).
Commit per milestone. Do NOT merge into develop — Miha merges himself (repo policy: always
`git merge --no-ff`, never fast-forward).

All file paths are relative to `team-berry-game/`. Line numbers are as of develop @ 2bb3fce.
**The code exploration below is already done and verified — do not re-derive it.**

---

## 1. What Miha wants

**Bug fix:** Snow placed by snow curses is not cleared by any items, pieces or abilities.

**Rework:** Snow stops being a wall (today snowed tiles literally can't be clicked during
play — see section 2) and becomes a visual block with a risk/reward effect:
- Pieces no longer clear a 3x3 area when moving. They only clear **the single tile they
  land on / stand on**. You can therefore move onto snow **during play** (this is about
  in-battle movement — the pre-battle placement phase is unaffected), but you still can't
  see what's under the neighboring snow tiles.
- New status: if a piece is **surrounded by snow on all 4 orthogonal sides (top, bottom,
  left, right)** for 1 turn, it becomes **FROZEN** and can't move.
- It thaws when it is no longer surrounded on all 4 sides — e.g. another piece moves next
  to it (that move clears the landed-on tile, breaking the ring). Thaw takes effect
  immediately, same turn.
- If it stays surrounded for **3 turns, it dies**.

---

## 2. Verified code map (exploration already done)

There are **two separate snow/fog systems**, both in `Scripts/TileMap/grid_manager.gd`:

| System | Storage | Created by | Removed by |
|---|---|---|---|
| Ambient fog ("snow blanket", grey) | `fog_nodes: Dictionary` (grid_pos → node) | `initialize_all_fog()` at battle start, covers top N rows (N = floor, `grid_manager.gd:260-274`) | `reveal_area()` (`grid_manager.gd:308-311`) — never decays on its own |
| Curse fog (snow from curses, tinted) | `curse_fog_nodes: Dictionary` + stage/tick/spread dicts (`grid_manager.gd:363-379`) | `cover_area_curse()` (`grid_manager.gd:389`) called by `snowfall_curse.gd`, `blizzard_curse.gd`, `contagion_curse.gd`, `wraith_cloak_curse.gd` | self-decays via `tick_curse_fog_decay()` (`grid_manager.gd:411`), or `clear_curse_fog_area()` (`grid_manager.gd:468`) |

**The bug, precisely:** `reveal_area()` only removes ambient fog. Everything that "clears
snow" goes through `reveal_area()` and therefore never touches curse snow:
- Piece movement 3x3 reveal: `base_character.gd:320-331` (`execute_move`)
- Turn-start 3x3 reveal around every ally: `BattleController.gd:590-614` (`update_fog_after_turn_start`)
- Pawn "Lantern Signal" (desc: *"Clear the snow in a 3x3 area…"*): `pawn.gd:112`
- Flare item: `Scripts/Items/flare_item.gd:12`
- Skill-tree passives `move_reveal` (`base_character.gd:335-337`) and `battle_start_reveal` (`BattleController.gd:262-268`)
- Queen "Scorched Earth" skill node (flag `blast_clears_snow`, `GameParameters/skill_trees.json:64`)
  is **not implemented at all** — `trigger_exterminate_if_armed()` (`BattleController.gd:120-133`)
  never reads the flag and clears no snow of either kind.
- The ONLY thing that clears curse snow today is Rook "Lookout": `rook.gd:105` calls
  `clear_curse_fog_area()` explicitly.

**Why snow is a "wall" today — the click-blocking mechanism (verified):**
- In-battle board clicks are handled by `map_behaviour.gd` `_unhandled_input()`
  (`map_behaviour.gd:172-183`: converts `get_global_mouse_position()` → grid, then runs
  select/move/capture/inspect logic). `_unhandled_input` only fires if no Control consumed
  the click first.
- `battle_ui.board_area` (the UI overlay over the board) is `MOUSE_FILTER_STOP` only
  during the placement phase (`battle_ui.gd:215`) and `MOUSE_FILTER_IGNORE` during play
  (`battle_ui.gd:224`) — during play, clicks fall through the UI to the world.
- Every fog tile (`Battle/fog_tile_scene.tscn`, used by BOTH fog systems) contains a
  `ColorRect` whose `mouse_filter` is unset in the .tscn → default `STOP`. It consumes
  left-clicks over it, so **clicking a snowed tile during play silently does nothing** —
  it can't be selected as a move target. That is the wall. The 3x3 auto-clear masks it
  for short moves (nearby snow melts before you click it).
- Movement RULES never check fog: `calculate_valid_targets()` (`base_character.gd:225-286`)
  has zero fog checks. Once the click gets through, moving/sliding into snow is already
  legal — so the fix is input-level, not rules-level.
- Placement phase needs NO changes: placement is restricted to the bottom rows
  (`battle_ui.gd:296-297` → `placement_highlighter.is_placement_cell`), ambient fog covers
  only top rows, and curse fog is wiped at battle init (`BattleController.gd:163
  clear_all_curse_fog()`). Snow can never exist on a placement cell (and during placement
  `board_area` STOPs clicks before fog could anyway).
- Knight "Shadow Leap" deliberately excludes snowed tiles as jump targets (`knight.gd:59`,
  desc says "snow-free"). Leave it — under the rework it becomes a real tradeoff. (Flagged
  for Miha below.)
- Enemy AI needs NO changes: the minimax simulation already ignores fog and curse hooks
  (`Scripts/AI/enemy_ai_strategy.gd:229,261` comments confirm).
- Status effect precedent to copy: `stunned_turns` / `rooted_turns`
  (`base_character.gd:125,131`; movement gate `base_character.gd:230,281`; tick-down
  `BattleController.gd:397-408`; signals `piece_stunned`/`piece_rooted`
  `BattleController.gd:45,50` + `notify_stun`/`notify_root` 381-387; UI badges
  `battle_ui.gd:590-644`, status text `battle_ui.gd:786-794`, turn-entry badge refresh
  `battle_ui.gd:236-237`, colors `battle_ui.gd:64-68`).
- NAME COLLISION WARNING: `grid_manager.is_frozen(pos, mover_is_enemy)`
  (`grid_manager.gd:53`) already exists — it is Bishop.Traps freeze **zones**, totally
  unrelated. Do not reuse that name; the movement gate at `base_character.gd:235` calls it.
- `exterminate_armed` dict already carries `"owner"` (`queen.gd:103-107`), and
  `has_flag()` exists at `base_character.gd:594`.
- `cover_area_curse` happily covers occupied tiles (needed by wraith_cloak which fogs the
  owner's own tile). Do not add an occupancy filter there.
- `update_fog_after_turn_start()` is called once per player turn from `start_player_turn`
  (`BattleController.gd:273`) and is fully synchronous (no awaits).
- Dead/planned code you will encounter but must NOT touch or delete:
  `Scenes/CharacterPiecesNodes/Neutral/Fog.tscn` (unused piece) and
  `PlayerManager.snowCount`/`addSnow()` (planned overworld feature).

---

## 3. Design decisions (defaults chosen — implement as written, flagged items go in the final report to Miha)

1. **"Snow" for all checks below = either system**: a tile has snow iff
   `fog_nodes.has(pos) or curse_fog_nodes.has(pos)`. This means pushing into the ambient
   snow blanket at the top of the map is now also freeze-risky. *(flag for Miha)*
2. **Bug fix approach**: make `reveal_area()` clear BOTH systems. Every existing "clear
   snow" path (pawn, rook, flare, passives, abduction) is fixed in one place, and their
   player-facing descriptions finally become true. Snow-clearing abilities keep their full
   areas — only the free movement/turn-start clears shrink to 1 tile.
3. **Surrounded** = each of the 4 orthogonal neighbors is either off-board or has snow.
   Off-board sides count as surrounding (edge pieces can freeze). *(flag for Miha)*
4. Freeze applies to **allied pieces only** (incl. wolf and converted allies —
   anything with `is_enemy == false` and `is_obstacle == false`). Enemies never freeze.
5. Frozen blocks **movement only**. Abilities still work (a frozen pawn can Lantern-Signal
   itself free — intended counterplay). Frozen pieces can still be captured. *(flag for Miha)*
6. Thresholds: `SNOW_FREEZE_TURNS = 1`, `SNOW_DEATH_TURNS = 3`, counted in **consecutive
   player-turn-starts spent surrounded**; counter resets to 0 the moment the ring breaks.
   Timeline: enemy snows you in on their turn → your next turn start: counter=1 → FROZEN.
   Still surrounded next turn start: counter=2. Next: counter=3 → piece dies. Player gets
   2 full turns to react.
7. Death uses the existing `die()` (`base_character.gd:386`) → dead-party registration,
   revive items, battle-end detection all work automatically.
8. **Clicking snowed tiles** (once fog stops eating clicks): a snowed tile is treated as
   an unknown tile. If it secretly holds an enemy:
   - With a piece selected, the move click proceeds normally — if the tile is in range it
     becomes a surprise capture (`try_move` already handles occupied targets). That IS the
     risk/reward: you can't see what's under the snow. *(flag for Miha)*
   - With nothing selected, do NOT open enemy inspection (that would leak what's hidden) —
     see M2 step 3.
   - Known pre-existing quirk, OUT of scope: when a piece is selected, the move
     highlighter already marks capture targets, including enemies under snow — that leak
     existed before (targets never checked fog) and becomes more visible now. Flag it in
     the final report; don't fix unless Miha asks.
9. Comment style: gameplay scripts have Slovenian comments — match that. Test files use
   English. Keep comments to constraints only, per repo style.

---

## 4. Milestones

Log a one-line `./tests/run_all.sh` result in section 6 after EVERY milestone (repo
convention — other agents read it instead of re-running the suite).

### M0 — Baseline
- `git checkout develop && git checkout -b features/snow-rework`
- Run `./tests/run_all.sh` from `team-berry-game/` (godot binary: `godot4`, installed at
  `~/.local/bin/godot4`). Record the baseline in section 6, including any PRE-EXISTING
  failures. Only deltas against this baseline matter later.

### M1 — Bug fix: curse snow becomes clearable
1. `grid_manager.gd` `reveal_area()` (line 308): also remove curse fog —
   ```gdscript
   func reveal_area(positions_to_reveal):
       for pos in positions_to_reveal:
           _remove_fog_tile(pos)
           _remove_curse_fog_tile(pos)
   ```
   Update the Slovenian comment above it (it currently documents ambient-only behavior).
2. Delete `clear_curse_fog_area()` (`grid_manager.gd:468-…`, now redundant) and drop the
   call at `rook.gd:105` (the `reveal_area(area)` call right above it now does both).
   Verified: those are the only two references (tests don't use it; they use
   `clear_all_curse_fog`, which stays).
3. Implement Scorched Earth in `trigger_exterminate_if_armed()` (`BattleController.gd:120`):
   read `var blast_owner = exterminate_armed.get("owner")` **before** the dict is cleared
   at line 125; after the kill loop:
   ```gdscript
   if is_instance_valid(blast_owner) and blast_owner is BaseCharacter \
           and blast_owner.has_flag("blast_clears_snow"):
       grid_manager.reveal_area(tiles)
   ```
4. Tests (see section 5 for harness how-to): cover_area_curse a tile → reveal_area it →
   assert `curse_fog_nodes` no longer has it. Scorched Earth: set
   `queen.passives = [{"type": "flag", "flag": "blast_clears_snow"}]`, arm, snow the area,
   trigger via a move, assert cleared.

### M2 — Un-wall the snow: click-through + single-tile clearing
1. **Make fog click-transparent**: in `Battle/fog_tile_scene.tscn`, add
   `mouse_filter = 2` (= `MOUSE_FILTER_IGNORE`) to the `ColorRect` node. One scene serves
   both fog systems, so this single edit lets clicks reach
   `map_behaviour._unhandled_input` on every snowed tile. (Belt-and-braces alternative if
   .tscn editing feels fragile: set it in code at both `FOG_TILE_SCENE.instantiate()`
   sites, `grid_manager.gd:287` and `:393` — pick ONE approach, the .tscn edit preferred.)
2. `base_character.gd` `execute_move()` (lines 320-331): replace the 3x3 double loop with
   `grid_manager.reveal_area([grid_pos])`. Keep the `move_reveal` passive block
   (335-337) exactly as is — it's a paid upgrade and now actually worth money.
3. **Hidden-enemy inspection guard** (decision 8): in `map_behaviour.gd`
   `_unhandled_input`, the no-selection enemy-inspection branch ("LOGIKA 1.D", the path
   that calls `_inspect_enemy`) must skip enemies standing on a snowed tile — use the new
   `grid_manager.has_snow_at(clicked_grid)` (added in M3; if doing M2 first, add the
   helper here). Move/capture branches stay untouched (surprise capture is intended).
4. `BattleController.gd` `update_fog_after_turn_start()` (lines 594-614): replace the 3x3
   loop with collecting just `character.grid_pos` per living ally. Keep the
   `tick_curse_fog_decay()` call after it.
5. No changes to: placement (`battle_ui.gd`), knight jump filter, pawn/rook/flare areas,
   `battle_start_reveal` (`BattleController.gd:268`), abduction reveal.
6. Tests: put ambient fog (via `cover_area`) AND curse fog on tiles around a target tile;
   `execute_move` an ally onto it; assert landing tile is clear of both and all neighbors
   still snowed. Plus: instantiate `FOG_TILE_SCENE` and assert its ColorRect
   `mouse_filter == Control.MOUSE_FILTER_IGNORE` (guards against the .tscn edit being
   lost; full click simulation isn't practical headless — clicking through snow goes on
   the manual checklist).

### M3 — Freeze / death mechanic
1. `base_character.gd`, next to `rooted_turns` (line 131), with Slovenian doc comments:
   ```gdscript
   var snow_trapped_turns: int = 0
   var snow_frozen: bool = false
   ```
2. `grid_manager.gd` helpers (near the curse-fog section):
   ```gdscript
   func has_snow_at(pos: Vector2i) -> bool:
       return fog_nodes.has(pos) or curse_fog_nodes.has(pos)

   func is_snow_surrounded(pos: Vector2i) -> bool:
       if not is_instance_valid(tile_map):
           return false
       var used_rect: Rect2i = tile_map.get_used_rect()
       for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
           var n: Vector2i = pos + offset
           if is_inside_boundary(n, used_rect) and not has_snow_at(n):
               return false
       return true
   ```
   (Off-board neighbors count as surrounding — decision 3. `is_inside_boundary` already
   exists; check its exact signature before calling.)
3. `base_character.gd` — single source of truth for lazy thaw:
   ```gdscript
   func is_snow_frozen_now() -> bool:
       if snow_frozen and is_instance_valid(grid_manager) \
               and not grid_manager.is_snow_surrounded(grid_pos):
           snow_frozen = false
           snow_trapped_turns = 0
       return snow_frozen
   ```
   Gate movement in `calculate_valid_targets()` right after the stun check (line 230-231):
   `if not is_enemy and is_snow_frozen_now(): return targets`.
   Do NOT gate `activate_ability()` (decision 5). The lazy check is what makes
   "another piece moving next to it unfreezes it **the same turn**" work: the rescuer's
   move clears its landing tile via M2, and the frozen piece's next target calculation
   sees the broken ring.
4. `BattleController.gd`:
   - `signal piece_frozen(character: BaseCharacter)` next to `piece_stunned` (line 45).
   - Consts `SNOW_FREEZE_TURNS := 1`, `SNOW_DEATH_TURNS := 3`.
   - New `_update_snow_freeze_states()` called at the END of
     `update_fog_after_turn_start()` (order matters: own-tile reveal → decay tick →
     freeze eval, so snow that just melted doesn't count):
     ```gdscript
     for character in grid_manager.get_all_characters():
         # skip non-BaseCharacter / invalid / is_enemy / is_obstacle
         if grid_manager.is_snow_surrounded(character.grid_pos):
             character.snow_trapped_turns += 1
             if character.snow_trapped_turns >= SNOW_DEATH_TURNS:
                 character.die()
                 continue
             if character.snow_trapped_turns >= SNOW_FREEZE_TURNS and not character.snow_frozen:
                 character.snow_frozen = true
                 piece_frozen.emit(character)
         else:
             character.snow_trapped_turns = 0
             character.snow_frozen = false
     ```
     Iterate a copy of the list if `get_all_characters()` returns live storage —
     `die()` mutates the grid (check how `end_player_turn` at 397 iterates; mirror it).
   - In `start_player_turn`, right after the `update_fog_after_turn_start()` call
     (line 273): `if check_battle_end(): return` — a freeze death (e.g. the king) must end
     the battle immediately.
5. `battle_ui.gd` UI wiring (copy the ROOT badge pattern exactly):
   - `const STATUS_FROZEN_COLOR := Color(0.55, 0.8, 1.0)` next to line 67.
   - `_set_frozen_badge(character, frozen)` → `_set_named_badge(character, "FrozenBadge",
     "FROZE" if frozen else "", STATUS_FROZEN_COLOR, Vector2(2, 25))` (stacked below
     RootBadge at (2,17), same reasoning as the root badge comment at 618-620).
   - `_refresh_frozen_badges()` mirroring `_refresh_stun_badges()` (line 607) but reading
     `character.is_snow_frozen_now()` (this also thaws stale state before display).
   - Call it alongside the two refreshes at lines 236-237, AND from the handlers of
     `moves_changed` / `abilities_changed` signals (find where battle_ui connects them),
     so a mid-turn rescue visibly thaws the badge without waiting for next turn.
   - `_on_piece_frozen(character)` connected to the new signal in `_ready` (next to lines
     117-118): set badge + `_show_character` refresh, same as `_on_piece_rooted` (628).
   - Status text in `_show_character` (786-794): priority STUNNED > FROZEN > ROOTED
     (frozen = no movement at all, worse than rooted). Use `is_snow_frozen_now()`.
6. Tests: see section 5, cases 3-5.

### M4 — Wrap-up
- CHANGELOG.md entry at repo root (see existing entries for format).
- Full `./tests/run_all.sh`, log result in section 6, compare against M0 baseline.
- Final report to Miha must list the flagged decisions (section 3: items 1, 3, 5, 8, plus
  "knight jump still forbids snow tiles" and the pre-existing capture-highlight leak) and
  a manual playtest checklist: click a distant snowed tile as a slide target (click now
  registers — the old wall is gone), move onto snow (only that tile clears), surprise
  capture by moving onto a snowed tile hiding an enemy, clicking a snowed hidden enemy
  with nothing selected does NOT inspect it, let a piece get ringed (FROZE badge + FROZEN
  status on turn start), rescue it mid-turn (badge clears, piece can move same turn), let
  one die at 3 turns, rook/pawn/flare clearing curse snow, Scorched Earth node.

---

## 5. Test harness facts (verified — read this instead of exploring)

- Runner: `team-berry-game/tests/run_all.sh`. Unit tests auto-discovered from
  `tests/unit/` by `run_unit_tests.gd`; smoke tests are **manually registered** in
  `run_all.sh` via `check_script "<label>" "res://tests/smoke/<file>.gd" <quit_after> "<expect_str>"`.
  A smoke test MUST print its `expect_str` on success — zero errors alone is treated as
  suspect (silent no-op protection).
- **MainLoop gotcha:** smoke tests `extends SceneTree` and drive frames via
  `_process(delta) -> bool` — return `true` means STOP, `false` means keep running. Never
  `await` inside `_process` (the engine never resumes it — silent stall). Copy the
  frame-polled state machine pattern from `tests/smoke/smoke_curses.gd` (its header
  comment explains everything, including how it boots a real battle and overrides the
  enemy roster).
- Good news for this feature: `update_fog_after_turn_start()`, `reveal_area()`,
  `cover_area()`, `cover_area_curse()`, `execute_move()` are all synchronous — after the
  battle scene has booted you can test everything without running enemy turns.
- New smoke test: `tests/smoke/smoke_snow_freeze.gd`, expect_str `SMOKE_SNOW_FREEZE_OK`,
  quit-after 400. Register it in `run_all.sh`. Suggested cases:
  1. Bug fix: `cover_area_curse([p])` → `reveal_area([p])` → assert
     `not grid_manager.curse_fog_nodes.has(p)`.
  2. Single-tile move clear: snow (one ambient via `cover_area`, rest curse) on a tile +
     its neighbors → ally `execute_move` onto it → landing tile clear of both, neighbors
     still snowed.
  3. Freeze: ring an ally's 4 neighbors with **ambient** fog via `cover_area` (ambient
     never decays — avoids decay interference; it also proves ambient counts as snow) →
     call `battle_controller.update_fog_after_turn_start()` → assert `snow_frozen` and
     `calculate_valid_targets().is_empty()`.
  4. Same-turn thaw: from case 3, `reveal_area([one neighbor])` → assert
     `is_snow_frozen_now() == false` and targets non-empty, `snow_trapped_turns == 0`.
  5. Death: re-ring, call `update_fog_after_turn_start()` three times total from fresh
     counter → assert the piece died (check `grid_manager.get_character_at()` is null /
     instance freed after a frame; `die()` uses `queue_free`, so poll one frame).
  6. Scorched Earth (can also live here): flag-passive queen + armed exterminate + snowed
     tiles → any move → snow in blast area gone.
- GDScript gotchas that have bitten before in this repo: don't use `:=` inference on
  `Dictionary.get()` results (Variant inference errors); build `Array[Vector2i]` with an
  explicit type annotation before appending; `base_character.curse` stays untyped on
  purpose (autoload load-order, see comment at `base_character.gd:115-120`) — don't
  "fix" it.

---

## 6. Progress / test log (fill in as you go)

- [x] M0 baseline: `./tests/run_all.sh` → unit tests 942/942 pass. Smoke: all PASS except
      pre-existing `FAIL: smoke_ability_ui_pipeline` (expected string not found: "SMOKE
      TEST: all 12 abilities exercised cleanly through the real UI pipeline") — unrelated
      to snow, not touched by this branch. Overall harness result `FAIL` due only to that
      one pre-existing failure. This is the baseline to diff against.
- [x] M1 bug fix: suite result: unit tests 942/942 pass. Smoke: all PASS except the
      same pre-existing `smoke_ability_ui_pipeline` failure from the M0 baseline (no new
      failures). One transient flake seen on a single run (`smoke_spyglass`, unrelated -
      random column-pick test occasionally lands on an occupied tile); reran clean.
      New `smoke_snow_freeze` (bug-fix + Scorched Earth cases) passes.
      Deviation from plan: `reveal_area()`'s Slovenian doc-comment was a plain one-liner,
      not a multi-line block - expanded it in place rather than editing a nonexistent
      longer comment.
- [x] M2 single-tile clear: suite result: unit tests 942/942 pass. Smoke: all PASS
      except the same pre-existing `smoke_ability_ui_pipeline` failure. No new failures.
      `smoke_snow_freeze` single-tile-clear + fog-click-through cases pass.
- [ ] M3 freeze mechanic: suite result:
- [ ] M4 wrap-up: final suite result:

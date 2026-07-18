# ENEMY CURSES + INSPECTION + AI/DIFFICULTY (implementation plan)

Branch: create `features/enemy-curses` off `develop`. Merge back with `git merge --no-ff`.
**Coordination with `SHOP_V2_PLAN.md`:** both plans edit the same hot spots
(`BattleController.start_player_turn/end_player_turn`, `base_character.calculate_valid_targets`,
`battle_ui.gd`, `map_behaviour.gd`). Implement them on separate branches and merge shop-v2
FIRST, then branch this off the updated develop. One explicit reuse point is marked §5.2.

This doc is written so an implementing model can build the feature WITHOUT re-deriving context.
Work phases in order; each ends runnable/testable. Check off `[ ]` boxes as you go.

> **POST-SHOP-V2 NOTE (2026-07-18): line numbers in this doc are STALE.** They were taken
> before `features/shop-v2` landed, and that branch rewrote parts of BattleController,
> base_character, map_behaviour, move_highlighter, battle_ui and grid_manager. Treat every
> `l.NNN` as "approximately here — locate by the quoted function name instead" (e.g.
> `calculate_valid_targets` is now ~l.136 of base_character, the capture-immune break ~l.170,
> `check_battle_end` ~l.405 of BattleController). Two shop-v2 additions this plan builds on
> directly: the capture-immune break is now
> `if target_char.is_capture_immune or target_char.is_castle_protected():` (castle item), and
> the spyglass risk helper exists at `map_behaviour._compute_risk_tiles()` (~l.111) — see the
> §5.2 reuse note. Also read `SHOP_V2_PLAN.md`'s deviation blocks first: they record GDScript
> type-inference gotchas (typed-array ternaries, untyped loop vars from
> `get_all_characters()`) that this plan's own snippets may also trip on — apply the same
> fixes preemptively.

**Decisions from Miha (do not re-litigate):**
- Enemies from **floor 2 onward** can carry a random **curse** that makes them stronger, with a
  visible board effect so the player can tell.
- Initial curses: **place snow in a 3x3 area**, **move twice in one enemy turn**,
  **stun a player piece for 1 turn** (surface stun via the battle UI **STATUS** field).
- Curses get a **framework like pieces/items**: one base class, variants apply effects.
- Clicking an enemy piece shows its status/curse in the battle UI **and its reachable tiles
  highlighted all in red** (never green — must not be confusable with an ally's moves).
- AI may be improved but **must stay beatable** — every enemy moves each turn vs. the player's
  ~1 move. Keep improvements mild and/or gate them behind a **difficulty selector**.

**Defaults chosen by Claude (keep unless Miha objects; numbers are placeholders he balances):**
- Max **one curse per enemy**; assignment chance and min floor live in `Data/curses.json`
  (`curse_chance: 0.25`, `min_floor: 2`), so Miha tunes without code.
- **Which** curse an enemy gets uses the same scheme as the shop's rarity roll (Miha asked for
  this explicitly): each curse has a relative `weight` in the JSON (normalize over the sum, no
  need to total 100) and an `excluded_pieces` list of `strName`s it can never land on. Roll
  only among curses eligible for that piece; if every curse excludes the piece → no curse.
- Curse ids: `snowfall`, `frenzy`, `stunning_gaze`.
- Stun balance valve: `stunning_gaze` has a JSON `cooldown` (default 2 enemy turns) so it can't
  chain-stun every turn; stun lasts exactly the player's next turn and blocks that piece's
  moves AND abilities.
- Cursed visual (Miha confirmed the reduced-motion split): **animated particle effect**
  (CPUParticles2D, per-curse color) + pulsing tint normally; when
  `SettingsManager.reduced_motion` is on, a **static code-drawn shape + static tint** instead —
  nothing animates. No new sprites needed either way. Details in §1e.
- Difficulty selector: **EASY / NORMAL / HARD** in the settings menu, persisted like
  reduced_motion, default NORMAL. It scales curse chance (0.5× / 1× / 1.5×) and gates the AI
  danger-avoidance feature (off / 50% / always). Value-aware captures are always on.
- Enemy inspection triggers only when **no ally is selected** (ally selected + click enemy is
  the existing capture attempt — unchanged).

---

## 0. Existing code you will build on

| File | What it gives you |
|---|---|
| `team-berry-game/Scripts/Data/item_data.gd` + `Data/items.json` | The autoload-reads-JSON + script-registry pattern to copy for `CurseData` (`ITEM_SCRIPTS` dict, `create_item`, `_load_json`). |
| `team-berry-game/Scripts/CharacterPieces/base_character.gd` | `calculate_valid_targets()` (l.100), `try_move` (l.195), `die()` (l.230), enemy AI `calculate_best_move()` (l.483: spotting → blind seek → capture-priority l.577 → chase l.593), `find_visible_enemies()` (l.288 — for an ENEMY piece this returns visible ALLIES), `strName`, `is_enemy`, `is_obstacle`, `@onready settings_manager` already present (l.21). Enemies use these same scripts (see gotcha below). |
| **GOTCHA:** enemy scenes (`Scenes/CharacterPiecesNodes/Enemy/*.tscn`) reuse the ALLY scripts with `is_enemy = true`. Curse/AI code paths live in shared scripts — gate by `is_enemy` where it matters. |
| `team-berry-game/Scripts/TileMap/BattleController.gd` | `start_enemy_turn()` per-enemy loop (l.221–239), `_take_enemy_action()` (l.243), `start_player_turn()` (l.159), `end_player_turn()` (l.198), `check_battle_end()` (l.274), `turn_count`, `state_changed`. |
| `team-berry-game/Scenes/Map/battle.gd` | Enemy spawn loop (l.74–85) — curse assignment goes right after each spawn. `player_manager.current_map_floor` is set before the battle scene loads (fog already relies on it, l.98 in BattleController). |
| `team-berry-game/Scripts/TileMap/grid_manager.gd` | Fog: `fog_nodes`, `_spawn_fog_tile()` (l.218), `reveal_area()` (l.243), `initialize_all_fog()`. **`spawn_character()` (l.99) does NOT return the instance** — battle.gd must fetch it another way or you add a `return character` (safe: no caller uses the return today). Also `get_all_characters`, `get_character_at`, `is_inside_boundary`. |
| `team-berry-game/Scripts/map_behaviour.gd` | Click flow. Enemy-click-with-no-selection is a no-op at l.211–213 — inspection hooks there. `_apply_selection` (l.88), `_clear_selection` (l.99), `selection_changed` signal. |
| `team-berry-game/Scripts/TileMap/move_highlighter.gd` | The "extra array + own color + show/clear funcs" pattern (`ability_targets`, l.15–20) to copy for the red enemy preview. `CAPTURE_COLOR` is red `(0.9, 0.1, 0.1, 0.6)` — pick a distinct red for preview, e.g. darker `(0.8, 0.15, 0.15, 0.5)`, since ALL preview tiles are one color by design. |
| `team-berry-game/Scripts/Battle/battle_ui.gd` | Detail panel: `_on_selection_changed` (l.644), `_show_character` (l.652 — sets `%StatusValue` "ALIVE", portrait from `friendly_%s.png`), `_clear_detail_panel` (l.676), `_clear_ability_rows` (l.684), ability row labels (`ability1_name/desc/...`). Board badges: `_set_board_badge(character, text)` (l.485) — note its **inverse-scale compensation**: piece roots have per-piece scale (rook 0.05 vs pawn 0.08), so any child visual must divide by `character.scale`. Status colors consts l.53–55. |
| `team-berry-game/Scripts/SettingsManager.gd` | Autoload; `reduced_motion` + ConfigFile `load_settings/save_settings` — copy this shape for `difficulty`. |
| `team-berry-game/Scripts/settings_menu.gd` + its scene | Where the difficulty OptionButton goes (mirror the reduced-motion row's wiring). |
| Autoload registration | `team-berry-game/project.godot` `[autoload]` — register `CurseData` after `ItemData`. |

Verification tooling (installed & proven): `godot4` headless CLI;
`cd team-berry-game && ./tests/run_all.sh`. Gotchas: rerun
`godot4 --headless --import --path team-berry-game` after new `class_name` scripts; in
`--script` tests `_process()` must `return false`; autoloads via `root.get_node(...)`; smoke
tests assert a positive printed string. Comments in Slovenian; CHANGELOG entry at the end; any
generated sprite (none expected here) gets a `TEMP_SPRITES.md` row.

---

## Phase 1 — Curse framework (data + classes + assignment + visual)

### 1a. `Data/curses.json` (new)

```json
{
	"config": {
		"min_floor": 2,
		"curse_chance": 0.25,
		"difficulty_chance_mult": {"easy": 0.5, "normal": 1.0, "hard": 1.5}
	},
	"curses": {
		"snowfall":      {"name": "Snowfall", "description": "Covers a 3x3 area in snow after it moves.", "weight": 40, "excluded_pieces": [], "radius": 1, "color": [0.55, 0.75, 1.0]},
		"frenzy":        {"name": "Frenzy", "description": "Acts twice every enemy turn.", "weight": 30, "excluded_pieces": ["queen"], "extra_actions": 1, "color": [1.0, 0.45, 0.3]},
		"stunning_gaze": {"name": "Stunning Gaze", "description": "After it moves, stuns the closest ally in its sight for 1 turn.", "weight": 30, "excluded_pieces": [], "duration": 1, "cooldown": 2, "color": [0.8, 0.5, 1.0]}
	}
}
```

`weight` is relative (same convention as shop_config's rarity_weights — normalize over the
sum). `excluded_pieces` lists `strName`s ("pawn", "queen", …) the curse may never roll on —
per-curse balance valve. All numbers placeholders for Miha (the `frenzy`-excludes-queen entry
is an EXAMPLE of the mechanism, keep it or empty it, doesn't matter).

### 1b. `Scripts/Data/curse_data.gd` (new autoload `CurseData`)

Copy `item_data.gd`'s shape (Slovenian comments). Loads the json in `_ready()`. API:

```gdscript
const CURSE_SCRIPTS: Dictionary = {
	"snowfall": preload("res://Scripts/Curses/snowfall_curse.gd"),
	"frenzy": preload("res://Scripts/Curses/frenzy_curse.gd"),
	"stunning_gaze": preload("res://Scripts/Curses/stunning_gaze_curse.gd"),
}
func get_curse_ids() -> Array                 # keys of "curses"
func get_curse_name(id) / get_curse_description(id) -> String
func get_param(id: String, key: String, default)   # radius/extra_actions/duration/cooldown
func get_color(id: String) -> Color           # from [r,g,b], default Color.MAGENTA
func get_min_floor() -> int                   # config, default 2
func get_curse_chance(difficulty: String) -> float  # curse_chance * difficulty_chance_mult
func create_curse(id: String) -> BaseCurse

# Uteženi met med prekletstvi, ki so za ta tip figure sploh dovoljena
# (weight > 0, strName ni v excluded_pieces). "" = nobeno ni na voljo.
# rng parameter zaradi testov (seedable) - ista konvencija kot
# ItemData.roll_shop_stock (glej SHOP_V2_PLAN.md).
func roll_curse_for(piece_name: String, rng: RandomNumberGenerator = null) -> String
```

Register in `project.godot` after `ItemData`.

### 1c. Curse classes (`Scripts/Curses/`, new dir)

`base_curse.gd`:

```gdscript
class_name BaseCurse
extends RefCounted
# Ogrodje prekletstev: 1 osnovni razred, variante povozijo kavlje - enak
# vzorec kot pieces (base_character) in itemi (base_item).

var id: String = ""

func display_name() -> String: return CurseData.get_curse_name(id)
func description() -> String: return CurseData.get_curse_description(id)
func color() -> Color: return CurseData.get_color(id)

# Koliko DODATNIH akcij ima ta sovražnik v sovražnikovi potezi (frenzy).
func extra_actions() -> int: return 0

# Kavelj: pokliče se PO vsaki uspešno izvedeni akciji tega sovražnika
# (BattleController._take_enemy_action). owner: BaseCharacter, bc: BattleController.
func on_action_taken(_owner, _bc) -> void: pass

# Besedilo za STATUS/inspekcijo v battle UI.
func status_text() -> String: return "CURSED: %s" % display_name()
```

- `frenzy_curse.gd`: `_init(): id = "frenzy"`; `extra_actions()` returns
  `CurseData.get_param(id, "extra_actions", 1)`.
- `snowfall_curse.gd` / `stunning_gaze_curse.gd`: stubs now (`_init` sets id), effects in
  Phase 2.

### 1d. Attach point + assignment

- `base_character.gd`: `var curse: BaseCurse = null` (near `is_capture_immune`), plus
  `func apply_curse(new_curse: BaseCurse)` → sets it and adds the visual (1e).
- `battle.gd` enemy spawn loop (l.74–85): make `grid_manager.spawn_character()` `return
  character` (verify no caller breaks — none use the return today, incl. King.Heal), then:
  ```gdscript
  var enemy = grid_manager.spawn_character(...)
  _maybe_curse(enemy)
  ```
  `_maybe_curse(enemy)`: if `player_manager.current_map_floor >= CurseData.get_min_floor()`
  and `randf() < CurseData.get_curse_chance(settings_manager.difficulty)` (Phase 4 adds
  `difficulty`; until then pass `"normal"`):
  ```gdscript
  var curse_id := CurseData.roll_curse_for(enemy.strName)
  if curse_id != "":
  	enemy.apply_curse(CurseData.create_curse(curse_id))
  ```

### 1e. Board visual (code-drawn, no sprites)

New `Scripts/Curses/curse_marker.gd` (Node2D child added by `apply_curse`). Two modes,
branched on `settings_manager.reduced_motion` — same accessibility pattern as
`base_character.slide_to()` (l.146: tween normally, instant when reduced):

- **Normal (reduced_motion off): animated particles.** A `CPUParticles2D` child configured in
  code (no scene, no textures): `amount` ~8, `lifetime` ~1.2, small upward `gravity`
  (e.g. `Vector2(0, -12)`), slight `spread`/`initial_velocity`, `scale_amount_min/max` tiny,
  `color = curse.color()` (default square particle texture at small scale reads as drifting
  motes — fine). Plus the looping tween on the PIECE's `modulate` between `Color.WHITE` and
  `curse.color().lerp(Color.WHITE, 0.5)` (~0.8 s each way). Use **CPUParticles2D, not
  GPUParticles2D** — it behaves identically under the headless/software renderer the tests
  run on, and at 8 particles the CPU cost is nil.
- **Reduced motion: static shape only.** `_draw()`: small filled diamond (4-point polygon) in
  `curse.color()` with a darker outline above the piece; a single static tint
  (`modulate = curse.color().lerp(Color.WHITE, 0.6)`) instead of the pulse; NO particles, NO
  tween. (Draw the diamond in BOTH modes if it looks good with particles too — implementer's
  call; the invariant is: reduced_motion ⇒ nothing on the board animates.)
- The mode is sampled when the marker is created (battle start). Toggling the setting
  mid-battle only affects the next battle — acceptable, note it in a comment
  (SettingsManager has no change signal; don't add one for this).
- **Scale gotcha** (same as `_set_board_badge`, battle_ui l.501–513): piece roots have
  per-piece scale — set `marker.scale = Vector2.ONE / character.scale` and position in
  world-units × inv_scale so the visual is the same size on every piece.
- Marker is a child → moves and dies with the piece automatically.

### Phase 1 checklist
- [x] curses.json + CurseData autoload + registration
- [x] base_curse + 3 variants (frenzy functional, other two stubs)
- [x] `curse` var + `apply_curse` + battle.gd assignment (+ spawn_character returns instance)
- [x] curse_marker visual incl. reduced-motion + scale compensation
- [x] Unit test `tests/unit/test_curses.gd`: create each curse id, name/desc/color/params from
      JSON; chance × difficulty multiplier math; min_floor respected (call `_maybe_curse`-logic
      with a stubbed floor value or factor the roll into a pure func
      `should_curse(floor, roll, difficulty) -> bool` for testability — prefer the pure func).
      For `roll_curse_for`: seeded RNG → deterministic assert; weight 0 curse never rolled; a
      piece named in every `excluded_pieces` → returns ""; a piece excluded from one curse
      only ever gets the others.
- [x] Headless import + `./tests/run_all.sh` green.

**DEVIATION (important, read before touching curse-related types again):** `CurseData` (and
`ItemData`, `AbilityData`, ...) autoloads are NOT resolvable as bare global identifiers during
the mandatory early "global class_name scan" that Godot runs before ANY headless `--script` run
(this is a *stronger* version of the documented entry-script gotcha — it also applies
transitively to *any* `class_name` script, not just the entry script). Concretely: `base_character.gd`
declares `class_name BaseCharacter`, so it's swept by that scan; if it (or anything it forces to
compile via a STATIC type reference — a class var, a function param, or even a local `var x:
BaseCurse` inside a method body) points at `BaseCurse` (`class_name`, `extends RefCounted`,
whose own methods read `CurseData.xxx`), the scan tries to fully compile `base_curse.gd` before
`CurseData` is registered → `SCRIPT ERROR: Compile Error: Identifier not found: CurseData` on
every single smoke test (they all transitively load a piece scene → `BaseCharacter`). Fix
applied: `base_character.gd`'s `curse` var and `apply_curse(new_curse)` param are deliberately
**untyped**, and `apply_curse` instantiates the marker via `load("res://Scripts/Curses/curse_marker.gd").new()`
instead of the bare `CurseMarker` class_name identifier (dynamic `load()` defers resolution past
the early scan, unlike a static type reference). `curse_marker.gd` itself is free to keep typed
`BaseCurse` params/vars since nothing in the early-scanned graph statically references
`CurseMarker` anymore. This is why `ItemData`/`BaseItem` never hit this: no `class_name` script
in the codebase has a static type reference to `BaseItem` (the one place `BaseItem` is used as a
type, in `battle_ui.gd`, is a local var in a script with no `class_name`, so it's compiled lazily
at scene-instantiation time, well after autoloads are up). Keep this pattern (untyped +
`load()`) for any FUTURE code that gives `BaseCharacter` (or any other early-scanned class_name
script) a static reference to a `BaseCurse`-derived type.

## Phase 2 — Curse effects

### 2a. `frenzy` (extra action)
`BattleController.start_enemy_turn()` loop (l.221–239): replace the single
`await _take_enemy_action(character)` with:
```gdscript
var actions := 1 + (character.curse.extra_actions() if character.curse else 0)
for i in actions:
	if not is_instance_valid(character): break   # lahko je umrl/izginil med akcijo
	await _take_enemy_action(character)
	if check_battle_end(): return
```
(The existing post-action `check_battle_end()` moves inside the loop.)

### 2b. Curse hook after each action
In `_take_enemy_action()` (l.243), after a successful move (`if moved:` branch), BEFORE the
flash/pause: `if character.curse: character.curse.on_action_taken(character, self)`.

### 2c. `snowfall`
- `grid_manager.gd`: public counterpart to `reveal_area`:
  ```gdscript
  # Item/curse "snowfall": ponovno pokrije polja z meglo. Polja ob zaveznikih
  # se ob začetku igralčeve poteze itak spet odkrijejo (update_fog_after_turn_start).
  func cover_area(positions) -> void:   # zrcalno reveal_area: _spawn_fog_tile(pos) po meji
  ```
  Guard each pos with `is_inside_boundary` (use `tile_map`… grid_manager has no tile_map ref —
  simplest: skip the boundary check; `_spawn_fog_tile` on an off-board tile draws harmlessly
  outside, but cleaner is to pass positions already filtered by the caller. Filter in the
  curse using `owner.tile_map.get_used_rect()` + `grid_manager.is_inside_boundary`.)
- `snowfall_curse.gd.on_action_taken(owner, bc)`: 3×3 around `owner.grid_pos` —
  `GridManager.square_radius_tiles(owner.grid_pos, CurseData.get_param(id, "radius", 1))`
  (static helper, l.74), filter to board, `owner.grid_manager.cover_area(tiles)`.
  Note: allies inside get hidden until the next `update_fog_after_turn_start` reveals 3×3
  around each ally at player-turn start — intended, no special-casing.

### 2d. `stunning_gaze` + stunned state
- `base_character.gd`: `var stunned_turns: int = 0`. In `calculate_valid_targets()` add next
  to the frozen guard (l.105): `if stunned_turns > 0: return targets`. In
  `activate_ability()` (l.434) add `if stunned_turns > 0: return false`.
- Tick down: `BattleController.end_player_turn()` (l.198), first thing: for every friendly
  `BaseCharacter` on the grid with `stunned_turns > 0`, decrement by 1. (Stun applied during
  the ENEMY turn therefore blocks exactly the player's next turn, then clears.)
- `stunning_gaze_curse.gd`: `var cooldown_left := 0`. `on_action_taken(owner, bc)`:
  if `cooldown_left > 0: cooldown_left -= 1; return`. Else
  `var seen := owner.find_visible_enemies(owner.move_range)` (for an enemy this returns
  allies), pick the closest by `grid_pos.distance_to`, set its
  `stunned_turns = CurseData.get_param(id, "duration", 1)`,
  `cooldown_left = CurseData.get_param(id, "cooldown", 2)`, and notify UI: emit a new
  `BattleController` signal `piece_stunned(character)` (add `func notify_stun(c)` on bc that
  emits it; curse calls `bc.notify_stun(target)`).
- UI feedback (STATUS, per Miha): `battle_ui.gd` —
  - connect `piece_stunned` in `_ready`; handler: `_set_board_badge(character, "STUN")` and, if
    `_shown_character == character`, refresh the panel.
  - `_show_character()` (l.652): if `character.stunned_turns > 0` → `status_value.text =
    "STUNNED"`, color `Color(0.8, 0.5, 1.0)` (new `STATUS_STUNNED_COLOR` const next to l.53).
  - Clearing: when `stunned_turns` hits 0 in the end_player_turn tick, also clear the badge —
    emit `piece_stunned` with… simpler: give battle_ui a refresh in `_on_battle_state_changed`
    (l.157): on entering `PLAYER_TURN`, sweep grid characters and
    `_set_board_badge(c, "STUN" if c.stunned_turns > 0 else "")` for allies. (Badge text ""
    hides it — l.516.) NOTE this badge shares the node with slot badges (name "SlotBadge") —
    give the stun badge its own node name (`param` the helper: copy `_set_board_badge` into
    `_set_named_badge(character, node_name, text)` and re-route both callers) so slot numbers
    and STUN don't overwrite each other.

### Phase 2 checklist
- [x] frenzy loop (+ dead-mid-frenzy guard) — smoke: frenzied enemy acts 2× in one enemy turn
- [x] on_action_taken hook wired
- [x] cover_area + snowfall — smoke: fog_nodes gains tiles around the enemy after its move
- [x] stunned state (targets + abilities blocked), tick-down, cooldown, STATUS + badge
- [x] Smoke `tests/smoke/smoke_curses.gd` printing `SMOKE_CURSES_OK` (build board by hand like
      `smoke_item_use.gd`; force-assign each curse; drive turns via
      `end_player_turn`/`start_enemy_turn`); wire into `run_all.sh`.

**DEVIATION (important, real gotcha for any future coroutine-driving smoke test):**
`smoke_item_use.gd`'s pattern (build board, call the thing, read the result, all inline) does
NOT work for anything that goes through `BattleController.start_enemy_turn()` /
`end_player_turn()`, because those `await get_tree().create_timer(...)`. `_process(delta) ->
bool` is called directly by the engine's `MainLoop`, not through GDScript's own `await`
mechanism — if `_process()` itself contains an `await` that suspends, the engine never resumes
that specific call (the test just silently stalls forever after the first suspension, prints
nothing further, zero `ERROR:` lines, and `--quit-after N` eventually kills the process with no
indication anything was wrong). `smoke_enemy_turn_pacing.gd`/`smoke_courier_package.gd` already
work around this correctly: fire the BattleController call WITHOUT `await` and poll
`current_state`/`turn_count` across ordinary subsequent frames until it settles.
`smoke_curses.gd` had to be rewritten from an inline `await`-per-stage script into an explicit
frame-polled state machine (`Stage` enum) for exactly this reason — first draft hung
indefinitely with zero error output, which is the trap: it LOOKS like a `--quit-after` tuning
problem (bumped it from 6 → 60 → 300 → 2000 frames with no change) but is actually a structural
one. `stunning_gaze`'s `curse.on_action_taken()` itself has no `await` inside, so THAT part is
safe to call synchronously within one `_process()` tick — only the `frenzy`/`snowfall` stages
(driven through the real `start_enemy_turn()`) and the final tick-down check (through
`end_player_turn()`) needed the state-machine treatment.

## Phase 3 — Enemy inspection (click enemy → red range + status)

1. `move_highlighter.gd`: copy the `ability_targets` pattern:
   `var enemy_preview: Array[Vector2i]`, `show_enemy_preview(tiles)` /
   `clear_enemy_preview()`, `const ENEMY_PREVIEW_COLOR = Color(0.8, 0.15, 0.15, 0.5)`.
   Draw ALL preview tiles in this one color (deliberately NOT green/gold; it may coexist with
   nothing else — showing a preview implies no ally selection).
2. `map_behaviour.gd`:
   - new signal `enemy_inspected(character)` (next to `selection_changed`).
   - l.211–213 (click enemy, nothing selected): instead of the no-op:
     ```gdscript
     move_highlighter.show_enemy_preview(clicked_character.calculate_valid_targets())
     enemy_inspected.emit(clicked_character)
     return
     ```
     Do NOT set `selected_character` — inspection is display-only, so all move/capture flows
     stay untouched.
   - Clear it everywhere selection state changes: in `_clear_selection()` and at the top of
     `_apply_selection()` call `move_highlighter.clear_enemy_preview()`; also clicking the same
     or another enemy just re-runs the preview; clicking empty board with nothing selected
     should clear it (the early paths that currently just `return`).
3. `battle_ui.gd`: connect `enemy_inspected` (same place `selection_changed` is connected) →
   `_show_enemy(character)`:
   ```gdscript
   portrait.texture = load("res://Assets/Sprites/enemy_%s.png" % character.strName)
   _shown_character = character
   _clear_ability_rows()
   if character.curse:
   	status_value.text = character.curse.status_text()     # "CURSED: Snowfall"
   	status_value.add_theme_color_override("font_color", character.curse.color())
   	ability1_name.text = character.curse.display_name()   # opis prekletstva v 1. vrstici
   	ability1_desc.text = character.curse.description()
   else:
   	status_value.text = "ENEMY"
   	status_value.add_theme_color_override("font_color", STATUS_DEAD_COLOR)
   ```
   (`_clear_ability_rows` leaves button disabled — good. `_on_selection_changed(null)` fires
   afterwards only if something re-emits selection — verify order; if selecting an ally later,
   the normal path overwrites the panel. Nothing else to do.)
4. Wolf note (if shop-v2 merged): the wolf is friendly — inspection doesn't apply; its sprite
   loads via `friendly_wolf.png` in `_show_character` (path already `friendly_%s`).

### Phase 3 checklist
- [x] red preview array/color/show/clear in highlighter, cleared on every selection change
- [x] enemy_inspected signal + battle_ui `_show_enemy` (curse text + color, portrait)
- [x] Smoke: call the inspection path directly with a cursed + an uncursed enemy; assert
      preview tiles non-empty and `status_value.text` contains "CURSED"; print
      `SMOKE_INSPECT_OK`; add to run_all.sh.

**Deviation:** `_on_battle_state_changed`'s existing `if is_instance_valid(_shown_character):
_show_abilities(_shown_character)` refresh (fires on every battle-state transition) would
otherwise overwrite the curse name/description we just wrote into `ability1_name`/`ability1_desc`
for an inspected enemy the next time the state changed while that panel was showing (enemies
have no real abilities, so `_show_abilities` on one just blanks the rows to "-"/disabled).
Guarded it with `and not _shown_character.is_enemy` - zero behavior change for the existing
ally-inspection path (already `is_enemy == false` there), only skips the stomp for the new
enemy-inspection path.

## Phase 4 — Difficulty selector

1. `SettingsManager.gd`: `var difficulty: String = "normal"` (`"easy"|"normal"|"hard"`),
   `func set_difficulty(value)` → set + `save_settings()`; persist in the same ConfigFile
   section as reduced_motion (`load_settings` reads it back, default "normal").
2. `settings_menu.gd` + scene: add a row mirroring the reduced-motion one — Label
   "DIFFICULTY" + `OptionButton` (EASY/NORMAL/HARD), init from
   `SettingsManager.difficulty`, `item_selected` → `set_difficulty`. `UiAudio.play_click()`
   like the other controls.
3. Curse chance already consumes it (Phase 1d — replace the `"normal"` placeholder with
   `settings_manager.difficulty`; battle.gd needs an `@onready` for the autoload).

- [x] setting + persistence + menu row + curse-chance wiring; unit-test the
      `get_curse_chance` multiplier per difficulty.

(`get_curse_chance` × difficulty was already unit-tested in Phase 1's `test_curses.gd` -
`test_get_curse_chance_applies_difficulty_multiplier` - no new test needed for that part.)

## Phase 5 — AI improvements (mild, difficulty-gated)

All inside `base_character.calculate_best_move()`; every change gated so EASY plays exactly
like today (except value-aware captures, which are always-on and mild).

1. **Value-aware captures** (always on): the capture-priority scan (l.577–587) currently
   returns the FIRST capturable target. Instead collect all capture options and return the
   highest-value one. Piece values: new `Data/ai_config.json`
   `{"piece_values": {"pawn": 1, "knight": 3, "bishop": 3, "rook": 5, "queen": 9, "king": 10, "wolf": 2}}`
   loaded by a tiny `get_piece_value(strName)` on `CurseData`? — NO: keep data loaders
   single-purpose; add the json load + getter to a new small section in the SAME
   `curse_data.gd` autoload is tempting, but cleaner: name the autoload file's scope now —
   **decision: put `ai_config.json` loading into `CurseData` renamed?** Keep it simple:
   load `ai_config.json` in `CurseData` with getters `get_piece_value(name)` and
   `get_ai_param(difficulty, key)` — one autoload for all "enemy behavior" data; note it in
   the class comment. (Renaming the autoload is not worth the churn.)
2. **Danger avoidance** (EASY 0% / NORMAL 50% / HARD 100%, from ai_config:
   `"danger_avoid_prob": {"easy": 0.0, "normal": 0.5, "hard": 1.0}`): in the chase step
   (l.593–599), compute the set of tiles any ALLY could capture next turn (union of
   `calculate_valid_targets()` over living non-enemy, non-obstacle characters —
   **reuse note (shop-v2 is merged, this exists now):** spyglass built exactly this union in
   `map_behaviour._compute_risk_tiles()` (~l.111), but intersected with the selected piece's
   valid_moves. Refactor: move the raw union into a shared
   `grid_manager.tiles_reachable_by(is_enemy_side: bool) -> Array[Vector2i]`; map_behaviour
   keeps the intersection, the AI uses the raw union. Type loop vars explicitly — this is one
   of the spots where the `get_all_characters()` Variant-inference gotcha bites, see the
   POST-SHOP-V2 note). If `randf() < prob`: among chase
   candidates, prefer the best-scoring tile NOT in the danger set; if all candidates are
   dangerous, fall back to the normal best (never paralyze the AI). Do NOT apply the filter to
   the capture step — captures stay aggressive, that's the fun.
3. **Explicit non-goals** (keep it beatable — Miha's constraint): no minimax/lookahead, no
   coordinated focus fire, no change to spotting/blind-seek/panic, no danger avoidance on
   EASY. The asymmetry (all enemies move, player moves ~1) means small biases are already a
   big swing — resist adding more.

- [ ] value-aware capture + ai_config.json + getters
- [ ] danger avoidance gated by difficulty, capture step untouched
- [ ] Unit-ish smoke: board with a pawn and a queen both capturable → AI takes the queen;
      HARD: chase candidate covered by an ally is avoided when an equal-score safe tile
      exists (seed `randf` via fixed difficulty prob 1.0). Print `SMOKE_AI_OK`.

## Phase 6 — Wrap up
- [ ] Full `./tests/run_all.sh` green; boot `battle.tscn` headless `--quit-after 5` with a
      forced floor ≥ 2 — zero ERROR lines.
- [ ] `CHANGELOG.md` entry (curses, inspection, difficulty, AI).
- [ ] `ABILITY_TIER_NOTES.md`/docs untouched; no new sprites expected — if any were generated
      anyway, `TEMP_SPRITES.md` rows.
- [ ] Small per-phase commits, Claude co-author line; leave branch unmerged for review.

## Explicitly out of scope (don't build)
- More curses beyond the 3 (framework makes them cheap later; don't invent any).
- Curses on bosses/mini-bosses being special (they roll like any enemy for now).
- Multiple curses per enemy, curse removal/cleanse interactions (King.Cleanse converts a
  cursed enemy → it keeps its curse as an ally? NO — on conversion (`_do_cleanse`,
  king.gd l.55) clear `curse` and its marker/tint: one line, do include this).
- AI lookahead/minimax, enemy ability usage, difficulty-based enemy stat changes.
- Balancing numbers (all JSON values are placeholders for Miha).

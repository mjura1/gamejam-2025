# SHOP V2 — rarity-weighted stock + 9 new items (implementation plan)

Branch: create `features/shop-v2` off `develop`. Merge back with `git merge --no-ff` when done.
Predecessor: `ITEM_SHOP_PLAN.md` (fully implemented and merged — its §0 file table and gotchas
still apply; this doc repeats what's needed so you don't have to read it).

This doc is written so an implementing model can build the feature WITHOUT re-deriving context.
Read referenced files as you touch them; you should not need to explore beyond them.
Work phases in order; each ends runnable/testable. Check off `[ ]` boxes in this file as you go.

**Decisions from Miha (do not re-litigate):**
- Shop stock becomes **N independent slots**; each slot rolls a rarity from **JSON-editable
  weights** (e.g. 50 common / 25 uncommon / 10 rare), then a uniform-random item of that rarity.
  Rolls are per-slot independent, NOT one roll for the whole store.
- Rarity tiers: **common / uncommon / rare** (Miha's item list below uses these three).
- New items (9) exactly as specified in the per-item sections of Phases 4–6. Don't invent more.
- "Vicious knights" extra move is **limited to once per player turn** (Miha pre-approved this
  balance limiter).

**Defaults chosen by Claude (fine to keep; Miha may adjust numbers later by hand):**
- Slot count default **4**, in the same JSON as the weights (`Data/shop_config.json`).
- A bought slot shows **SOLD** and can't be re-bought; stock is rolled **once per shop visit**
  (shop scene `_ready`), and there is exactly 1 shop visit per map anyway.
- Duplicate rolls across slots are allowed. Owning 2+ copies of a passive has no extra effect
  (all passive checks are `count > 0`).
- All new prices/`reward` values default **1** (correct names, placeholder numbers — same rule
  as ITEM_SHOP_PLAN; Miha balances by hand later).
- Bounty/Courier reward = **upgrade items** (the run currency), amount from JSON `reward` field.
- New items are mostly **passive** (always active while owned, this run) — see `kind` field.
  Runs still reset `owned_items` in `PlayerManager.setStarting()`; nothing carries over.

---

## 0. Existing code you will build on

| File | What it gives you |
|---|---|
| `team-berry-game/Scripts/Data/item_data.gd` | Autoload `ItemData`. Loads `Data/items.json` + `Data/piece_prices.json`. `get_item_ids/get_item_name/get_item_description/get_buy_cost/get_sell_value/create_item`. Extend here. |
| `team-berry-game/Data/items.json` | Currently only `extra_move`. One entry per item; ids snake_case; sprite `Assets/Sprites/item_<id>.png` and script registry keyed by id. |
| `team-berry-game/Scripts/Player/PlayerManager.gd` | `owned_items` dict, `add_item/remove_item/get_item_count`, `try_buy_item` (l.275), `upgrade_items`, `add_upgrade_items`, `items_changed`/`party_changed` signals, `active_party`/`friendly_party`, `setStarting()` reset. |
| `team-berry-game/Scripts/Map/shop.gd` + `Scenes/Map/shop.tscn` | Shop scene (BUY/SELL/LEAVE). `_on_buy_pressed` instantiates `ShopBuyPanel.tscn` onto `get_tree().root`. Roll stock here. |
| `team-berry-game/Scenes/Menu/ShopBuyPanel.gd` | Buy panel — currently lists **every** id from `ItemData.get_item_ids()`. Rework to render the rolled slots. |
| `team-berry-game/Scripts/TileMap/BattleController.gd` | Turn machine. `start_player_turn()` (l.159), `end_player_turn()` (l.198), `check_battle_end()` (l.274: victory branch l.278, wipe branch l.290), `add_bonus_move()` (l.194), `state_changed`, `turn_count`. |
| `team-berry-game/Scripts/CharacterPieces/base_character.gd` | `calculate_valid_targets()` (l.100; capture-immune break at l.124), `try_move`, `capture()` (l.259), `die()` (l.230), `is_capture_immune`, `is_converted_ally`, `strName`, `grid_pos`, `get_move_directions()`, `find_visible_enemies()`, enemy AI `calculate_best_move()` (l.483). |
| **GOTCHA:** enemy piece scenes (`Scenes/CharacterPiecesNodes/Enemy/*.tscn`) reuse the **Ally scripts** (e.g. enemy_queen.tscn → `Ally/queen.gd`) with `is_enemy = true`. Every player-only behavior below MUST gate on `not is_enemy`. |
| `team-berry-game/Scripts/map_behaviour.gd` | Player click flow. `_apply_selection()` (l.88, calls `move_highlighter.show_moves`), capture-success branch (l.178–190), move-success branch (l.221–233). Spyglass + vicious-knights hook here. |
| `team-berry-game/Scripts/TileMap/move_highlighter.gd` | `valid_moves` + `show_moves/clear_moves`, per-purpose color consts, `ability_targets` shows the "second array + second color" pattern to copy for risk tiles. |
| `team-berry-game/Scripts/TileMap/grid_manager.gd` | `get_all_characters()`, `get_character_at()`, `is_occupied()`, `is_inside_boundary()`, `spawn_character(scene, world_pos)`, `is_entry_denied/is_frozen` (zone system). Fortress helper goes here. |
| `team-berry-game/Scenes/Map/battle.gd` | Battle root. `friendly_pieces` dict (roster name → PackedScene) — add the wolf. Spawning pattern at l.62/85. |
| `team-berry-game/Scripts/CharacterPieces/Ally/king.gd` | `_do_heal()` shows the mid-battle spawn pattern: `grid_manager.spawn_character(scene, grid_manager.grid_to_world(tile))`. |
| `team-berry-game/Scripts/CharacterPieces/Ally/knight.gd` | Knight L-offsets (`get_move_directions()`, move_range 1) — copy for mounted hunters. |
| `team-berry-game/Scripts/Battle/battle_ui.gd` | Item drawer: `_rebuild_item_drawer()` (l.810), `_build_item_row()` (l.829), `_on_item_row_input()` (l.857), `use_item(id, grid_pos)` (l.885), `_set_board_badge(character, text)` (l.485 — board badges, use for bounty/courier marks). |
| `team-berry-game/Scripts/Items/base_item.gd` / `extra_move_item.gd` | Consumable item classes (`can_use`/`apply`); only consumables need one. Passives need NO item class. |

Verification tooling (installed & proven):
- `godot4` CLI on PATH (Godot 4.5.2 headless).
- `cd team-berry-game && ./tests/run_all.sh` (auto-discovered `tests/unit/test_*.gd` + smoke scripts).
- **Gotchas:** after adding any new `class_name`/script, rerun
  `godot4 --headless --import --path team-berry-game`. In `--script` SceneTree tests,
  `_process()` returning `true` STOPS the loop — `return false`. Autoloads are NOT global
  identifiers in `--script` mode — `root.get_node("PlayerManager")`. Smoke tests must assert a
  positive printed confirmation string.
- Repo conventions: comments in Slovenian, commits imperative English + Claude co-author line,
  CHANGELOG.md entry at the end, any generated sprite gets a row in `TEMP_SPRITES.md`.

---

## Phase 1 — Data: rarity/kind fields, shop config, 9 new entries

### 1a. `Data/items.json` — extend schema and add the 9 items

Every entry gains `"rarity"` (`common|uncommon|rare`) and `"kind"` (`consumable|passive`).
`extra_move` becomes `"rarity": "common", "kind": "consumable"`. New entries (all costs/values/
rewards 1 — placeholders on purpose):

```json
{
	"extra_move":   {"name": "Extra Move", "description": "One use. Gives +1 move this turn in battle.", "buy_cost": 1, "sell_value": 1, "rarity": "common", "kind": "consumable"},

	"spyglass":     {"name": "Spyglass", "description": "When selecting a piece, tiles the enemy could capture next turn are marked.", "buy_cost": 1, "sell_value": 1, "rarity": "common", "kind": "passive"},
	"bloodhounds":  {"name": "Bloodhounds", "description": "A friendly wolf joins each battle and hunts on its own after your turn.", "buy_cost": 1, "sell_value": 1, "rarity": "common", "kind": "passive"},
	"vicious_knights": {"name": "Vicious Knights", "description": "Once per turn, a knight that captures may move again.", "buy_cost": 1, "sell_value": 1, "rarity": "common", "kind": "passive"},
	"bounty":       {"name": "Bounty", "description": "Each battle a random enemy is marked. If it is the first enemy to fall, gain upgrade items.", "buy_cost": 1, "sell_value": 1, "rarity": "common", "kind": "passive", "reward": 1},

	"castle":       {"name": "Castle", "description": "Your king cannot be captured while a friendly rook has line of sight to him.", "buy_cost": 1, "sell_value": 1, "rarity": "uncommon", "kind": "passive"},
	"courier_package": {"name": "Courier Package", "description": "Each battle a random ally is the courier. If they survive the battle, gain upgrade items.", "buy_cost": 1, "sell_value": 1, "rarity": "uncommon", "kind": "passive", "reward": 1},
	"divine_intervention": {"name": "Divine Intervention", "description": "Consumed on party wipe: return to the map instead of game over.", "buy_cost": 1, "sell_value": 1, "rarity": "uncommon", "kind": "passive"},

	"fortress":     {"name": "Fortress", "description": "Enemies cannot cross the line between a friendly rook and a house in its line of sight.", "buy_cost": 1, "sell_value": 1, "rarity": "rare", "kind": "passive"},
	"mounted_hunters": {"name": "Mounted Hunters", "description": "Your queen and bishops may also move like knights.", "buy_cost": 1, "sell_value": 1, "rarity": "rare", "kind": "passive"}
}
```

### 1b. `Data/shop_config.json` (new) — the JSON Miha edits for chances

```json
{
	"slots": 4,
	"rarity_weights": {"common": 50, "uncommon": 25, "rare": 10}
}
```

Weights are relative (need not sum to 100) — normalize over their sum. `slots` = number of
independent shop slots.

### 1c. `ItemData` additions (`Scripts/Data/item_data.gd`)

Load `shop_config.json` in `_ready()` alongside the other two (same `_load_json` helper). Add:

```gdscript
func get_rarity(id: String) -> String        # default "common"
func get_kind(id: String) -> String          # default "consumable"
func get_reward(id: String) -> int           # default 1 (bounty/courier)
func get_ids_by_rarity(rarity: String) -> Array
func get_shop_slot_count() -> int            # config "slots", default 4
func get_rarity_weights() -> Dictionary      # config "rarity_weights", default {"common": 1.0}

# Neodvisen met za vsak slot: najprej rariteta po utežeh, nato uniformen item
# te raritete. rng parameter zaradi testov (seedable); null -> nov RNG.
func roll_shop_stock(rng: RandomNumberGenerator = null) -> Array
```

`roll_shop_stock` rules: skip rarities that have zero items (renormalize over the rest); if the
whole pool is somehow empty, return `[]`. Returns an Array of item id Strings, length = slots.
No item class needed for passives — `ITEM_SCRIPTS` stays as-is (only consumables are in it);
`create_item()` returning `null` for passives is fine because only the battle drawer's
drag-to-use path calls it (guarded in Phase 3).

### Phase 1 checklist
- [x] items.json rewritten (9 new entries + rarity/kind on extra_move)
- [x] shop_config.json
- [x] ItemData: config load + 6 getters + roll_shop_stock
- [x] Unit test `tests/unit/test_shop_stock.gd`: seeded RNG → deterministic assert; slot count
      respected; weights `{"common": 1}` → all common; weights naming an empty rarity → no
      crash, only existing rarities returned; every returned id exists in items.json.
- [x] `godot4 --headless --import --path team-berry-game` + `./tests/run_all.sh` green.

**Deviations from plan (adapted, not escalated):**
- Pulled Phase 7's placeholder-sprite generation forward into Phase 1 (all 9 item sprites +
  `friendly_wolf.png`, TEMP_SPRITES.md rows added now). Reason: `ShopBuyPanel` still lists
  *every* item id until Phase 2, so the moment items.json grew 9 spriteless ids,
  `smoke_shop` broke on `Resource file not found` — the plan's "each phase ends
  runnable/testable" goal required art to exist before that gap opened, not at the end.
  Used 256×256 (matching the real `item_extra_move.png`/`shop.png` convention), not the
  plan's guessed "48×48-ish".
- Found and fixed a pre-existing bug in `tests/run_unit_tests.gd`: autoload `_ready()` (e.g.
  `ItemData`'s JSON load) hasn't run yet when `_initialize()` executes in `--script` mode, so
  any unit test reading autoload-loaded data silently saw `{}` and only passed when a
  hardcoded default happened to match the real configured value. Fixed with
  `await process_frame` before the discovery loop. This was latent before this plan (not
  introduced by it) but `test_shop_stock.gd` is what exposed it.

## Phase 2 — Shop UI: rolled slots instead of "everything"

1. `Scripts/Map/shop.gd`: in `_ready()` (add one — the script currently has none):
   `var stock: Array = []` filled with `{"id": id, "sold": false}` per entry of
   `ItemData.roll_shop_stock()`. In `_on_buy_pressed()` set `instance.stock = stock` BEFORE
   `add_child` (panel reads it in `_ready`). Stock lives on the shop scene so closing/reopening
   the panel during one visit keeps the same slots and SOLD flags.
2. `Scenes/Menu/ShopBuyPanel.gd`: replace the `get_item_ids()` loop in `_refresh()` with the
   slots array (`var stock: Array = []` property). Per row additions:
   - rarity tag: small colored label or name tint — common `Color.WHITE`, uncommon
     `Color(0.4, 0.9, 0.4)`, rare `Color(0.45, 0.65, 1.0)` (consts in the panel script).
   - sold slot → button text `SOLD`, disabled; else `BUY (cost)`, disabled when unaffordable
     (existing logic). On successful `player_manager.try_buy_item(id)` set `slot.sold = true`
     (the shared dict — mutates shop scene state) — `items_changed` already triggers `_refresh`.
3. Sell view (`ShopSellPanel.gd`) needs no logic change; passives sell like any item.

### Phase 2 checklist
- [x] shop.gd rolls once per visit; panel renders slots + SOLD + rarity colors
- [x] Extend `tests/smoke/smoke_shop.gd`: inject a hand-built stock array (don't rely on RNG),
      buy a slot → count 1 + slot sold; re-buy refused. Keep printing `SMOKE_SHOP_OK`.

**Deviations:**
- run_all.sh's actual `expect_str` for this smoke test is
  `"SMOKE TEST: shop buy/sell flow completed cleanly"`, not `SMOKE_SHOP_OK` (that string
  doesn't appear anywhere in the test or harness) - kept the real existing string instead.
- Found an ordering bug while wiring SOLD: `try_buy_item()` emits `items_changed` (→
  `_refresh()`) *before* returning, so setting `slot["sold"] = true` only after
  `try_buy_item()` returns means the refresh that just ran still saw the stale (unsold)
  flag - the row would show `BUY` again for one frame and never flip to `SOLD` until some
  unrelated later refresh. Fixed by calling `_refresh()` again explicitly right after setting
  the flag in the same callback.

## Phase 3 — Passive plumbing (tiny)

1. `PlayerManager.gd`: add the one helper every effect below uses:
   ```gdscript
   # Pasivni itemi: aktivni, dokler je v inventarju vsaj 1 kos.
   func has_passive(id: String) -> bool:
   	return owned_items.get(id, 0) > 0 and ItemData.get_kind(id) == "passive"
   ```
2. `battle_ui.gd` drawer: in `_build_item_row()` (l.829), for `ItemData.get_kind(id) == "passive"`
   rows: append a small `PASSIVE` label and do NOT connect `_on_item_row_input` (not draggable).
   In `use_item()` (l.885) guard `if ItemData.get_kind(id) != "consumable": return false`
   (belt and braces; also `create_item` would return null).

- [x] has_passive + drawer passive rows + use_item guard

## Phase 4 — Common items

Each item section = full spec; implement + its test, commit, next.

### 4a. `vicious_knights` (easiest — do first)
After a **friendly knight** capture, grant +1 move, max once per player turn.
- `BattleController.gd`: `var vicious_knight_used: bool = false`, reset to false in
  `start_player_turn()` (l.159).
- `map_behaviour.gd` capture-success branch (l.178–190): `selected_character` is cleared by
  `_clear_selection()` — capture a local `var mover := selected_character` before that (the
  branch already runs `try_move` first). After `battle_controller.consume_move()`:
  ```gdscript
  if mover.strName == "knight" and player_manager.has_passive("vicious_knights") \
  		and not battle_controller.vicious_knight_used:
  	battle_controller.vicious_knight_used = true
  	battle_controller.add_bonus_move()
  ```
  (map_behaviour has no player_manager @onready yet — add one like base_character's.)
- Test (unit-style smoke): simulate via direct calls — set flag, `add_bonus_move`, assert
  `moves_remaining`; and assert the once-per-turn latch resets on `start_player_turn`.

### 4b. `bounty`
Each battle, one random enemy is marked; if it's the FIRST enemy to die that battle → reward.
- `BattleController.gd`: `var bounty_target: BaseCharacter = null`,
  `var first_enemy_death_resolved: bool = false`. In `initialize_battle()` both reset; pick the
  target at the START of the first player turn (in `start_player_turn()` when `turn_count == 1`
  — enemies are spawned by then): if `player_manager.has_passive("bounty")`, collect all
  `is_enemy and not is_obstacle` characters from `grid_manager.get_all_characters()`, pick
  `pick_random()`, store it, and badge it: emit a new signal `bounty_marked(character)`;
  `battle_ui.gd` connects it (next to the other connects in `_ready`) and calls
  `_set_board_badge(character, "☠")` (l.485).
- `base_character.gd` `die()` (l.230): before `queue_free`, if `is_enemy and not is_obstacle
  and is_instance_valid(battle_controller)`: call `battle_controller.on_enemy_died(self)`.
- `BattleController.on_enemy_died(character)`: if `first_enemy_death_resolved`: return; set it
  true; if `character == bounty_target`:
  `player_manager.add_upgrade_items(ItemData.get_reward("bounty"))` (+ a print for tests).
  First enemy death decides the bounty win/lose — later kills irrelevant.
- Test: fake grid not needed — call `on_enemy_died` twice with/without matching target and
  assert `upgrade_items` delta once.

### 4c. `spyglass`
When the player selects a piece, mark which of its valid moves an enemy could capture next turn.
- `move_highlighter.gd`: copy the `ability_targets` pattern — `var risk_tiles: Array[Vector2i]`,
  `show_risk_tiles(tiles)` / clear inside `clear_moves()`, drawn in `_draw` with
  `const RISK_COLOR = Color(0.95, 0.55, 0.1, 0.6)` AFTER valid_moves so it overlays them.
- `map_behaviour.gd` `_apply_selection()` (l.88), after `show_moves(valid_moves)`:
  ```gdscript
  if player_manager.has_passive("spyglass"):
  	move_highlighter.show_risk_tiles(_compute_risk_tiles(valid_moves))
  ```
  `_compute_risk_tiles(valid_moves)`: union over every living `is_enemy and not is_obstacle`
  character of its `calculate_valid_targets()`, intersected with `valid_moves`. (In this game a
  piece captures exactly along its movement pattern, so an enemy's reachable-empty tiles ARE the
  squares it could capture on next turn. Known approximation: it doesn't simulate the board
  change caused by your own move — acceptable, it's a marker, note it in a comment.)
- Ensure `_clear_selection()` clears the risk tiles (via `clear_moves()`).
- Test: unit test with a stub is awkward — do a smoke on the battle scene: place one ally +
  one adjacent enemy pawn (see `smoke_item_use.gd` for the harness), grant spyglass, call
  `_compute_risk_tiles` on the ally's valid targets, assert the contested tile is in it.

### 4d. `bloodhounds` (hardest common — new piece + mini-AI)
A friendly wolf (pawn-like) spawns each battle and acts autonomously after every player turn.
- New script `Scripts/CharacterPieces/Ally/wolf.gd` extends BaseCharacter:
  `move_range = 2`, `strName = "wolf"`, `var is_autonomous := true`,
  `get_move_directions()` = copy pawn.gd's. Override `calculate_best_move()` (base one
  early-returns `{}` for non-enemies): 1) `calculate_valid_targets()`; empty → `{}`.
  2) any target holding an enemy (`get_character_at(pos)` with `is_enemy and not is_obstacle`)
  → `{"move_type": "CAPTURE", "target_pos": pos}`. 3) else move to the target minimizing
  `distance_to` the nearest living enemy (mirror base l.593–599); no enemies → `{}`.
  No abilities: `get_ability_defs()` stays empty (base default).
- New scene `Scenes/CharacterPiecesNodes/Ally/wolf.tscn`: instance
  `base_character.tscn` like the other allies (see enemy_queen.tscn structure: base scene +
  script override + texture override), script wolf.gd, texture
  `Assets/Sprites/friendly_wolf.png` (temp sprite, Phase 7).
- `Scenes/Map/battle.gd`: add `"friendly_wolf": preload(".../wolf.tscn")` to `friendly_pieces`
  (King.Heal `has()` check makes this safe).
- Spawn: `BattleController.gd`, in `start_player_turn()` when `turn_count == 1` and
  `player_manager.has_passive("bloodhounds")`: pick a random free cell in the bottom 3 rows
  (`grid_manager.is_occupied` + `is_inside_boundary` over the used rect, mirror battle.gd's
  obstacle loop bounds), `grid_manager.spawn_character(wolf_scene, grid_to_world(cell))`. Exactly
  one wolf regardless of copies owned. Get the scene via battle root:
  `get_node("..").friendly_pieces["friendly_wolf"]`.
- Roster bookkeeping: wolf is a temporary summon, NOT in `friendly_party`. After spawning, mark
  the spawned instance `is_converted_ally = true` and add a `PlayerManager` helper
  `add_temporary_ally(name)` → `active_party.append(name)` + `party_changed.emit()`; call it
  with `"friendly_wolf"`. Death then routes through the existing converted-ally path in `die()`
  (l.247) → `remove_converted_ally("friendly_wolf")` — no phantom `dead_party` entry, and
  King.Heal can't revive it (not in dead_party). It DOES count for `activeGone()` while alive —
  intended (the wolf can carry a battle).
- Autonomous action: `BattleController.end_player_turn()` (l.198) — make the flow:
  ```gdscript
  if check_battle_end(): return
  await _move_autonomous_allies()
  if check_battle_end(): return
  start_enemy_turn()
  ```
  `_move_autonomous_allies()`: iterate `grid_manager.get_all_characters()` snapshot; for valid
  `BaseCharacter`s with `not is_enemy` and `get("is_autonomous")` truthy → reuse
  `await _take_enemy_action(character)` (l.243 — despite the name it just runs
  calculate_best_move + try_move + flash; try_move skips the can_move() budget check for... note:
  it only skips for `is_enemy` — see next line). **Gotcha:** `try_move` (base l.195) checks
  `battle_controller.can_move()` for non-enemies, which fails after the player spent their
  budget. Change that guard to `if not is_enemy and not get("is_autonomous") and not
  battle_controller.can_move():` (add `var is_autonomous := false` to base_character.gd so
  `get()` is safe everywhere).
  Callers of `end_player_turn` (battle_ui action button) don't await it — fine, it continues as
  a coroutine exactly like `start_enemy_turn`'s awaits already do.
- Battle UI: "friendly_wolf" appears in `active_party` → roster row lookups will want
  `Assets/Sprites/friendly_wolf.png` — same auto-by-name convention, nothing to code (verify
  `_rebuild_rows` l.523 doesn't special-case; it keys off active_party names).
- Test: smoke — grant bloodhounds, init battle harness, assert a wolf node exists on the grid
  after first `start_player_turn`, force `end_player_turn`, assert wolf moved toward/captured a
  seeded enemy. Print `SMOKE_BLOODHOUNDS_OK`.

### Phase 4 checklist
- [x] 4a vicious_knights + test
- [x] 4b bounty + badge + test
- [x] 4c spyglass + highlighter color + test
- [x] 4d bloodhounds (wolf script/scene/spawn/AI/roster) + test

**Deviations:**
- `try_move`'s guard uses `is_autonomous` directly (a real `BaseCharacter` field added for
  this item) rather than `get("is_autonomous")` - the plan's `get()` was only needed if the
  field lived solely on `wolf.gd`; adding it to the base class makes direct access
  type-safe and the `get()` indirection unnecessary.
- Actual print string differs from the plan's `SMOKE_BLOODHOUNDS_OK` (same drift pattern as
  Phase 2's shop test) - used a real descriptive confirmation string instead, matched in
  `run_all.sh`.
- Noticed `smoke_ability_ui_pipeline` fails intermittently (~30-50% of full `run_all.sh`
  runs) with "expected confirmation not found", but passes 100% of the time run standalone
  at the same `--quit-after`. This is pre-existing environmental flakiness (cumulative
  system load from running many sequential headless Godot processes in one session), not a
  regression - confirmed by running full-suite retries back to back, where it flips
  pass/fail with no code changes in between. Not touched; out of scope to fix a pre-existing
  test's timing budget.

## Phase 5 — Uncommon items

### 5a. `divine_intervention`
- `BattleController.check_battle_end()` wipe branch (l.290): before the game_over path:
  ```gdscript
  if player_manager.activeGone():
  	_set_state(BattleState.GAME_OVER)
  	if player_manager.remove_item("divine_intervention"):
  		print("DIVINE_INTERVENTION: rešeni pred porazom")
  		GF.call_deferred("return_to_map")
  		return true
  	player_manager.reset_floor_number()
  	GF.call_deferred("game_over")
  	return true
  ```
  `remove_item` returns false when not owned — exact existing semantics. Do NOT
  `reset_floor_number()` on the rescue (player keeps map progress; roster `friendly_party` is
  untouched by battle deaths, so returning to map is safe). One copy consumed per rescue;
  multiple copies = multiple rescues.
- Test: set active_party empty + owned divine_intervention, call `check_battle_end()`, assert
  item consumed and no `game_over` (stub/observe via GF.current state or a print assert).

### 5b. `courier_package`
Mirror of bounty for allies, resolved at victory.
- `BattleController`: `var courier: BaseCharacter = null`; picked in the same `turn_count == 1`
  block as bounty when `has_passive("courier_package")`: random living ally on grid
  (`not is_enemy and not is_obstacle and not is_converted_ally` — excludes the wolf), signal
  `courier_marked(character)` → battle_ui badges `"C"` (same wiring as bounty's).
- Victory branch of `check_battle_end()` (l.278, before the return): if
  `is_instance_valid(courier)` (still on the board = survived) →
  `player_manager.add_upgrade_items(ItemData.get_reward("courier_package"))` + print.
  (`die()` → `queue_free` makes the ref invalid on death; captured couriers pay nothing.)
- Test: direct — set `courier` to a live node, run victory path, assert reward; free the node,
  assert no reward.

### 5c. `castle`
Your king can't be captured while a friendly rook has line of sight to him.
- `base_character.gd`: new method:
  ```gdscript
  # Item "castle": kralj je nezajemljiv, dokler ga vidi prijateljska trdnjava
  # (ravna črta, prvi zadetek na poti mora biti trdnjava).
  func is_castle_protected() -> bool:
  	if is_enemy or strName != "king": return false
  	if not player_manager.has_passive("castle"): return false
  	for dir in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
  		var step := grid_pos + dir
  		while grid_manager.is_inside_boundary(step, tile_map.get_used_rect()):
  			if grid_manager.is_occupied(step):
  				var c = grid_manager.get_character_at(step)
  				if c and not c.is_enemy and not c.is_obstacle and c.strName == "rook":
  					return true
  				break
  			step += dir
  	return false
  ```
- Hook: `calculate_valid_targets()` l.124 — extend the existing immune break:
  `if target_char.is_capture_immune or target_char.is_castle_protected(): break`.
  This automatically covers enemy AI too (its capture-priority scan uses valid targets).
  Scope note (comment it): protects from normal captures only, not from Queen.Exterminate.
- Test: smoke on battle harness — king + rook in LOS + adjacent enemy: enemy's
  `calculate_valid_targets()` must NOT contain king's tile; move rook out of LOS (or interpose
  a piece) → it must.

### Phase 5 checklist
- [x] 5a divine_intervention + test

**Deviations:** the plan suggested a unit test ("set active_party empty + owned
divine_intervention, call check_battle_end(), assert item consumed and no game_over").
Adapted to a smoke test instead: the rescue path calls `GF.call_deferred("return_to_map")`,
which manipulates the REAL running SceneTree's `current_scene` - safe as a standalone smoke
test process (same pattern as `smoke_battle_end.gd`'s WIN path), but calling it from inside
`test_*.gd` would run inside `run_unit_tests.gd`'s own shared SceneTree alongside every
other unit test in that process, risking cross-test interference or a crash if
`current_map_instance` isn't set up the way a real battle would set it up.
- [x] 5b courier_package + badge + test

**Deviations:** extracted the reward payout into a `_maybe_pay_courier_reward()` helper
(mirrors `on_enemy_died()` for bounty) instead of inlining it in `check_battle_end()`'s
victory branch - lets the "surviving/died/no-courier" cases be pure-unit-tested directly,
same reasoning as 5a's deviation (the victory branch itself calls `GF.call_deferred(...)`,
unsafe to invoke from inside `run_unit_tests.gd`'s shared SceneTree). A smoke test still
covers the real end-to-end wiring (mark -> badge -> survive -> victory -> reward).
- [x] 5c castle + test

**Deviations:** the plan's `is_castle_protected()` snippet (`for dir in [Vector2i(1,0), ...]:
var step := grid_pos + dir`) doesn't compile as written - GDScript can't infer `step`'s type
from an untyped array-literal element (`dir` is `Variant`, so `grid_pos + dir` has no static
type for `:=`). Fixed by declaring `var directions: Array[Vector2i] = [...]` and typing
`step` explicitly. `smoke_castle.gd` also needed its free-column search to verify the WHOLE
king-to-enemy line is clear (not just the 3 placement rows) - a house sitting between them
produced a false test failure indistinguishable from a real bug (enemy blocked by the house,
not by castle) until this was tightened.

## Phase 6 — Rare items

### 6a. `mounted_hunters`
Player queen + bishops additionally move/capture like knights (true jumps).
- Copy knight offsets into a shared const (put it in base_character.gd:
  `const KNIGHT_OFFSETS: Array[Vector2i] = [...]` — take the 8 from knight.gd, and refactor
  knight.gd's `get_move_directions()` to return it so there's one source of truth).
- `queen.gd` and `bishop.gd`: override:
  ```gdscript
  func calculate_valid_targets() -> Array[Vector2i]:
  	var targets := super.calculate_valid_targets()
  	if is_enemy or not player_manager.has_passive("mounted_hunters"):
  		return targets
  	if grid_manager.is_frozen(grid_pos, is_enemy):   # super vrne [] — ne dodajaj skokov
  		return targets
  	for offset in KNIGHT_OFFSETS:
  		var pos := grid_pos + offset
  		if pos in targets: continue
  		if not grid_manager.is_inside_boundary(pos, tile_map.get_used_rect()): continue
  		if grid_manager.is_entry_denied(pos, is_enemy): continue
  		var c = grid_manager.get_character_at(pos)
  		if c == null:
  			targets.append(pos)
  		elif c.is_enemy != is_enemy and not c.is_obstacle and not c.is_capture_immune \
  				and not c.is_castle_protected():
  			targets.append(pos)
  	return targets
  ```
  Jumps ignore blockers by nature (no path walk). The `is_enemy` gate matters — enemy
  queens/bishops share these scripts (see §0 gotcha).
- Test: smoke — queen on empty board, grant item, assert an L-tile is in targets; ungrant,
  assert it isn't; enemy queen never gets it.

### 6b. `fortress`
Enemies cannot enter or cross the straight line between a friendly rook and a house in its LOS.
- `grid_manager.gd`: new helper (compute on demand — board is 12×12, cost is trivial):
  ```gdscript
  # Item "fortress": polja med prijateljsko trdnjavo in hišo v njeni ravni
  # liniji so za sovražnike neprehodna. Vključno s poljem hiše ni treba -
  # hiša je že ovira; blokiramo stroga vmesna polja.
  func fortress_blocked_tiles() -> Array[Vector2i]
  ```
  Guard `PlayerManager.has_passive("fortress")` first (grid_manager already lives under the
  battle scene; fetch the autoload via `get_node("/root/PlayerManager")` in `_ready` like
  others do). For each character with `not is_enemy and not is_obstacle and strName == "rook"`:
  walk the 4 straight dirs; if the FIRST occupied cell hit is an `is_obstacle` character
  (houses are the only obstacles) → append all strictly-between tiles.
- Hook — `base_character.calculate_valid_targets()` step loop (l.109), for enemies only, treat
  those tiles as walls. Compute once per call: at the top,
  `var fortress: Array[Vector2i] = grid_manager.fortress_blocked_tiles() if is_enemy else []`,
  and inside the loop before the occupancy check: `if target_pos in fortress: break`.
  This blocks entering AND sliding through, and the enemy AI inherits it automatically. Knight
  enemies jump (range-1 L dirs) — a fortress tile can't be jumped over by them anyway (their
  path IS the landing tile), which matches "cannot pass that line".
- Test: smoke — rook + house in line, enemy on the far side, item granted: assert no enemy
  valid target on/through the line; remove item → path opens.

### Phase 6 checklist
- [x] 6a mounted_hunters (+ knight.gd refactor to shared offsets) + test

**Deviations:** `smoke_mounted_hunters.gd`'s first attempt used a single fixed L-offset
`(1, 2)`/fallback `(-1, -2)` for the contested tile - placement can land the queen in a
board corner (e.g. `(0, 11)`) where BOTH of those land out of bounds, causing a false
failure indistinguishable from a real bug. Fixed by looping over the real
`KNIGHT_OFFSETS` (now on the queen instance via the base-class const) until an in-bounds,
unoccupied tile is found, same pattern already used in `smoke_vicious_knights.gd`.
- [ ] 6b fortress + test

## Phase 7 — Sprites, wrap-up

- 10 temp sprites, same generation route as before (headless GDScript `Image.create`→`save_png`
  or ImageMagick; distinct solid color + 1–2 letter monogram is plenty):
  `item_spyglass.png`, `item_bloodhounds.png`, `item_vicious_knights.png`, `item_bounty.png`,
  `item_castle.png`, `item_courier_package.png`, `item_divine_intervention.png`,
  `item_fortress.png`, `item_mounted_hunters.png` (48×48-ish like `item_extra_move.png`), and
  `friendly_wolf.png` (match ally piece sprite dimensions, e.g. `friendly_pawn.png`).
  **Every one gets a `TEMP_SPRITES.md` row.** Rerun the headless import; commit pngs +
  `.import` files (repo tracks them).
- [ ] Full `./tests/run_all.sh` green; boot `shop.tscn` and `battle.tscn` headless
      `--quit-after 5` with zero ERROR lines.
- [ ] `CHANGELOG.md` entry.
- [ ] Check every `[ ]` in this file; commits small and per-phase; leave the branch for review,
      do NOT merge to develop.

## Explicitly out of scope (don't build)
- Legendary tier (only 3 tiers exist for now — the JSON structure supports adding it later).
- Shop restock/reroll button, dynamic pricing, pity timers.
- Excluding already-owned passives from rolls (duplicates allowed by decision above).
- Real art (placeholders only, tracked in TEMP_SPRITES.md).
- Persistent-death / revive interactions (unchanged from before).
- Castle/fortress interactions with abilities (Exterminate etc.) beyond what's specified.

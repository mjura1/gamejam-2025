# ITEM SHOP — implementation plan

Branch: `features/item-shop` (branched off `develop`, all of map-improvements / upgrade-items /
battle-ui already merged). Merge back into `develop` with `git merge --no-ff` when done.

This doc is written so an implementing model can build the feature WITHOUT re-deriving context.
All file paths, existing APIs, schemas and gotchas are spelled out. Read the referenced files as
you touch them, but you should not need to explore beyond them. Work through the phases in order;
each phase ends runnable/testable. Check items off in this file as you go (edit the `[ ]` boxes).

**Design decisions already made with Miha — do not re-litigate:**
- Currency = the existing **upgrade items** (`PlayerManager.upgrade_items`). No new currency.
- Shop appears on **map 2 and map 3 only** (tier index 1 and 2), as a **whole floor** in the
  middle of the map (like the campfire floor — every path passes through it), so exactly 1 shop
  visit per map. Tier 0 has no shop.
- On map 3 the middle floor (4) is currently the friendly-king recruit floor → **move the king
  recruit floor to 3, shop takes floor 4.**
- Items follow the pieces pattern: **1 base item class**, variants swap id/name/sprite/effect.
- Only ONE real item for now: `extra_move` (single-use, +1 move this turn in battle) — it's the
  test item to prove the pipeline. Don't invent more items.
- All prices live in JSON, **every value defaults to 1** (correct names, placeholder numbers —
  Miha will balance by hand later).
- Shop can **buy items** and **sell items AND pieces** (from active party and reserve).
- In battle, items are reached via a **slim vertical bar between the board and the side panel**
  with a `<` / `>` toggle button that expands/collapses an item list; items are used by
  **drag-and-drop** onto the board.
- Any generated/placeholder sprite MUST be recorded in `TEMP_SPRITES.md` (repo root, already
  created) so the team knows what to replace with real art.

---

## 0. Existing code you will build on (read these first)

| File | What it gives you |
|---|---|
| [team-berry-game/Scripts/Player/PlayerManager.gd](team-berry-game/Scripts/Player/PlayerManager.gd) | Autoload. `upgrade_items`, `items_changed` / `party_changed` signals, `friendly_party` / `reserve_party` (Array[String] of roster names like `"friendly_pawn"`), `setStarting()` run-reset, `move_active_to_reserve()` shows the "never leave active party empty" guard. |
| [team-berry-game/Scripts/Data/ability_data.gd](team-berry-game/Scripts/Data/ability_data.gd) + [team-berry-game/Data/abilities.json](team-berry-game/Data/abilities.json) | The exact autoload-reads-JSON pattern to copy for item/price data. |
| [team-berry-game/Scripts/Map/map_point.gd](team-berry-game/Scripts/Map/map_point.gd) | `Room.RoomType` enum + `RoomTypeNames` dict — add `shop` here. |
| [team-berry-game/Scripts/Map/MapGenerator.gd](team-berry-game/Scripts/Map/MapGenerator.gd) | `TIER_CONFIGS` (per-map floors/bosses/special floors), `_configure_tier()`, `_assign_room_types()` — add the shop floor here. |
| [team-berry-game/Scripts/Map/MapController.gd](team-berry-game/Scripts/Map/MapController.gd) | `_handle_event()` — routes a clicked room by `RoomTypeNames` string, then calls `GF.start_event(type)`. |
| [team-berry-game/Scripts/Map/GameFlow.gd](team-berry-game/Scripts/Map/GameFlow.gd) | Autoload `GF`. `start_event()` scene-switching (campfire branch is the model for shop), `return_to_map()`, `_change_scene_instance()`. |
| [team-berry-game/Scripts/Map/map_node_icon.gd](team-berry-game/Scripts/Map/map_node_icon.gd) | Map icons auto-load `res://Assets/Sprites/<room_type_name>.png` — so a `shop.png` sprite is ALL you need for the map icon. |
| [team-berry-game/Scripts/Map/campfire.gd](team-berry-game/Scripts/Map/campfire.gd) + [team-berry-game/Scenes/Map/campfire.tscn](team-berry-game/Scenes/Map/campfire.tscn) | The campfire menu scene (buttons that spawn panels, REST/BACK → `GF.return_to_map()`) — the shop scene mirrors this shape. |
| [team-berry-game/Scenes/Menu/CampfireUpgradePanel.gd](team-berry-game/Scenes/Menu/CampfireUpgradePanel.gd) / `CampfirePartyPanel.gd` + their `.tscn` | Panel style to copy for the shop's buy/sell UI (note: panels are wrapped in a CanvasLayer so the gameplay camera doesn't pan them — copy that). |
| [team-berry-game/Scripts/Battle/battle_ui.gd](team-berry-game/Scripts/Battle/battle_ui.gd) + [team-berry-game/Scenes/Battle/battle_ui.tscn](team-berry-game/Scenes/Battle/battle_ui.tscn) | Battle HUD (CanvasLayer). Layout: `Root/BoardArea` (left) + `Root/SidePanel` (right). Contains the whole manual drag-and-drop pattern to reuse for items: `_begin_drag()` (l.353), `_input()` ghost-follow (l.380), `_resolve_drop()` (l.392), `_screen_to_grid()` (l.419), shared `%DragGhost` TextureRect. |
| [team-berry-game/Scripts/TileMap/BattleController.gd](team-berry-game/Scripts/TileMap/BattleController.gd) | Turn state machine. `moves_remaining` (l.41), `moves_changed(remaining, max_moves)` signal, `current_state` / `BattleState.PLAYER_TURN`, `can_move()`. The extra-move item pokes this. |
| Autoload registrations | `team-berry-game/project.godot` `[autoload]` block (KeybindManager, SettingsManager, GF, PlayerManager, UiAudio, AbilityData) — register `ItemData` here. |

Verification tooling (already installed & proven):
- `godot4` CLI on PATH (`~/.local/bin`), Godot 4.5.2 headless.
- Test harness: `cd team-berry-game && ./tests/run_all.sh` (imports assets if needed, runs
  `tests/unit/test_*.gd` auto-discovered unit tests + smoke scripts).
- **Gotchas:** after adding any new `class_name` script rerun
  `godot4 --headless --import --path team-berry-game` or `load()` won't resolve it. In
  `--script` SceneTree tests, `_process()` returning `true` STOPS the loop — always
  `return false` and let `--quit-after` end it. Autoloads are NOT global identifiers in
  `--script` mode — use `root.get_node("PlayerManager")`. A smoke test must assert a positive
  printed confirmation, not just "no ERROR lines".

---

## Phase 1 — Data: JSONs + ItemData autoload

### 1a. `team-berry-game/Data/items.json` (new)

One entry per shop item. `extra_move` is the only real item; keep ids snake_case — sprites and
effect scripts are looked up by id.

```json
{
	"extra_move": {"name": "Extra Move", "description": "One use. Gives +1 move this turn in battle.", "buy_cost": 1, "sell_value": 1}
}
```

### 1b. `team-berry-game/Data/piece_prices.json` (new)

Sell prices for party pieces. **Keys are the roster strings** exactly as stored in
`friendly_party` / `reserve_party` (so no name mapping is ever needed):

```json
{
	"friendly_pawn": {"sell_value": 1},
	"friendly_knight": {"sell_value": 1},
	"friendly_rook": {"sell_value": 1},
	"friendly_bishop": {"sell_value": 1},
	"friendly_queen": {"sell_value": 1},
	"friendly_king": {"sell_value": 1}
}
```

All values 1 on purpose (names correct, numbers placeholder).

### 1c. `team-berry-game/Scripts/Data/item_data.gd` (new autoload `ItemData`)

Copy the shape of `ability_data.gd` exactly (comments in Slovenian like the rest of the repo).
Loads BOTH jsons in `_ready()`. API:

```gdscript
func get_item_ids() -> Array            # keys of items.json (shop stock = everything, for now)
func get_item_name(id: String) -> String        # "name", fallback: id
func get_item_description(id: String) -> String
func get_buy_cost(id: String) -> int            # default 1 if missing
func get_sell_value(id: String) -> int          # default 1
func get_piece_sell_value(roster_name: String) -> int   # from piece_prices.json, default 1
func create_item(id: String) -> BaseItem        # instantiates from ITEM_SCRIPTS registry below
```

Registry (the "1 base item, swap per-variant" piece-pattern equivalent):

```gdscript
const ITEM_SCRIPTS: Dictionary = {
	"extra_move": preload("res://Scripts/Items/extra_move_item.gd"),
}
```

Register in `project.godot` after `AbilityData`:
`ItemData="*res://Scripts/Data/item_data.gd"`.

### 1d. Item classes

`team-berry-game/Scripts/Items/base_item.gd` (new):

```gdscript
class_name BaseItem
extends RefCounted

var id: String = ""

func display_name() -> String: return ItemData.get_item_name(id)
func icon_texture() -> Texture2D: return load("res://Assets/Sprites/item_%s.png" % id)

# battle_controller: BattleController; grid_pos: cell the item was dropped on.
# Returns true if the item may be consumed here. Base: usable any time it's the player's turn.
func can_use(battle_controller, grid_pos: Vector2i) -> bool:
	return battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN

# Apply the effect. Return true on success (caller then consumes 1x from inventory).
func apply(battle_controller, grid_pos: Vector2i) -> bool:
	return false
```

`team-berry-game/Scripts/Items/extra_move_item.gd` (new):

```gdscript
extends BaseItem
# Enkratna uporaba: +1 premik v TEJ potezi. Cilj (grid_pos) je nepomemben.
func _init(): id = "extra_move"
func apply(battle_controller, _grid_pos: Vector2i) -> bool:
	battle_controller.add_bonus_move()
	return true
```

In `BattleController.gd` add (next to `consume_move()`, ~l.183):

```gdscript
# Item "extra_move": dodatni premik v trenutni potezi. Namerno lahko preseže
# moves_per_turn - UI label potem kaže npr. 2/1, kar je pravilno.
func add_bonus_move():
	moves_remaining += 1
	moves_changed.emit(moves_remaining, player_manager.moves_per_turn)
```

### 1e. Inventory in PlayerManager

Add to `PlayerManager.gd` (reuse the existing `items_changed` signal — battle UI and panels
already listen to it):

```gdscript
# Inventar shop itemov: item id ("extra_move") -> količina.
var owned_items: Dictionary = {}

func add_item(id: String, amount: int = 1):
	owned_items[id] = owned_items.get(id, 0) + amount
	items_changed.emit()

# Vrne false, če itema ni. Odšteje 1 in počisti ključ pri 0.
func remove_item(id: String) -> bool: ...

func get_item_count(id: String) -> int: return owned_items.get(id, 0)
```

Reset in `setStarting()`: `owned_items = {}` (runs don't carry items over — same rule as
`upgrade_items`).

Buy/sell primitives also live here (shop UI stays dumb):

```gdscript
func try_buy_item(id: String) -> bool          # cost = ItemData.get_buy_cost; deduct upgrade_items, add_item
func try_sell_item(id: String) -> bool         # remove_item + upgrade_items += sell_value; items_changed
func try_sell_active_piece(index: int) -> bool # guard: refuse if friendly_party.size() <= 1 (same rule as move_active_to_reserve)
func try_sell_reserve_piece(index: int) -> bool
```

Selling a piece: erase from the array, `upgrade_items += ItemData.get_piece_sell_value(name)`,
emit BOTH `party_changed` and `items_changed`.

### Phase 1 checklist
- [x] `Data/items.json`, `Data/piece_prices.json`
- [x] `Scripts/Data/item_data.gd` + autoload entry in `project.godot`
- [x] `Scripts/Items/base_item.gd`, `Scripts/Items/extra_move_item.gd`
- [x] `BattleController.add_bonus_move()`
- [x] `PlayerManager`: `owned_items` + add/remove/get + 4 try_* funcs + reset in `setStarting()`
- [x] New unit test `tests/unit/test_items.gd`: buy/sell item math, sell-piece math, last-active-piece
      guard, remove_item on empty. (Gotcha: assign typed arrays via a locally-typed var, see §0.)
- [x] `godot4 --headless --import --path team-berry-game` then `./tests/run_all.sh` green.

## Phase 2 — Map integration (shop room)

1. `map_point.gd`: append `shop` **at the END of the enum** (existing rooms are serialized as
   ints — reordering would corrupt meaning) and add `RoomType.shop : "shop"` to `RoomTypeNames`.
2. `MapGenerator.gd`:
   - `TIER_CONFIGS`: tier 1 gets `"shop_floor": 3` (7 floors → middle). Tier 2: change
     `"recruit_floor": 4` → `3` and add `"shop_floor": 4` (9 floors → middle; mini-boss at 6,
     campfire 7, boss 8 — no collisions). Tier 0: no key.
   - Instance var `var shop_floor: int = -1`; in `_configure_tier()`:
     `shop_floor = config.get("shop_floor", -1)`.
   - `_assign_room_types()`: add `elif i == shop_floor: room.type = Room.RoomType.shop` into the
     if/elif chain (anywhere after the boss/mini-boss branches; the floors are distinct by
     construction).
3. `MapController._handle_event()`: shop adds nothing to any party — no new branch needed
   (the `begins_with` checks all miss and it falls through to `GF.start_event`). Leave
   `addSnow()` as is.
4. `GameFlow.gd`: `const SHOP_SCENE = preload("res://Scenes/Map/shop.tscn")`; in `start_event()`
   add a branch like campfire's:
   `if room_type == Room.RoomType.shop: _change_scene_instance(SHOP_SCENE.instantiate()); return`
   (no `resetActives()` — that's battle prep only).
5. Map icon: create placeholder `Assets/Sprites/shop.png` (see Phase 4) — `map_node_icon.gd`
   picks it up automatically by name. Nothing to code.

### Phase 2 checklist
- [x] enum + names + generator config/var/assign branch
- [x] GameFlow shop branch (scene from Phase 3 must exist to preload — do Phase 3 tscn stub first
      or temporarily point at campfire.tscn, but don't commit that)
- [x] Headless check: `godot4 --headless --path team-berry-game --scene res://Scenes/Map/map.tscn --quit-after 5`
      → zero new errors. Since map 1 has no shop, ALSO extend/add a smoke or unit test that calls
      `MapGenerator.new().generate_map(1)` and `(2)` and asserts: some room of type `shop` exists
      exactly on the configured floor, every column that's non-null on that floor is `shop`, and
      tier 2 recruit floor is 3. Print a positive confirmation string and assert on it.

## Phase 3 — Shop scene (buy / sell / leave)

New: `Scenes/Map/shop.tscn` + `Scripts/Map/shop.gd`, mirroring the campfire pair
(`Control` root, full-rect, a title, an `HBoxContainer` of buttons). Buttons: **BUY**, **SELL**,
**LEAVE**. LEAVE → `GF.return_to_map()` (shop is single-visit per map by construction — the room
gets marked visited like any other; nothing extra to do).

Panels — copy the structure/wiring style of `CampfireUpgradePanel` (it already renders rows,
listens to `items_changed`, greys out unaffordable buttons). Either one `ShopPanel.tscn` with two
tabs or two panels toggled by BUY/SELL — implementer's choice, keep it simple. Requirements:

**Buy view** — one row per id in `ItemData.get_item_ids()`: item icon, name, description,
cost in upgrade items, `BUY` button. Header shows current `PlayerManager.upgrade_items`.
Button disabled when `upgrade_items < buy_cost`. Click → `PlayerManager.try_buy_item(id)`;
UI refreshes via `items_changed`. Play `UiAudio.play_click()` like other menus.

**Sell view** — two sections:
- *ITEMS*: one row per owned item id: icon, name, `xN` count, sell value, `SELL` button →
  `try_sell_item(id)`.
- *PIECES*: one row per entry of `friendly_party` (tag it "ACTIVE") then `reserve_party`
  (tag "RESERVE"): piece sprite (`res://Assets/Sprites/<roster_name>.png`), name, sell value,
  `SELL` button → `try_sell_active_piece(i)` / `try_sell_reserve_piece(i)`. Rebuild the list on
  `party_changed`. The last remaining active piece's SELL button: disabled (guard exists in
  PlayerManager too — belt and braces).

Godot layout gotcha: the campfire panels wrap content in a `CanvasLayer` so the world camera
doesn't move it. The shop scene replaces the whole current scene (like campfire), so a plain
`Control` root is fine — but if you spawn sub-panels onto `get_tree().root` the CanvasLayer
wrapper pattern applies.

### Phase 3 checklist
- [x] shop.tscn + shop.gd + panel scene(s), buy + sell + leave working
- [x] Smoke test `tests/smoke/smoke_shop.gd`: build the state by hand (see how
      `smoke_battle_end.gd` fakes `GF.current_map_instance`), instantiate shop scene, call the
      buy handler with 0 items (must refuse), grant 2 upgrade items, buy `extra_move` (must
      succeed: count 1, upgrade_items 1), sell it back (upgrade_items 2), sell a reserve piece,
      try selling the last active piece (must refuse). Print `SMOKE_SHOP_OK` on success; wire
      into `run_all.sh` via `check_script()` expecting that substring. `return false` in
      `_process`!

## Phase 4 — Temp sprites

Needed (both are TEMP placeholders):
- `Assets/Sprites/shop.png` — map node icon. Match existing map icons' feel/size (they're small
  PNGs scaled 3x by `map_node_icon.gd`; look at `item.png` for reference).
- `Assets/Sprites/item_extra_move.png` — battle-bar + shop icon for the extra_move item
  (path convention `item_<id>.png` comes from `BaseItem.icon_texture()`).

How: simplest reliable route is a tiny headless GDScript (`Image.create` → fill/draw → 
`save_png`) run once with `godot4 --headless --script`, or ImageMagick if available. Distinct
solid-color + letter ("S" / "+1") is plenty. **Whatever you generate, append a row to
`TEMP_SPRITES.md`** (already in repo root) with path, what it should eventually depict, and how
it was generated. Then rerun the import (`godot4 --headless --import --path team-berry-game`)
so `.import` files exist; commit the pngs (+ generated `.import` files, as the repo already
tracks those for other sprites — check `git status`).

- [x] both pngs + TEMP_SPRITES.md rows + import files committed

## Phase 5 — Battle item bar (vertical `<`/`>` drawer + drag-to-use)

All in `battle_ui.tscn` / `battle_ui.gd`.

**Scene:** between `Root/BoardArea` and `Root/SidePanel` add a right-anchored horizontal strip
sitting flush against SidePanel's left edge: an `HBoxContainer` (call it `ItemDrawer`) containing:
- `ItemPanel` (PanelContainer, initially `visible = false`) with a `VBoxContainer` of item rows —
  built in code: one `TextureRect` (item icon, from `BaseItem.icon_texture()`) + `Label` `xN`
  per owned item id. Empty inventory → a small "NO ITEMS" label.
- `ToggleButton` (Button, text `<`, slim: custom_minimum_size ~`(24, 120)`) — the vertical bar.

Behaviour: `<` opens (`ItemPanel.visible = true`, button text becomes `>`), `>` closes. Rebuild
rows on `PlayerManager.items_changed` (connect in `_ready()` next to the existing connects) and
on open. Don't touch SidePanel's layout — the drawer floats over/next to the board like the HUD
already does (BoardArea is just a click-catcher Control).

**Drag-to-use:** mirror the piece-drag trio (`_begin_drag` l.353 / `_input` l.380 /
`_resolve_drop` l.392), with parallel state so item-drag and piece-drag can't interleave:

```gdscript
var dragging_item: bool = false
var drag_item_id: String = ""
```

- Item row `gui_input`: on left-press during the battle phase (NOT placement — check
  `battle_controller.current_state == battle_controller.BattleState.PLAYER_TURN`), set state,
  reuse `%DragGhost` with the item texture.
- Extend `_input()`: if `dragging_item`, move ghost; on release call `_resolve_item_drop(pos)`.
- `_resolve_item_drop(screen_pos)`: hide ghost; if the drop is over the board
  (`_screen_to_grid()` — any cell is fine for extra_move; validity is the item's business):

```gdscript
var item := ItemData.create_item(drag_item_id)
if item.can_use(battle_controller, grid_pos) and item.apply(battle_controller, grid_pos):
	player_manager.remove_item(drag_item_id)   # emits items_changed -> row rebuild
	UiAudio.play_click()
```

  Dropped back on the panel / not applied → nothing consumed, no-op.
- During placement phase, hide or disable the drawer (`_on_battle_state_changed` l.139 already
  branches on state — hide there, show when `PLAYER_TURN` starts).

Result with extra_move: `MOVES 0/1` → drag the item anywhere on the board → `MOVES 1/1`
(the existing `_on_moves_changed` label handler updates it, incl. the >max case like `2/1`).

### Phase 5 checklist
- [x] drawer scene nodes + toggle + row rebuild on items_changed
- [x] drag-to-use wired, placement phase excluded, item consumed exactly once
- [x] Smoke test `tests/smoke/smoke_item_use.gd`: load battle like `smoke_battle.gd`, place
      pieces / reach PLAYER_TURN, grant `extra_move` via PlayerManager, record `moves_remaining`,
      call the same code path the drop uses (factor the consume logic into a testable
      `battle_ui.use_item(id, grid_pos) -> bool` that `_resolve_item_drop` calls!), assert
      `moves_remaining` incremented and count decremented, print `SMOKE_ITEM_USE_OK`; add to
      `run_all.sh` with that expected substring.

## Phase 6 — Wrap up

- [x] Full `./tests/run_all.sh` green; also boot the real game once headlessly:
      map 1 has no shop, so at minimum `--scene res://Scenes/Map/map.tscn --quit-after 5` and
      `--scene res://Scenes/Map/shop.tscn --quit-after 5` load with zero ERROR lines.
- [x] Update `CHANGELOG.md` (repo keeps one) with a short entry.
- [x] Confirm `TEMP_SPRITES.md` lists every generated asset.
- [x] Commits: small, per-phase, message style matches `git log` (imperative, English), each
      ending with the Claude co-author line already used in this repo. Do NOT merge to develop;
      leave the branch for review.

## Explicitly out of scope (don't build)
- More items beyond `extra_move` (pipeline proof only).
- Revive/persistent-death interactions, shop restocking, dynamic stock/pricing.
- Real art (placeholders only, tracked in TEMP_SPRITES.md).
- Renaming `upgrade_items` or unifying it with a "gold" concept.

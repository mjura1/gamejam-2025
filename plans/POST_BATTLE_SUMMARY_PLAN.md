# POST-BATTLE SUMMARY PLAN — VICTORY / DEFEAT overlay screens

Status: NOT STARTED. Work on branch `features/post-battle-summary` off `develop` (create
it first). Commit per milestone. Do NOT merge into develop — Miha merges himself (repo
policy: always `git merge --no-ff`, never fast-forward).

All file paths are relative to `team-berry-game/` unless stated otherwise. Line numbers
are as of `develop @ 67d9909`.

**The code exploration below is already done and verified (three parallel Explore agents
+ direct file reads + a Plan-agent design pass, all cross-checked against the real files —
not hallucinated). Do NOT re-explore the codebase or re-read these files "just to check" —
jump straight to section 4 (Milestones) and use section 2 as the reference.** If something
below turns out to be stale (file moved, line numbers drifted), fix it locally and note the
deviation in section 6 — don't redo the whole survey.

---

## 1. What Miha wants

Playtest with a brand-new player surfaced that the game is confusing with zero end-of-battle
feedback: winning silently drops you back on the map, losing silently dumps you at the main
menu, with no explanation of what happened. Fix: add VICTORY and DEFEAT summary overlays,
shown the instant a battle ends, before today's automatic scene transition. Reuses the pause
menu's visual pattern (semi-transparent blurred overlay).

From his hand-drawn mockup + description:

**VICTORY screen**
- "SUMMARY" section: two rows, "enemy" party and "mine" (player) party, each a row of piece
  icons.
- Pieces already owned before this battle are grayed out. A piece newly added to either
  party *this battle* (new recruit or new enemy) is shown fully colored, slightly
  highlighted, with a "+" badge.
- "REWARDS" section below: items gained this battle. Today that's only upgrade items
  (`x3` in the mockup); the mockup also shows "artifact 1 x1" as an example of a *future*
  reward type — artifacts are NOT implemented anywhere in this codebase (confirmed via a
  repo-wide grep, zero hits) and must NOT be faked or stubbed with placeholder data. Build
  the rewards list as a generic, data-driven list of `{label, amount}` rows so a future
  artifact reward is just another row, not a redesign.
- "CONTINUE" button → does whatever the existing post-victory logic already does: return to
  the map, advance to a harder tier, or (confirmed with Miha) end the run to the main menu
  if this was the final boss of the last tier in classic mode. **The summary shows in ALL of
  these cases** — no special-casing "is this a run-ending win" to skip the screen.

**DEFEAT screen**
- "Final Floor: N" and "Final Room: N". **Terminology gotcha**: Miha's "Floor" = the whole
  map/tier (code: `PlayerManager.current_map_tier`, 0-based, classic mode has tiers 0/1/2,
  infinite mode goes higher). Miha's "Room" = depth within that map (code:
  `PlayerManager.current_map_floor`, confusingly named — it's room depth, NOT tier). Do not
  swap these.
- "BACK" button → ends the run and lands directly on the already-implemented game-mode-select
  overlay, skipping the bare main-menu title screen entirely.

**Confirmed with Miha (AskUserQuestion, both recommended defaults accepted):**
1. Victory summary shows on every win, including a run-ending final-boss win — Continue just
   re-triggers whatever the existing logic would already do.
2. Rewards section is a generic reward-row list, not a hardcoded single upgrade-items line.

---

## 2. Verified code map (exploration already done — do not re-derive)

### 2.1 Battle end detection — `Scripts/TileMap/BattleController.gd:549-580`

```gdscript
func check_battle_end() -> bool:
	if not is_instance_valid(player_manager):
		return false

	if player_manager.enemyGone():
		_set_state(BattleState.GAME_OVER)
		if player_manager.is_boss_floor:
			player_manager.add_upgrade_items(player_manager.UPGRADE_ITEMS_PER_BOSS_WIN)
			GF.call_deferred("advance_map_tier")
		else:
			player_manager.add_upgrade_items(player_manager.UPGRADE_ITEMS_PER_WIN)
			GF.call_deferred("return_to_map")
		_maybe_pay_courier_reward()
		return true

	if player_manager.activeGone():
		_set_state(BattleState.GAME_OVER)
		if player_manager.remove_item("divine_intervention"):
			GF.call_deferred("return_to_map_after_escape")
			return true
		player_manager.reset_floor_number()
		GF.call_deferred("game_over")
		return true

	return false
```
Called after every resolved action (multiple call sites in `BattleController.gd` and
`battle_ui.gd`) — may run many times per battle, only the first `true`-returning call
matters. `_set_state(BattleState.GAME_OVER)` already blocks further board input, so the
battle scene safely sits idle while an overlay is shown — no extra input-blocking needed.

`_maybe_pay_courier_reward()` (`BattleController.gd:396-399`) conditionally calls
`player_manager.add_upgrade_items(ItemData.get_reward("courier_package"))` too — i.e. a
second, conditional source of `upgrade_items` on top of the win/boss-win constant. This is
why the reward amount for the summary must be captured as a before/after delta, not a
hardcoded constant.

**Defeat gotcha, verified**: `reset_floor_number()` runs **synchronously** and zeroes
`current_map_floor` *before* the deferred call fires. `current_map_tier` gets reset to 0
later too, inside `_end_run()` (called from `game_over()`, itself deferred). So the final
tier/floor numbers MUST be captured into locals before `reset_floor_number()` runs, or the
defeat screen will always show 0/0.

### 2.2 GameFlow autoload — `Scripts/Map/GameFlow.gd` (full file already read)

Relevant consts/vars (lines 9-22):
```gdscript
const MAP_SCENE = preload("res://Scenes/Map/map.tscn")
const BATTLE_SCENE = preload("res://Scenes/Map/battle.tscn")
const CAMPFIRE_SCENE = preload("res://Scenes/Map/campfire.tscn")
const SHOP_SCENE = preload("res://Scenes/Map/shop.tscn")
const MAIN_MENU_SCENE = preload("res://Scenes/Menu/main_menu.tscn")
const PAUSE_MENU_SCENE = preload("res://Scenes/Menu/pause_menu.tscn")
const TUTORIAL_HUB_SCENE = preload("res://Scenes/Menu/tutorial_hub_menu.tscn")

var game_initialized: bool = false
var current_map_instance: Node = null
var pause_menu_instance: Control = null
var pause_menu_layer: CanvasLayer = null
var floor_counter_layer: CanvasLayer = null
var floor_counter_label: Label = null
```

`_ready()` (lines 28-44) — **the CanvasLayer-on-root pattern to copy**:
```gdscript
func _ready():
	# CanvasLayer wrapper is required here: the map/battle scene's active
	# Camera2D transforms the whole viewport's 2D canvas, so a Control added
	# as a plain sibling would pan/zoom along with gameplay instead of
	# staying screen-locked. CanvasLayer content ignores that transform.
	pause_menu_instance = PAUSE_MENU_SCENE.instantiate()
	pause_menu_layer = CanvasLayer.new()
	pause_menu_layer.name = "PauseMenuLayer"
	pause_menu_layer.layer = 10
	pause_menu_layer.add_child(pause_menu_instance)
	get_tree().root.call_deferred("add_child", pause_menu_layer)
	_setup_floor_counter()
```
`_setup_floor_counter()` (lines 52-92) is a second example of the same pattern, built via
code instead of a `.tscn` (`floor_counter_layer.layer = 9`) — useful reference for building
simple UI without a scene file, though we'll use a `.tscn` for the summary (richer layout).

Existing transition functions (**do not duplicate their logic — reuse them as-is**):
- `return_to_map()` (line 184) — victory, non-boss floor.
- `advance_map_tier()` (lines 157-177) — victory, boss floor. Already correctly handles:
  incrementing the tier, ending the run to `MAIN_MENU_SCENE` if
  `current_map_tier >= 3 and game_mode != "infinite"`, otherwise generating a new harder map
  and resetting `enemy_party` to `default_enemies`. **This already does the right thing for
  the "final boss of last tier" case Miha confirmed should still show a summary** — Continue
  just needs to call this function, no new branching required.
- `game_over()` (lines 231-234) — defeat. Currently:
  ```gdscript
  func game_over():
      print("GF: Player lost. Returning to Main Menu.")
      _end_run()
      _change_scene_instance(MAIN_MENU_SCENE.instantiate())
  ```
- `_end_run()` (lines 247-255) — resets `game_initialized`, `current_map_tier`, unpauses,
  frees `current_map_instance` if detached.
- `return_to_main_menu()` (lines 239-242) — used by pause menu's "Main Menu" button, separate
  from `game_over()` (both end up calling `_end_run()` + main menu, kept as two functions so
  their call sites stay distinguishable). Not touched by this plan.
- `_change_scene_instance()` (lines 203-229) — generic scene swap helper; also toggles
  `floor_counter_layer.visible` based on whether the new scene is the map. Not touched.

### 2.3 Pause menu visual pattern — `Scenes/Menu/pause_menu.tscn` + `Scripts/pause_menu.gd`

Scene tree:
```
PauseMenu (Control, process_mode=ALWAYS, full-rect anchors)
├─ ColorRect          # translucent bg (0.21,0.21,0.21,0.784) + ShaderMaterial blur
├─ VBoxContainer      # centered, separation=50, holds buttons
├─ Label "PAUSE"      # BLKCHCRY.TTF, size 130, shadow
└─ AnimationPlayer    # "blur" anim, animates ColorRect shader lod 0→0.9 over 0.3s
```
Blur shader: `Scenes/pause_menu.gdshader` (reusable `ext_resource`, reuse it verbatim for the
summary's backdrop). Button `StyleBoxFlat` resources (inline in the `.tscn`, reusable):
rounded (16px corner radius), drop shadow (size 5, offset (0,3.41)); `normal` bg
`(11.7,11.7,11.7,1)`, `hover` bg `(0.6,0.6,0.6,0.78)`, font size 30, black/white text per
state. `pause()`/`resume()` in `pause_menu.gd` just call `show()`/`hide()` and toggle
`get_tree().paused` — **not relevant to us**, the summary overlay should NOT pause the tree
(battle state already blocks input via `BattleState.GAME_OVER`; pausing would also freeze
the summary's own UI process if not careful about `process_mode`).

There's an unused, unscripted stub `Scenes/Menu/GameOver.tscn` (bare `Control`+`Panel`, no
children of substance, not wired anywhere). **Leave it alone** — not worth adapting, a future
cleanup pass can delete it.

### 2.4 Piece icon component — `Scripts/Battle/piece_icon.gd`

```gdscript
class_name PieceIcon
extends TextureRect

signal icon_clicked(icon)

var piece_name: String = ""
var character: BaseCharacter = null
var is_dead: bool = false
var is_benched: bool = false
var is_highlighted: bool = false
var is_placed: bool = false
var slot_label: Label   # small corner badge, currently used for keybind hints

const COLOR_NORMAL := Color(1, 1, 1)
const COLOR_DEAD := Color(0.35, 0.35, 0.35)
const COLOR_BENCHED := Color(0.6, 0.6, 0.6)
const COLOR_HIGHLIGHTED := Color(1, 1, 0.4)
const COLOR_PLACED := Color(0.75, 0.75, 0.75)

func setup(p_piece_name: String, p_character: BaseCharacter):
	piece_name = p_piece_name
	character = p_character
	texture = load("res://Assets/Sprites/%s.png" % piece_name)
	_update_modulate()

func set_dead(dead: bool): ...
func set_benched(benched: bool): ...
func set_highlighted(highlighted: bool): ...
func set_placed(placed: bool): ...
func set_slot_label(text: String):
	slot_label.text = text
	slot_label.visible = text != ""
```
Sized 40x40, `EXPAND_IGNORE_SIZE`/`STRETCH_KEEP_ASPECT_CENTERED`. `setup(piece_name,
character)` accepts `character = null` fine (only used for click interactions later, which
the summary doesn't need — leave `icon_clicked` unconnected). **Reuse this class directly**
for both party rows:
- "already had" piece → `icon.setup(name, null)` then `icon.set_benched(true)` (0.6 gray).
- "new this battle" piece → `icon.set_highlighted(true)` (yellow tint) +
  `icon.set_slot_label("+")` (repurposing the existing corner-badge mechanism from keybind
  hints to a "+" glyph).

This is the same class already used to render `roster_row`/`active_row` in
`Scripts/Battle/battle_ui.gd` — precedent confirms it's meant to be reused this way.

### 2.5 Reward display convention — `Scripts/Battle/battle_ui.gd:1103-1105`

```gdscript
func _update_item_counts():
	upgrade_count_label.text = "x%d" % player_manager.upgrade_items
	revive_count_label.text = "x%d" % player_manager.revive_items
```
`"x%d"` next to a label is the existing convention — reuse it for reward rows.

### 2.6 Party/roster data model — `Scripts/Player/PlayerManager.gd` (full file already read)

```gdscript
var default_friends: Array[String] = ["friendly_pawn", "friendly_pawn", "friendly_pawn"]
var default_enemies: Array[String] = ["enemy_pawn", "enemy_pawn", "enemy_pawn"]
var friendly_party: Array[String]   # persistent roster, plain type-name strings
var enemy_party: Array[String]      # persistent roster, GROWS every battle within a tier
var reserve_party: Array[String]
var active_enemies: Array[String]   # battle-scoped copy (resetActives())
var active_party: Array[String]     # battle-scoped copy (resetActives())
var dead_party: Array[String]       # battle-scoped only - death is NOT persistent yet

var upgrade_items: int = 0
var revive_items: int = 0
var owned_items: Dictionary = {}    # shop inventory, id -> count, NOT battle rewards

const UPGRADE_ITEMS_PER_WIN := 1
const UPGRADE_ITEMS_PER_BOSS_WIN := 3
const UPGRADE_ITEMS_PER_ITEM_ROOM := 2

var max_party_size = 10
var current_map_floor: int = 0   # room depth within tier, 0-14, "Room" in Miha's vocabulary
var current_map_tier: int = 0    # "Floor" in Miha's vocabulary, 0-based
var game_mode: String = "classic"  # or "infinite"
var is_boss_floor: bool = false
var is_mini_boss_floor: bool = false
```
Key functions:
- `add_to_friendly_party(character)` (lines 89-96) — appends to `friendly_party` if under
  `max_party_size`, else overflows into `reserve_party` (currently `void` return).
- `add_to_enemy_party(character)` (lines 283-287) — always appends to `enemy_party`, no cap,
  comment confirms it's intentional that the enemy army grows across a whole tier and only
  resets on `advance_map_tier()` (`GameFlow.gd:176`).
- `resetActives()` (line 289) — `active_enemies = enemy_party.duplicate()`,
  `active_party = friendly_party.duplicate()`, clears `dead_party`. Called by
  `GF.start_event()` right before a battle scene starts, i.e. **after** `_handle_event()` has
  already appended any new piece — confirms the new piece is indistinguishable from old ones
  by the time the battle exists, so "new" must be tracked at the append point, not derived
  later by diffing.
- `enemyGone()`/`activeGone()` (lines 383-393) — trivial emptiness checks on
  `active_enemies`/`active_party`.
- `set_current_floor(new_floor)` / `reset_floor_number()` (lines 375-381) — only-increases
  setter + the reset that must be captured-around (§2.1).
- Death: `register_dead_character()` (lines 224-238) removes from `active_party` (battle-
  scoped) and appends to `dead_party` (also battle-scoped) — **`friendly_party` (the
  persistent roster) is never touched by death**. So between battles, every entry in
  `friendly_party` is considered "alive" for display purposes; the summary does NOT need a
  third "died this battle" visual state — that's out of scope, matches the literal
  requirement (only "already had" vs "new" states were asked for).

No existing "new piece added this battle" tracking exists anywhere — confirmed via
targeted search, this must be built from scratch (§2.7 shows exactly where).

### 2.7 Where new pieces get added — `Scripts/Map/MapController.gd:334-373`

```gdscript
func _on_room_selected(room_data: Room):
	previous_room = current_room
	var new_floor = room_data.grid_position.x
	if PlayerManager:
		PlayerManager.set_current_floor(new_floor)
	_on_button_pressed()
	_handle_event(room_data)
	_update_reachable_rooms(room_data)
	queue_redraw()

func _handle_event(room_data: Room):
	var room_name = Room.RoomTypeNames.get(room_data.type, "unknown_event")
	PlayerManager.is_boss_floor = room_data.grid_position.x == generator.FLOORS - 1
	PlayerManager.is_mini_boss_floor = generator.mini_boss_floor != -1 and room_data.grid_position.x == generator.mini_boss_floor

	if room_name.begins_with("enemy_"):
		PlayerManager.add_to_enemy_party(room_name)
	elif room_name.begins_with("friendly_"):
		PlayerManager.add_to_friendly_party(room_name)
	elif room_name == "item":
		PlayerManager.add_upgrade_items(PlayerManager.UPGRADE_ITEMS_PER_ITEM_ROOM)
	# campfire/shop: no party mutation, GF.start_event() just changes scene.

	PlayerManager.addSnow()
	GF.start_event(room_data.type)
```
`Room.RoomType` enum (`Scripts/Map/map_point.gd:16-32`) confirms `enemy_bishop/king/knight/
rook/queen/pawn` and `friendly_pawn/knight/rook/bishop/queen/king` are **separate, mutually
exclusive** room types alongside `campfire/item/shop` — so `_handle_event()` appends to AT
MOST ONE of `friendly_party`/`enemy_party` per room selection, never both. This is the single
insertion point where "this piece is new" must be recorded.

`GF.start_event(room_type)` (`GameFlow.gd:135-153`): routes `campfire`/`shop` to their own
scenes, `item` does nothing scene-wise (reward already applied), and **everything else**
(i.e. every `enemy_*`/`friendly_*` room type) falls through to
`PlayerManager.resetActives()` + battle scene — confirms recruiting a friendly piece ALSO
triggers a battle (against whatever `enemy_party` has accumulated so far), it's not a
battle-free recruitment event.

### 2.8 Mode-select overlay — NOT a separate scene

`Scripts/Menu/mode_select_menu.gd` + `.tscn` is instanced as a **child overlay of the main
menu**, same pattern as `settings_menu`. Entry point,
`Scripts/main_menu.gd` (full file already read):
```gdscript
extends Control
const SETTINGS_MENU_SCENE = preload("res://Scenes/Menu/settings_menu.tscn")
const MODE_SELECT_SCENE = preload("res://Scenes/Menu/mode_select_menu.tscn")
var _settings_instance: Control = null
var _mode_select_instance: Control = null

func _on_play_pressed():
	if is_instance_valid(_mode_select_instance):
		return
	_mode_select_instance = MODE_SELECT_SCENE.instantiate()
	_mode_select_instance.back_pressed.connect(_on_mode_select_back)
	add_child(_mode_select_instance)
	$VBoxContainer.hide()
	$Title.hide()

func _on_mode_select_back():
	if is_instance_valid(_mode_select_instance):
		_mode_select_instance.queue_free()
	_mode_select_instance = null
	$VBoxContainer.show()
	$Title.show()
```
`_on_play_pressed()` only touches direct children (`$VBoxContainer`, `$Title`), so it's safe
to call on a freshly-`instantiate()`d main menu even before it's added to the tree. There is
currently NO way to land a fresh main-menu instance directly on mode-select — needs one small
addition (§4, M3).

`mode_select_menu.gd`'s `_on_classic_pressed()`/`_on_infinite_pressed()` call
`PlayerManager.setStarting(mode)` then `GF.start_new_game()` — unrelated to this plan, just
confirms this overlay is indeed "the screen where you select which game mode you'll play"
Miha referred to.

---

## 3. Design decisions (confirmed / defaults — implement as written, flag deviations in §6)

1. **One scene, two content states**, not two separate scenes: `Scenes/Menu/
   post_battle_summary.tscn` + `Scripts/Menu/post_battle_summary.gd`, placed alongside
   `mode_select_menu`/`settings_menu` (closer precedent for a self-contained overlay than
   `pause_menu`). Victory/defeat share backdrop, panel, title label; only body content and
   buttons differ, toggled by which `setup_*()` was called.
2. Public API:
   ```gdscript
   signal continue_pressed
   signal back_pressed
   func setup_victory(friendly_party: Array[String], enemy_party: Array[String],
           new_friendly_piece: String, new_enemy_piece: String, upgrade_items_gained: int) -> void
   func setup_defeat(final_tier: int, final_floor: int) -> void
   ```
   The scene never calls `GF` itself — dumb view, GameFlow owns transition logic. Buttons
   just emit signals (mirrors `mode_select_menu.gd`'s `back_pressed` pattern), plus
   `UiAudio.play_click()` on press (existing convention in every menu script here).
3. **CanvasLayer layer number: 11** — one above `pause_menu_layer` (10), so if Escape somehow
   fires while the summary is up, the summary still wins the stacking order and stays the
   only clickable modal. Do NOT set `get_tree().paused = true` for this overlay (unlike pause
   menu) — battle input is already blocked via `BattleState.GAME_OVER`, and pausing would
   complicate the overlay's own button input needing `PROCESS_MODE_ALWAYS` plumbing for no
   benefit.
4. **New-piece tracking**: two `PlayerManager` fields, `new_friendly_piece: String = ""` and
   `new_enemy_piece: String = ""`, single-value (not arrays) because at most one piece is
   ever added per battle (§2.7). Cleared at the TOP of `MapController._handle_event()` (before
   the room-type branch) so a stale value from a previous room never leaks into the next
   battle's summary. Set only when the piece actually lands in the *active* roster — see next
   point.
5. **`add_to_friendly_party()` return-value change**: `void → bool`, `true` if the piece
   joined `friendly_party` (i.e. will actually be in this battle), `false` if it overflowed
   into `reserve_party` (in which case `new_friendly_piece` must NOT be set — a benched piece
   isn't "new to this battle's party" in any visible sense). `add_to_enemy_party()` has no cap
   and stays `void`. GDScript allows discarding a changed return value, so
   `tests/unit/test_player_manager.gd`'s existing calls (which don't capture the result) keep
   compiling and passing unchanged.
6. **Reward delta**: computed as a before/after snapshot of `player_manager.upgrade_items`
   around the existing award calls in `check_battle_end()`'s victory branch (spans both the
   win/boss-win constant AND the conditional courier bonus) — NOT a new persistent
   PlayerManager field, since nothing else needs this delta as state.
7. **Continue/Back re-dispatch to existing functions, no duplicated transition logic**:
   Continue calls `advance_map_tier()` (boss floor) or `return_to_map()` (else) — both
   unmodified, both already handle every edge case including the classic-mode run-ending
   final-boss win. Back calls (a lightly modified) `game_over()` then opens mode-select on
   the resulting menu instance.
8. **`game_over()` signature change**: `void → Control`, returning the instantiated main-menu
   node, so the defeat handler can chain `new_menu.call_deferred("open_mode_select")` without
   re-implementing `_end_run()` + scene-swap. Backward compatible — no other caller uses the
   return value today (only call site is `BattleController.gd:577`, which is itself being
   changed in this plan).
9. **Party row rendering**: `PieceIcon.setup(roster_name, null)` for every entry in
   `friendly_party`/`enemy_party` (full duplicated arrays passed in at victory-detection time,
   `.duplicate()`d defensively even though nothing mutates them before Continue is clicked).
   Match against `new_friendly_piece`/`new_enemy_piece` with a "claimed" guard so only ONE
   icon ever gets the highlight+badge even if the roster contains duplicate type-name entries
   matching the new piece's name.
10. **Defeat label formatting**: `"Final Floor: %d" % (final_tier + 1)` (1-indexed, matches
    `GameFlow._update_floor_counter()`'s existing `current_map_tier + 1` convention) but
    `"Final Room: %d" % final_floor` (raw, 0-based — deliberately asymmetric, matches the
    literal mockup values and the plain variable value; don't "fix" this into symmetry).

---

## 4. Milestones

Log a one-line `./tests/run_all.sh` result in section 6 after EVERY milestone (repo
convention — other agents/sessions read it instead of re-running the whole suite).

### M0 — Baseline
- `git checkout develop && git checkout -b features/post-battle-summary`
- Run `./tests/run_all.sh` from `team-berry-game/` (godot binary: `godot4`, installed at
  `~/.local/bin/godot4`, or set `GODOT_BIN`). Record baseline in §6, including any
  PRE-EXISTING failures (there is at least one known one, see §5). Only deltas against this
  baseline matter later.

### M1 — New-piece tracking plumbing (PlayerManager + MapController)
1. `PlayerManager.gd`: add `new_friendly_piece: String = ""` / `new_enemy_piece: String = ""`
   near `is_boss_floor` (~line 79). Change `add_to_friendly_party()` to return `bool` per
   §3.5 (keep the existing print statements). `add_to_enemy_party()` unchanged (`void`).
2. `MapController.gd` `_handle_event()` (line 353): clear both new-piece fields at the top,
   then set `new_enemy_piece = room_name` after `add_to_enemy_party()`, and
   `new_friendly_piece = room_name` only if `add_to_friendly_party()` returned `true` — see
   §2.7/§3.4-5 for exact placement.
3. Tests: extend `tests/unit/test_player_manager.gd` with cases for the new return value
   (`add_to_friendly_party` returns true when under cap, false when overflowing to reserve)
   and, if there's a MapController unit-test file, a case for `new_friendly_piece`/
   `new_enemy_piece` being set/cleared correctly (check `tests/unit/` for an existing
   MapController test file first — if none exists, a smoke-level check in M4's new test is
   sufficient, don't create a new unit-test file just for this).

### M2 — `post_battle_summary.tscn` + `post_battle_summary.gd` (visual scene)
1. Build the scene per §2.3 (backdrop) + §3.1-2 (structure/API). Suggested node names (use
   `%UniqueName` scene-unique lookups throughout, matching `battle_ui.tscn`'s convention):
   `%TitleLabel`, `%VictoryContent`, `%EnemyRow` / `%MineRow` (each an `HFlowContainer`
   inside a `ScrollContainer` — `enemy_party` can grow to ~15 entries by the end of a tier),
   `%RewardsList` (empty `VBoxContainer`, populated at runtime), `%ContinueButton`,
   `%DefeatContent`, `%FinalFloorLabel`, `%FinalRoomLabel`, `%BackButton`.
2. `post_battle_summary.gd`:
   ```gdscript
   extends Control
   class_name PostBattleSummary
   signal continue_pressed
   signal back_pressed

   func _ready():
       %ContinueButton.pressed.connect(func(): UiAudio.play_click(); continue_pressed.emit())
       %BackButton.pressed.connect(func(): UiAudio.play_click(); back_pressed.emit())

   func setup_victory(friendly_party, enemy_party, new_friendly_piece, new_enemy_piece, upgrade_items_gained):
       %TitleLabel.text = "VICTORY"
       %VictoryContent.visible = true
       %DefeatContent.visible = false
       _populate_party_row(%MineRow, friendly_party, new_friendly_piece)
       _populate_party_row(%EnemyRow, enemy_party, new_enemy_piece)
       _populate_rewards(upgrade_items_gained)

   func setup_defeat(final_tier: int, final_floor: int):
       %TitleLabel.text = "DEFEAT"
       %VictoryContent.visible = false
       %DefeatContent.visible = true
       %FinalFloorLabel.text = "Final Floor: %d" % (final_tier + 1)
       %FinalRoomLabel.text = "Final Room: %d" % final_floor

   func _populate_party_row(row: Container, roster: Array, new_piece_name: String):
       for child in row.get_children():
           child.queue_free()
       var claimed := false
       for roster_name in roster:
           var icon := PieceIcon.new()
           icon.setup(roster_name, null)
           if not claimed and new_piece_name != "" and roster_name == new_piece_name:
               icon.set_highlighted(true)
               icon.set_slot_label("+")
               claimed = true
           else:
               icon.set_benched(true)
           row.add_child(icon)

   func _populate_rewards(upgrade_items_gained: int):
       for child in %RewardsList.get_children():
           child.queue_free()
       if upgrade_items_gained > 0:
           %RewardsList.add_child(_build_reward_row("UPGRADE ITEMS", upgrade_items_gained))

   func _build_reward_row(label_text: String, amount: int) -> Control:
       var row := HBoxContainer.new()
       var label := Label.new(); label.text = label_text; row.add_child(label)
       var amount_label := Label.new(); amount_label.text = "x%d" % amount; row.add_child(amount_label)
       return row
   ```
3. No `GF`/`PlayerManager` references inside this script at all — purely a view, per §3.2.
4. Manual check (windowed, not headless): instance the scene standalone in the editor,
   call `setup_victory()`/`setup_defeat()` from a temporary debug call to sanity-check
   layout before wiring it into GameFlow in M3.

### M3 — Wire it up: BattleController + GameFlow + main_menu
1. `main_menu.gd`: add
   ```gdscript
   func open_mode_select() -> void:
       _on_play_pressed()
   ```
2. `GameFlow.gd`:
   - Add `const POST_BATTLE_SUMMARY_SCENE = preload("res://Scenes/Menu/post_battle_summary.tscn")`
     and `var post_battle_summary_layer: CanvasLayer = null` near the other consts/vars.
   - Change `game_over()` to return the menu instance (§3.8):
     ```gdscript
     func game_over() -> Control:
         print("GF: Player lost. Returning to Main Menu.")
         _end_run()
         var new_menu := MAIN_MENU_SCENE.instantiate()
         _change_scene_instance(new_menu)
         return new_menu
     ```
   - Add (placed near `return_to_map()`, new section "3b. POST-BATTLE SUMMARY"):
     ```gdscript
     func show_victory_summary(friendly_party: Array[String], enemy_party: Array[String],
             new_friendly_piece: String, new_enemy_piece: String,
             upgrade_items_gained: int, is_boss_floor: bool) -> void:
         var summary_instance := POST_BATTLE_SUMMARY_SCENE.instantiate()
         var summary_layer := CanvasLayer.new()
         summary_layer.name = "PostBattleSummaryLayer"
         summary_layer.layer = 11
         summary_layer.add_child(summary_instance)
         post_battle_summary_layer = summary_layer
         get_tree().root.call_deferred("add_child", summary_layer)
         summary_instance.setup_victory(friendly_party, enemy_party, new_friendly_piece, new_enemy_piece, upgrade_items_gained)
         summary_instance.continue_pressed.connect(_on_victory_continue_pressed.bind(summary_layer, is_boss_floor))

     func _on_victory_continue_pressed(summary_layer: CanvasLayer, is_boss_floor: bool) -> void:
         summary_layer.queue_free()
         post_battle_summary_layer = null
         if is_boss_floor:
             advance_map_tier()
         else:
             return_to_map()

     func show_defeat_summary(final_tier: int, final_floor: int) -> void:
         var summary_instance := POST_BATTLE_SUMMARY_SCENE.instantiate()
         var summary_layer := CanvasLayer.new()
         summary_layer.name = "PostBattleSummaryLayer"
         summary_layer.layer = 11
         summary_layer.add_child(summary_instance)
         post_battle_summary_layer = summary_layer
         get_tree().root.call_deferred("add_child", summary_layer)
         summary_instance.setup_defeat(final_tier, final_floor)
         summary_instance.back_pressed.connect(_on_defeat_back_pressed.bind(summary_layer))

     func _on_defeat_back_pressed(summary_layer: CanvasLayer) -> void:
         summary_layer.queue_free()
         post_battle_summary_layer = null
         var new_menu := game_over()
         new_menu.call_deferred("open_mode_select")
     ```
   - Deferred-call ordering note (verified safe): `_change_scene_instance()` itself does
     `get_tree().root.call_deferred("add_child", new_instance)`; `new_menu.call_deferred(
     "open_mode_select")` is queued strictly after that (it runs after `game_over()`
     returns), so Godot's FIFO deferred-call queue guarantees the menu is in the tree before
     `open_mode_select()` fires, same frame.
3. `BattleController.gd` `check_battle_end()` (§2.1) — replace the two
   `GF.call_deferred("return_to_map"/"advance_map_tier")`/`GF.call_deferred("game_over")`
   calls:
   ```gdscript
   if player_manager.enemyGone():
       _set_state(BattleState.GAME_OVER)
       var was_boss_floor: bool = player_manager.is_boss_floor
       var upgrade_items_before: int = player_manager.upgrade_items
       if was_boss_floor:
           player_manager.add_upgrade_items(player_manager.UPGRADE_ITEMS_PER_BOSS_WIN)
       else:
           player_manager.add_upgrade_items(player_manager.UPGRADE_ITEMS_PER_WIN)
       _maybe_pay_courier_reward()
       var upgrade_items_gained: int = player_manager.upgrade_items - upgrade_items_before

       GF.call_deferred("show_victory_summary",
           player_manager.friendly_party.duplicate(), player_manager.enemy_party.duplicate(),
           player_manager.new_friendly_piece, player_manager.new_enemy_piece,
           upgrade_items_gained, was_boss_floor)
       return true

   if player_manager.activeGone():
       _set_state(BattleState.GAME_OVER)
       if player_manager.remove_item("divine_intervention"):
           print("DIVINE_INTERVENTION: rešeni pred porazom")
           GF.call_deferred("return_to_map_after_escape")
           return true
       var final_tier: int = player_manager.current_map_tier
       var final_floor: int = player_manager.current_map_floor
       player_manager.reset_floor_number()
       GF.call_deferred("show_defeat_summary", final_tier, final_floor)
       return true
   ```
   The `divine_intervention` rescue branch is untouched — no summary on a rescue.

### M4 — Test updates
1. Update these three smoke tests to insert a "wait for the summary overlay, then drive its
   signal directly" step (same "drive handlers directly" philosophy already used in
   `tests/smoke/smoke_mode_select.gd` — see its `_on_play_pressed()`/`_on_mode_select_back()`
   direct-call pattern, verified/read in full during planning) before their existing
   post-transition assertions:
   - `tests/smoke/smoke_battle_end.gd` — after `battle_controller.check_battle_end()`
     (line 56), poll for `root.get_node_or_null("PostBattleSummaryLayer")`, then call
     `.get_child(0).continue_pressed.emit()` on it, THEN let the existing "Battle scene left
     the tree" check proceed.
   - `tests/smoke/smoke_battle_loss.gd` — same pattern with `.back_pressed.emit()`, inserted
     before its existing "old map instance was freed" leak check (that check depends on
     `_end_run()` having run, which now only happens after Back is emitted).
   - `tests/smoke/smoke_courier_package.gd` — same `continue_pressed.emit()` step before its
     `battle_instance == null` polling loop; optionally also assert the summary's
     `upgrade_items_gained` snapshot matches `UPGRADE_ITEMS_PER_WIN + ItemData.get_reward(
     "courier_package")` while the summary instance is still reachable, strengthening
     coverage of the before/after delta logic (§3.6).
2. Confirmed unaffected (verified by reading, no changes needed):
   `tests/smoke/smoke_divine_intervention.gd` (rescue path untouched),
   `tests/smoke/smoke_infinite_mode.gd` (calls `advance_map_tier()` directly, not through
   `check_battle_end()`), `tests/smoke/smoke_bounty.gd` (resolves on first death, not full
   battle-end).
3. New smoke test `tests/smoke/smoke_post_battle_summary.gd`, expect_str
   `SMOKE_POST_BATTLE_SUMMARY_OK`, modeled on `smoke_battle_end.gd`/`smoke_courier_package.gd`
   for booting + forcing a win/loss (`BattleBoot.boot()`), and on `smoke_mode_select.gd` for
   driving the overlay directly:
   - Victory: force a win with a friendly/enemy room pre-seeded via `PlayerManager.
     new_friendly_piece`/`new_enemy_piece` set manually before triggering
     `check_battle_end()`, confirm the resulting `PostBattleSummaryLayer`'s summary node
     shows a claimed "+"-badged icon matching the seeded name and the correct
     `upgrade_items_gained` math; emit `continue_pressed`; confirm `return_to_map()` fires
     for a non-boss floor and `advance_map_tier()` fires for a boss floor (two sub-cases).
   - Defeat: force a loss, confirm `Final Floor`/`Final Room` text matches
     `current_map_tier`/`current_map_floor` captured BEFORE `reset_floor_number()` ran; emit
     `back_pressed`; confirm the resulting main-menu instance has its mode-select overlay
     open (`_mode_select_instance` valid, matching `smoke_mode_select.gd`'s assertion style).
   Register it in `tests/run_all.sh` (see §5 for the exact `check_script` call convention and
   where the existing entries for `smoke_battle_end`/`smoke_battle_loss`/`smoke_courier_package`
   live — lines 212-217 and 192-196 respectively — add the new one right after them).

### M5 — Wrap-up
- `CHANGELOG.md` entry at repo root (see existing entries, e.g. the top one, for format —
  feature name + branch + bullet list of what changed and why).
- Full `./tests/run_all.sh`, log result in §6, compare against M0 baseline (only new
  failures matter).
- Final report to Miha (§7 below — fill in as you go, don't leave it for the very end):
  flagged decisions from §3, plus a manual playtest checklist since this is a visual/UX
  feature headless tests can't fully cover.

---

## 5. Test harness facts (verified — do not re-explore)

- Runner: `team-berry-game/tests/run_all.sh`. Unit tests auto-discovered from `tests/unit/`
  via `res://tests/run_unit_tests.gd`; smoke tests are **manually registered** via
  `check_script "<label>" "res://tests/smoke/<file>.gd" <quit_after> "<expect_str>"` calls
  (see lines 87-273 of `run_all.sh` for every existing entry, exact `quit_after` values, and
  the header comment on `check_script` itself at line ~57 explaining WHY it checks for a
  specific `expect_str` and not just "zero errors" — a script that silently no-ops must still
  fail the check).
- Existing entries relevant to this plan, already at their current line numbers in
  `run_all.sh`: `smoke_battle_end` (line 212, quit_after 15), `smoke_battle_loss` (line 214,
  quit_after 15), `smoke_courier_package` (line 192, quit_after 10), `smoke_mode_select`
  (line 97, quit_after 5), `smoke_pause_menu` (line 273, quit_after 80).
- **MainLoop gotcha** (bit people before, see comments in `smoke_battle_end.gd`/
  `smoke_battle_loss.gd`): smoke tests `extends SceneTree`, drive frames via
  `_process(delta) -> bool` — returning `true` TERMINATES the loop, `false` continues it.
  Always return `false` and let `--quit-after` cut it off, so `call_deferred`/`queue_free`
  get frames to actually resolve before the process stops. Never `await` inside `_process`
  (engine never resumes it — silent stall).
- Boot helper: `BattleBoot.boot(self)` (used by `smoke_battle_end.gd`, `smoke_battle_loss.gd`,
  `smoke_courier_package.gd`) sets up `GF.current_map_instance` etc. so the deferred
  scene-transition path under test has somewhere valid to land — needed by the new
  `smoke_post_battle_summary.gd` too.
- "Drive handlers directly" precedent (verbatim from `smoke_mode_select.gd`, already fully
  read during planning): boot the scene, call
  `current_scene._on_play_pressed()`/`current_scene._on_mode_select_back()` directly rather
  than simulating clicks, then assert on the resulting node state
  (`current_scene._mode_select_instance`, `.visible`, `is_instance_valid(...)`). Apply the
  same style to emit `continue_pressed`/`back_pressed` directly on the summary instance.
- Known pre-existing failure as of the M0 baseline commit: `smoke_ability_ui_pipeline`
  (unrelated to this feature — do not attempt to fix it as part of this branch, just don't
  let it get confused with a new regression; note it explicitly in the M0 baseline log entry
  in §6, same as `SNOW_REWORK_PLAN.md`'s M0 did).
- Godot binary: `~/.local/bin/godot4` (headless CLI confirmed installed and working in past
  sessions). Manual verification commands:
  ```
  ~/.local/bin/godot4 --headless --path team-berry-game --script res://tests/smoke/smoke_battle_end.gd --quit-after 15
  ~/.local/bin/godot4 --headless --path team-berry-game --script res://tests/smoke/smoke_battle_loss.gd --quit-after 15
  ~/.local/bin/godot4 --headless --path team-berry-game --script res://tests/smoke/smoke_courier_package.gd --quit-after 10
  ~/.local/bin/godot4 --headless --path team-berry-game --script res://tests/smoke/smoke_post_battle_summary.gd --quit-after <TBD>
  team-berry-game/tests/run_all.sh
  ```

---

## 6. Progress / test log (fill in as you go)

- [x] M0 baseline: branch `features/post-battle-summary` created off `develop @ 67d9909`.
      `./tests/run_all.sh` → all unit tests pass (945), all smoke tests PASS except the
      pre-existing `smoke_ability_ui_pipeline` failure noted in §5. This is the baseline —
      only new deltas against it matter below.
- [x] M1 new-piece plumbing: `PlayerManager.new_friendly_piece`/`new_enemy_piece` added;
      `add_to_friendly_party()` → `bool`; `MapController._handle_event()` clears/sets both
      fields. Added 2 unit tests to `test_player_manager.gd` for the new return value.
      Unit tests: 947 passed, 0 failed (945 baseline + 2 new).
- [x] M2 summary scene: `Scenes/Menu/post_battle_summary.tscn` +
      `Scripts/Menu/post_battle_summary.gd` built per §2.3/§3.1-2. Sanity-checked headless
      (instantiate + call `setup_victory()`/`setup_defeat()` directly, since no windowed
      editor was available in this environment) — both render without errors, party rows and
      reward rows populate correctly, defeat labels format correctly. **Deviation from §4
      M2.4**: could not do the suggested windowed-editor manual check (headless-only
      environment) — covered instead by the standalone headless instantiation check plus the
      full M4 smoke test's assertions on the actual rendered node tree.
- [x] M3 wiring: `main_menu.gd.open_mode_select()`, `GameFlow.gd` (`game_over()` now returns
      `Control`, added `show_victory_summary()`/`show_defeat_summary()` + their signal
      handlers), `BattleController.gd.check_battle_end()` (both branches replaced per §4 M3.3,
      before/after upgrade-items delta, final tier/floor captured before
      `reset_floor_number()`). `./tests/run_all.sh` after this milestone: same as baseline
      except `smoke_battle_end`/`smoke_battle_loss`/`smoke_courier_package` now fail as
      expected (they don't yet know about the new overlay) — exactly the 3 tests M4 updates.
- [x] M4 test updates: updated `smoke_battle_end.gd`/`smoke_battle_loss.gd` to poll for
      `PostBattleSummaryLayer` and emit `continue_pressed`/`back_pressed` before their existing
      post-transition checks; `smoke_courier_package.gd` additionally asserts the summary's
      rendered rewards row matches the win+courier delta before emitting `continue_pressed`.
      New `tests/smoke/smoke_post_battle_summary.gd` (`SMOKE_POST_BATTLE_SUMMARY_OK`) covers
      victory non-boss CONTINUE → `return_to_map()`, victory boss CONTINUE →
      `advance_map_tier()`, and defeat BACK → mode-select-open, plus badge/reward assertions —
      registered in `run_all.sh` right after the existing battle-end entries.
      **Bug found + fixed along the way (not part of the original plan, needed to make the new
      multi-boot test viable)**: `tests/framework/battle_boot.gd`'s `BattleBoot.boot()`
      connected its placement-auto-complete listener *after* `add_child()`-ing the battle
      instance. That only worked when called from a `-s` script's `_initialize()` (where
      `_ready()` is deferred a frame); calling `boot()` a second/third time from `_process()`
      (needed since the new smoke test boots 3 separate battles in sequence) runs `_ready()`
      synchronously, so the PLACEMENT `state_changed` signal could fire before the listener
      was attached, permanently stranding the battle in PLACEMENT. Fixed by connecting before
      `add_child()`. Also widened `complete_placement()`'s cell search from the bottom 3 rows
      to the whole map height (still filtered by the real placement-zone legality check) since
      randomly-spawned "House" obstacles could occasionally block all 3 bottom rows — this
      only became likely to hit once one test process boots 3 battles instead of 1. Verified
      stable across 7+ repeated runs after both fixes (map generation is unseeded/random each
      run). This is a test-infrastructure fix only — no gameplay code path changed.
      Full `./tests/run_all.sh` after M4: identical to the M0 baseline (same single
      pre-existing `smoke_ability_ui_pipeline` failure, nothing else) plus the new
      `smoke_post_battle_summary` PASS.
- [x] M5 wrap-up: CHANGELOG.md entry added (top of file). Final full `./tests/run_all.sh`
      confirms parity with the M0 baseline. See report below.

## 7. Final report to Miha (fill in as you go)

**Flagged decisions (implemented as written, per §3 — confirm or adjust if these don't match
intent):**
- Everything in §3 was implementable exactly as written — no ambiguity hit during
  implementation, no roster edge case needed extra handling beyond what §3.9's "claimed"
  guard already covered.
- One thing worth a look during your manual pass: the summary panel currently has a fixed
  562px-wide content panel with a `ScrollContainer` (500px visible width) around each party
  row, so a tier-end enemy army of ~15 pieces scrolls horizontally inside its row rather than
  wrapping — confirm that reads OK visually rather than looking cramped (§4 M2.1's own note
  flagged this as a risk to watch for).
- Not part of the original plan, but flagged for visibility: fixed a pre-existing latent bug
  in the shared `BattleBoot` test helper (signal-connection ordering, see M4 log entry above)
  — it never affected real gameplay (only test-only multi-boot-in-one-process scenarios), but
  worth knowing this test infra now behaves slightly differently (wider placement search) if
  you extend other smoke tests later.

**Manual playtest checklist** (headless tests can't drive real mouse clicks or judge layout):
- [ ] Recruit an ally (enter a friendly room) → win that battle → the "+" badge lands on the
      correct icon in the "mine" row, other pieces are grayed, row doesn't overflow the panel.
- [ ] Win a battle with no new piece added → both rows show fully grayed icons, no badge.
- [ ] Win a boss-floor battle mid-run → Continue correctly advances to the next (harder) tier.
- [ ] Win the final boss of the last tier in classic mode → summary still shows, Continue
      correctly ends the run to the main menu.
- [ ] Lose a battle → Final Floor/Final Room show the correct numbers (not 0/0), Back lands
      directly on the mode-select overlay (not the bare title screen).
- [ ] Rewards row shows the right "x%d" count for a normal win vs. a boss win vs. a win with
      a surviving courier bonus stacked on top.

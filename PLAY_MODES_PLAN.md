# PLAY MODES (Mode Select + Tutorial hub + Infinite) — implementation plan

Branch: create `features/play-modes` off `develop`. Merge back with `git merge --no-ff`
(this repo never fast-forwards into `develop`/`main`).

**Note on repo state:** `git status` on `develop` currently shows uncommitted changes to
`curses.json`, `battle_ui.gd`, `base_character.gd`, `curse_data.gd`, `BattleController.gd`,
`grid_manager.gd`, `test_curses.gd` plus several new untracked `Scripts/Curses/*.gd` files —
an in-progress "more curse types" pass from a separate session, unrelated to this feature.
This plan's phases don't touch any curse-system file, so there should be no conflict, but
branch from the working tree as-is (don't stash/revert those changes — they aren't yours to
discard) and don't fold them into this feature's commits.

This doc is written so an implementing model can build the feature WITHOUT re-deriving
context. Work phases in order; each ends runnable/testable. Check off `[ ]` boxes as you go.

**Decisions from Miha (do not re-litigate):**
- Clicking "Play" on the main menu goes to a new **Mode Select** screen, styled like the main
  menu (same background image, fonts, button style).
- Mode Select offers **CLASSIC**, **TUTORIAL**, **INFINITE**, **BACK**.
- **CLASSIC**: today's game, unchanged, plus a difficulty selector next to it (same EASY/
  NORMAL/HARD selector as Settings). Hovering it shows a bubble/tooltip explaining what the
  difficulties actually change.
- **TUTORIAL**: leads to a replayable, **scrollable** list of tutorial stages. Each stage has
  descriptive text plus a small playable scene demonstrating one feature. Each stage's scene
  can independently enable/disable enemy AI (and, later, other features) so the demo behaves
  the way that lesson needs. **Only one concrete tutorial stage is needed now** — build the
  framework (hub screen + the mechanism for AI on/off per stage) with one working example;
  Miha will describe the rest of the tutorial content in a follow-up.
- **INFINITE**: same as classic (has the difficulty selector), but instead of returning to the
  main menu after the 3rd map (today's "beat all 3 tiers, run over" screen), it just keeps
  generating maps until the player dies.
- **BACK**: returns to the main menu.

**Defaults chosen by Claude (keep unless Miha objects):**
- One **shared** difficulty selector on the Mode Select screen (not one per button) — EASY/
  NORMAL/HARD is a single global setting (`SettingsManager.difficulty`, already used
  everywhere: curse chance, AI danger-avoidance), so two independent dropdowns would just be
  two views of the same value fighting for attention. It sits in its own row between the
  CLASSIC and INFINITE buttons; the tooltip on it explains the difference regardless of which
  mode the player picks.
- Tooltip text is static (not built from a live JSON read) but the exact numbers are sourced
  from `Data/curses.json` (`difficulty_chance_mult`: easy 0.5×, normal 1×, hard 1.5×) and
  `Data/ai_config.json` (`danger_avoid_prob`: easy 0%, normal 50%, hard 100%) — see §2. Uses
  Godot's built-in `tooltip_text` (native hover bubble), no custom popup needed.
- Mode Select is an **overlay instanced as a child of MainMenu**, exactly like
  `settings_menu.tscn` already is (`main_menu.gd`'s `_on_settings_pressed`/`_on_settings_back`
  — instantiate, hide `VBoxContainer`+`Title`, free on back). CLASSIC/INFINITE leaving through
  `GF.start_new_game()` naturally tears the whole MainMenu (+ its overlay children) down via
  `GF._change_scene_instance()` — no special cleanup needed.
- Tutorial Hub is **not** an overlay — it's a real scene, entered/exited via
  `GF._change_scene_instance()` (new `GF.start_tutorial_stage()` / `GF.return_to_tutorial_hub()`
  helpers), because a tutorial stage is a genuine scene swap (a small battle-like scene) and
  must be able to return to a freshly-built hub afterward. Its own BACK button reuses the
  existing `GF.return_to_main_menu()` (safe to call with no run active — `_end_run()` is a
  no-op when `game_initialized` is already false).
- New `PlayerManager.game_mode: String` (`"classic"` / `"infinite"`), reset by
  `setStarting(mode)` (signature gains a parameter, default `"classic"` so nothing else that
  calls it breaks). `GameFlow.advance_map_tier()` only ends the run at tier 3 when
  `game_mode != "infinite"`.
- Infinite mode needs **no changes to `MapGenerator`**: `_configure_tier()` already does
  `TIER_CONFIGS[clampi(tier, 0, TIER_CONFIGS.size() - 1)]`, so tier 3, 4, 5, ... all silently
  reuse the tier-2 config (king boss, full enemy pool) forever. That's exactly "the game just
  goes on" — the hardest map, repeating.
- Tutorial stages follow this repo's established "autoload reads JSON + registry" pattern
  (`ItemData`, `CurseData`): new `TutorialData` autoload + `Data/tutorials.json` (title/
  description per stage) + a `Dictionary` of `id -> preload(PackedScene)` for stage scenes.
  Per-stage AI on/off is a property of the **scene**, not the JSON — new
  `@export var ai_enabled: bool = true` on `BattleController`, checked at the top of
  `start_enemy_turn()`.
- The one concrete tutorial stage ("Moving & Capturing") is built the same way
  `Scenes/piece_test.tscn` already is: hand-placed pieces + `Battle/battle_controller.tscn`
  instanced + `Scripts/TileMap/grid_manager.gd` + the tiny `Scenes/test_sandbox.gd` root
  script (`register_all_characters_in_scene()` + `battle_controller.initialize_battle()`).
  Copy that proven scene rather than building one from scratch.

---

## 0. Existing code you will build on

| File | What it gives you |
|---|---|
| `team-berry-game/Scripts/main_menu.gd` + `Scenes/Menu/main_menu.tscn` | The overlay pattern to copy verbatim for Mode Select: `_settings_instance` var, `_on_settings_pressed` (instantiate, connect `back_pressed`, `add_child`, hide `$VBoxContainer`/`$Title`), `_on_settings_back` (free instance, show them again). Button style: two `StyleBoxFlat` sub-resources (`normal` white rounded, `hover` grey) + `StyleBoxEmpty` focus, `BLKCHCRY.TTF` font, all buttons in group `"buttons"`. |
| `team-berry-game/Scripts/settings_menu.gd` + `Scenes/Menu/settings_menu.tscn` | The difficulty `OptionButton` pattern to copy: `DIFFICULTY_IDS := ["easy","normal","hard"]` (order matches the 3 popup items), `.selected = DIFFICULTY_IDS.find(SettingsManager.difficulty)`, `item_selected.connect(...)` → `SettingsManager.set_difficulty(DIFFICULTY_IDS[index])`. |
| `team-berry-game/Scripts/SettingsManager.gd` | Autoload holding `difficulty: String` (persisted, default `"normal"`), already the single source of truth — read it, don't duplicate it. |
| `team-berry-game/Data/curses.json` (`config.difficulty_chance_mult`) + `Data/ai_config.json` (`danger_avoid_prob`) | Source numbers for the tooltip text: easy/normal/hard = 0.5×/1×/1.5× curse chance, 0%/50%/100% danger-avoidance. Don't wire live reads — just quote these numbers in the static tooltip string. |
| `team-berry-game/Scripts/Map/GameFlow.gd` (autoload `GF`) | `start_new_game()` (l.45, guards on `game_initialized`), `advance_map_tier()` (l.93 — the "tier >= 3 → end run" branch to gate on mode), `_change_scene_instance()` (l.139, handles old-scene teardown safely), `return_to_main_menu()` (l.165), `_end_run()` (l.173, idempotent). |
| `team-berry-game/Scripts/Player/PlayerManager.gd` | `setStarting()` (l.252, resets `friendly_party`/`enemy_party`/upgrades for a new run — add the mode param here), `current_map_tier` (l.74, already lives here, so `game_mode` belongs next to it). |
| `team-berry-game/Scripts/Map/MapGenerator.gd` | `TIER_CONFIGS` (l.42, exactly 3 entries) + `_configure_tier()` (l.113, `clampi(tier, 0, TIER_CONFIGS.size()-1)`) — this clamp is *why* infinite mode needs zero generator changes. |
| `team-berry-game/Scripts/TileMap/BattleController.gd` | `start_enemy_turn()` (l.386) / `end_enemy_turn()` (l.476) — add the `ai_enabled` export + guard here. |
| `team-berry-game/Scripts/Data/item_data.gd` / `Scripts/Data/curse_data.gd` | The "autoload reads a JSON file, exposes getters" shape to copy for `TutorialData`. |
| `team-berry-game/Scenes/piece_test.tscn` + `Scenes/test_sandbox.gd` + `Battle/battle_controller.tscn` | The proven "hand-placed pieces, no map/run needed" scene shape — duplicate this for the one concrete tutorial stage instead of building from scratch. |
| `team-berry-game/tests/smoke/smoke_start_new_game.gd` | Drives `main_menu._on_start_pressed()` directly and expects `GF.start_new_game()` to fire synchronously after. **This breaks** once Play opens an overlay instead — see §5, it needs updating, not deleting. |
| `team-berry-game/project.godot` `[autoload]` | Register `TutorialData` after `CurseData`. |

Verification tooling (installed & proven): `godot4` headless CLI;
`cd team-berry-game && ./tests/run_all.sh`. Gotchas from prior plans, still apply: rerun
`godot4 --headless --import --path team-berry-game` after adding new `class_name`/scenes; in
`--script` tests `_process()` must `return false`; use here-strings
(`grep -qF "$x" <<< "$out"`) not `echo | grep` in shell scripts (pipefail SIGPIPE trap, see
`FIX_PROGRESS.md`).

---

## Phase 1 — Mode Select screen

**New:** `Scripts/Menu/mode_select_menu.gd`, `Scenes/Menu/mode_select_menu.tscn`.

Scene: copy `main_menu.tscn`'s structure (same `menubackground.jpg` `StyleBoxTexture`
Background panel, same font, same two-StyleBoxFlat+StyleBoxEmpty button styling) into a new
root `Control` "ModeSelectMenu":
- `Title` Label, text `"SELECT MODE"`.
- `VBoxContainer` containing, top to bottom:
  - `ClassicButton` (text `"CLASSIC"`, group `"buttons"`)
  - `InfiniteButton` (text `"INFINITE"`, group `"buttons"`)
  - `DifficultyRow` (`HBoxContainer`): `Label` `"DIFFICULTY"` + `%DifficultyOption`
    (`OptionButton`, same 3 items as `settings_menu.tscn`'s `DifficultyOption` —
    `item_0="EASY"`, `item_1="NORMAL"`, `item_2="HARD"`).
  - `TutorialButton` (text `"TUTORIAL"`, group `"buttons"`)
  - `BackButton` (text `"BACK"`, group `"buttons"`)

`mode_select_menu.gd`:
```gdscript
extends Control

signal back_pressed

@onready var difficulty_option: OptionButton = %DifficultyOption

const DIFFICULTY_IDS := ["easy", "normal", "hard"]
const DIFFICULTY_TOOLTIP := "EASY - enemies get curses half as often (0.5x) and never play it safe.\nNORMAL - standard curse rate, enemies sometimes retreat to safety (50%%).\nHARD - enemies get curses 50%% more often (1.5x) and always retreat to safety."

func _ready():
	difficulty_option.selected = DIFFICULTY_IDS.find(SettingsManager.difficulty)
	difficulty_option.item_selected.connect(_on_difficulty_selected)
	difficulty_option.tooltip_text = DIFFICULTY_TOOLTIP

func _on_difficulty_selected(index: int):
	UiAudio.play_click()
	if index < 0 or index >= DIFFICULTY_IDS.size():
		return
	SettingsManager.set_difficulty(DIFFICULTY_IDS[index])

func _on_classic_pressed():
	UiAudio.play_click()
	PlayerManager.setStarting("classic")
	GF.start_new_game()

func _on_infinite_pressed():
	UiAudio.play_click()
	PlayerManager.setStarting("infinite")
	GF.start_new_game()

func _on_tutorial_pressed():
	UiAudio.play_click()
	GF.start_tutorial_hub()

func _on_back_pressed():
	UiAudio.play_click()
	back_pressed.emit()
```
Wire `[connection]` blocks for all 4 buttons' `pressed` signals to the matching handlers above
(same style as `main_menu.tscn`'s connection block at the bottom of the file).

**`main_menu.gd` changes:**
- Rename `_on_start_pressed` → `_on_play_pressed`; it no longer calls
  `PlayerManager.setStarting()`/`GF.start_new_game()` directly. Instead, mirror
  `_on_settings_pressed`/`_on_settings_back` exactly, with a new
  `const MODE_SELECT_SCENE = preload("res://Scenes/Menu/mode_select_menu.tscn")` and
  `var _mode_select_instance: Control = null`:
```gdscript
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
- `main_menu.tscn`: rename the `"START GAME"` button's text to `"PLAY"`, and its
  `[connection signal="pressed" ... method="_on_start_pressed"]` to `_on_play_pressed`.

### Phase 1 checklist
- [x] `mode_select_menu.tscn`/`.gd` built, styled like main menu, all 4 buttons wired
- [x] `main_menu.gd`/`.tscn` updated: `PLAY` opens Mode Select overlay, `BACK` closes it
- [x] Boot check: `godot4 --headless --path . --scene res://Scenes/Menu/main_menu.tscn --quit-after 5` — zero ERROR lines
      (only the pre-existing engine "1 resources still in use at exit" cleanup line, no script
      errors; overlay open/close + tooltip also driven headless via a scratch SceneTree script.
      Note: `setStarting(mode)`+`game_mode` from Phase 3 were pulled forward — the Phase 1
      overlay script can't compile without the new signature.)

---

## 2. Difficulty tooltip — verification only

No new code beyond §1's `tooltip_text` line. Manually confirm in-editor (or via a quick smoke
test, §5) that hovering `%DifficultyOption` on the Mode Select screen shows the 3-line bubble.
The numbers it quotes (0.5×/1×/1.5× curse chance, 0%/50%/100% danger-avoidance) come straight
from `Data/curses.json` / `Data/ai_config.json` — if either changes later, update this string
too (it's intentionally static, not computed).

---

## Phase 3 — Infinite mode

**`PlayerManager.gd`:**
```gdscript
var game_mode: String = "classic"
```
(near `current_map_tier`, l.74). Update `setStarting()`:
```gdscript
func setStarting(mode: String = "classic") -> void:
	game_mode = mode
	friendly_party = default_friends.duplicate()
	enemy_party = default_enemies.duplicate()
	piece_upgrades = {}
	upgrade_items = 0
	owned_items = {}
	items_changed.emit()
```
(every other existing caller of `setStarting()` keeps working unchanged via the default arg —
grep for callers before editing to confirm none pass positional args that would collide).

**`GameFlow.gd` `advance_map_tier()`** — gate the "run complete" branch on mode:
```gdscript
func advance_map_tier():
	PlayerManager.current_map_tier += 1

	if PlayerManager.current_map_tier >= 3 and PlayerManager.game_mode != "infinite":
		print("GF: Igralec je premagal vse 3 mape. Vračanje na Main Menu.")
		_end_run()
		_change_scene_instance(MAIN_MENU_SCENE.instantiate())
		return

	if is_instance_valid(current_map_instance):
		current_map_instance.queue_free()
	...
```
Everything below that `if` (new map instance, `reset_floor_number()`, `enemy_party` reset)
stays exactly as-is — it already does the right thing for tier 3, 4, 5, ... since
`MapGenerator._configure_tier()` clamps to the tier-2 config (see §0). Death still routes
through the existing `game_over()` (unchanged) → main menu, for both modes.

### Phase 3 checklist
- [x] `PlayerManager.game_mode` added, `setStarting(mode)` sets it, default arg keeps other
      callers working (landed early, in the Phase 1 commit — see §1 checklist note; grep
      confirmed all other callers are zero-arg)
- [x] `advance_map_tier()` infinite-mode branch added
- [x] Manual/headless check: start an infinite run, defeat 3+ boss floors in a row (or
      temporarily hack `current_map_tier = 2` before the 3rd boss fight to reach the branch
      quickly), confirm no return to main menu and a 4th map generates using tier-2 config
      (king boss, full enemy pool)
      (done headless via scratch SceneTree script: infinite tier 2→3 keeps a MapInstance on
      the tier-2 config — floors=9, king boss, full pool — and classic tier 2→3 still ends
      the run back at MainMenu with tier reset. Gotcha: run godot4 with an explicit
      `--path team-berry-game`; `--path .` from repo root silently loads no project.)

---

## Phase 4 — Tutorial hub + one concrete stage

**New `Data/tutorials.json`:**
```json
{
  "stages": [
    {
      "id": "movement",
      "title": "Moving & Capturing",
      "description": "Practice moving your pieces onto the board and capturing enemies. Enemies here won't move or fight back - take your time."
    }
  ]
}
```

**New `Scripts/Data/tutorial_data.gd`** (autoload `TutorialData`, copy `item_data.gd`'s
JSON-loader shape):
```gdscript
extends Node

const TUTORIALS_PATH := "res://Data/tutorials.json"

const STAGE_SCENES: Dictionary = {
	"movement": preload("res://Scenes/Tutorial/tutorial_movement.tscn"),
}

var _stages: Array = []

func _ready():
	_stages = _load_json(TUTORIALS_PATH).get("stages", [])

func get_stages() -> Array:
	return _stages

func get_stage_scene(id: String) -> PackedScene:
	return STAGE_SCENES.get(id)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("TutorialData: manjka datoteka %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
```
Register in `project.godot` `[autoload]`, after `CurseData`:
`TutorialData="*res://Scripts/Data/tutorial_data.gd"`.

**New `Scenes/Tutorial/tutorial_movement.tscn`:** duplicate `Scenes/piece_test.tscn` (already
has King + Queen hand-placed, `battle_controller.tscn` instanced, `GridManager`, and uses
`Scenes/test_sandbox.gd` as its root script — see §0). Changes on top of the copy:
- Add 1-2 enemy pieces nearby (e.g. `enemy_pawn.tscn` instances, `is_enemy = true` already set
  in their own scene) so there's something to capture.
- On the instanced `BattleController` node, override the new export: `ai_enabled = false`
  (edit in the Inspector, or add `ai_enabled = false` under that node's property overrides in
  the `.tscn` text — same mechanism Godot uses for any exported-var override on a scene
  instance).
- Add a small `CanvasLayer` (screen-locked, same reason `PauseMenuLayer` is one in
  `GameFlow.gd` — the board's `Camera2D` shouldn't drag it around) containing: a `Label` top
  banner with the stage description (`TutorialData.get_stages()[0]["description"]`, or just
  hardcode it in this one scene for now — either is fine for a single stage) and a `Button`
  `"BACK"` wired to a new tiny root-script method that calls `GF.return_to_tutorial_hub()`.

**`BattleController.gd`:** add near the top of the script:
```gdscript
@export var ai_enabled: bool = true
```
In `start_enemy_turn()` (l.386), right after the `_set_state(BattleState.ENEMY_TURN)` /
print line, add:
```gdscript
	if not ai_enabled:
		end_enemy_turn()
		return
```
This hands the turn straight back to the player with no enemy ever acting — the correct
"AI disabled" behavior (enemies stand still, player can freely practice moves/captures without
being attacked). Leave `battle.tscn`'s live `BattleController` instance at the default
`ai_enabled = true` (untouched — the export default preserves current behavior everywhere
except this one tutorial scene).

**New `Scripts/Menu/tutorial_hub_menu.gd`, `Scenes/Menu/tutorial_hub_menu.tscn`:** same visual
style as Mode Select (background/font/button styling), but content is a `ScrollContainer` >
`VBoxContainer` built at runtime from `TutorialData.get_stages()`:
```gdscript
extends Control

@onready var rows_container: VBoxContainer = %RowsContainer

func _ready():
	for stage in TutorialData.get_stages():
		var row := HBoxContainer.new()
		var title := Label.new()
		title.text = stage["title"]
		title.custom_minimum_size = Vector2(200, 0)
		var desc := Label.new()
		desc.text = stage["description"]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(400, 0)
		var play_button := Button.new()
		play_button.text = "PLAY"
		play_button.pressed.connect(_on_stage_pressed.bind(stage["id"]))
		row.add_child(title)
		row.add_child(desc)
		row.add_child(play_button)
		rows_container.add_child(row)

func _on_stage_pressed(stage_id: String):
	UiAudio.play_click()
	GF.start_tutorial_stage(TutorialData.get_stage_scene(stage_id))

func _on_back_pressed():
	UiAudio.play_click()
	GF.return_to_main_menu()
```
`BackButton` in the scene wired to `_on_back_pressed`.

**`GameFlow.gd`:** new preload + 2 helpers, alongside the existing scene consts:
```gdscript
const TUTORIAL_HUB_SCENE = preload("res://Scenes/Menu/tutorial_hub_menu.tscn")

func start_tutorial_hub():
	_change_scene_instance(TUTORIAL_HUB_SCENE.instantiate())

func start_tutorial_stage(stage_scene: PackedScene):
	_change_scene_instance(stage_scene.instantiate())

func return_to_tutorial_hub():
	_change_scene_instance(TUTORIAL_HUB_SCENE.instantiate())
```
`Mode Select`'s `_on_tutorial_pressed()` (§1) already calls `GF.start_tutorial_hub()`.

### Phase 4 checklist
- [x] `Data/tutorials.json` + `TutorialData` autoload registered
- [x] `tutorial_movement.tscn` built from `piece_test.tscn`, `ai_enabled = false`, enemy
      pieces added, description + BACK overlay wired
      (plus one thing this plan missed: the stage's root script must populate
      `PlayerManager.active_party`/`active_enemies` itself — entered from the menu, no run
      is active so `resetActives()` never ran, and `check_battle_end()` would fire the
      victory/defeat branch on the first END TURN with no map to return to. An extra
      `"tutorial_keepalive"` entry in `active_enemies` keeps `enemyGone()` false even after
      both pawns are captured — the stage exits only via BACK.)
- [x] `BattleController.ai_enabled` export + `start_enemy_turn()` guard added; live
      `battle.tscn` behavior unchanged (default `true`)
- [x] `tutorial_hub_menu.tscn`/`.gd` built, scrollable, lists stage(s) from `TutorialData`
- [x] `GF.start_tutorial_hub/start_tutorial_stage/return_to_tutorial_hub` added
- [x] Manual playtest: Main Menu → PLAY → TUTORIAL → Moving & Capturing → confirm the enemy
      pieces never move even after taking several player turns → BACK → back at the hub →
      BACK → back at Main Menu
      (done headless via a scratch SceneTree driver: hub lists 1 row; stage loads with
      `ai_enabled=false`; END TURN → enemy turn immediately hands back → Turn 2 with both
      pawn `grid_pos` unchanged; BACK rebuilds a fresh hub. Suite note for Phase 5:
      `smoke_campfire_flow`, `smoke_shop_map_flow`, `smoke_spyglass` fail on this branch
      even at the pre-Phase-4 HEAD — pre-existing, verified via stash round-trip — alongside
      the expected `smoke_start_new_game` breakage.)

---

## Phase 5 — Tests + wrap-up

**Fix the now-broken smoke test** `tests/smoke/smoke_start_new_game.gd`: it currently calls
`main_menu._on_start_pressed()` directly, which no longer exists / no longer starts a game
synchronously. Update it to drive the real flow one step further: call
`main_menu._on_play_pressed()`, then reach the instantiated overlay
(`main_menu._mode_select_instance`) and call its `_on_classic_pressed()` — keep the comment
explaining this is deliberately the one test that drives the actual button-press flow instead
of `BattleBoot.boot()`.

**New smoke test** `tests/smoke/smoke_mode_select.gd` (add to `run_all.sh` alongside the
others, same `check_script` pattern): boots `main_menu.tscn`, calls `_on_play_pressed()`,
asserts `_mode_select_instance` is valid and `$VBoxContainer` is hidden; then calls
`main_menu._on_mode_select_back()` directly and asserts `$VBoxContainer` is visible again and
`_mode_select_instance` is no longer valid (freed). Print `SMOKE_MODE_SELECT_OK` on success.

**New smoke test** `tests/smoke/smoke_infinite_mode.gd`: use `BattleBoot`-style setup (or a
lighter hand-rolled one) to call `PlayerManager.setStarting("infinite")`, set
`PlayerManager.current_map_tier = 2`, call `GF.advance_map_tier()`, and assert
(a) the scene did **not** switch to `MAIN_MENU_SCENE` (`get_tree().current_scene` stays a
`MapController`/map instance) and (b) `PlayerManager.current_map_tier == 3`. Print
`SMOKE_INFINITE_MODE_OK`.

**New smoke test** `tests/smoke/smoke_tutorial_ai_disabled.gd`: instantiate
`tutorial_movement.tscn` (or a minimal battle scene with `ai_enabled = false` set), drive to
`ENEMY_TURN` state, tick a few frames, assert no enemy piece's `grid_pos` changed and the state
returned to `PLAYER_TURN`. Print `SMOKE_TUTORIAL_AI_OK`.

- [x] `smoke_start_new_game.gd` updated for the new PLAY → Mode Select → CLASSIC flow
- [x] `smoke_mode_select.gd` added + wired into `run_all.sh`
- [x] `smoke_infinite_mode.gd` added + wired into `run_all.sh`
- [x] `smoke_tutorial_ai_disabled.gd` added + wired into `run_all.sh`
- [x] Full `./tests/run_all.sh` green (all 38 checks). The "3 pre-existing failures" noted
      in §4 were NOT pre-existing after all: `smoke_campfire_flow` and `smoke_shop_map_flow`
      also called `_on_start_pressed()` (this plan's §0 claim that only
      `smoke_start_new_game` drives the real Start flow was wrong) — the Phase 1 rename
      made their `has_method()` gate return false forever, a silent no-op with zero errors.
      Both now drive PLAY → overlay CLASSIC like `smoke_start_new_game`. `smoke_spyglass`
      just flakes occasionally; it passed unmodified in both full runs.
- [x] Boot checks with zero ERROR lines: `main_menu.tscn`, `mode_select_menu.tscn` (boots
      fine standalone as-is — its script only needs autoloads), `tutorial_hub_menu.tscn`,
      `tutorial_movement.tscn`
- [x] `godot4 --headless --import --path team-berry-game` re-run after adding the new scenes
      (needed for `.import` files to exist before any scene-loading test can find them)
- [x] `CHANGELOG.md` entry added (repo keeps one)
- [x] Commits: small, per-phase, imperative English messages matching `git log` style, each
      ending with the Claude co-author line already used in this repo. Do NOT merge to
      `develop` — leave the branch for review.

## Explicitly out of scope (don't build)
- More than one tutorial stage / any specific tutorial content beyond "Moving & Capturing" —
  Miha will spec the rest later.
- Per-stage toggles for anything other than `ai_enabled` (fog, curses, items, etc.) — the
  export-var pattern on `BattleController`/`grid_manager` is the template to reuse later, but
  don't add speculative toggles now.
- Any "best tier reached" / score tracking / leaderboard for infinite mode — it just runs
  until death, nothing is recorded beyond what already exists.
- Two independent difficulty selectors (one per CLASSIC/INFINITE row) — one shared selector,
  per the default decision above.
- Changing `MapGenerator.TIER_CONFIGS` to add genuinely new (harder-than-tier-2) content for
  high infinite-mode depth — out of scope; it deliberately just repeats tier 2 forever.
- Reworking the Settings menu's own difficulty selector — it's untouched, still works exactly
  as it does today; Mode Select's selector is a second view of the same `SettingsManager`
  value.

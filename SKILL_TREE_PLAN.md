# Skill Tree Plan — per-piece skill trees + new abilities

Implementation plan for replacing the flat "2 slots, 3 levels" upgrade system with a
small **skill tree per piece type**, purchased at the **same campfire upgrade panel**
with the **same currency** (`PlayerManager.upgrade_items`). Written to be followed
step-by-step; each milestone is a self-contained commit that leaves the game working.

Branch: create `features/skill-trees` off `develop`. Merge back with `--no-ff` (house rule).

---

## 1. Current system (what exists today — do not re-derive)

- Each ally piece script (`Scripts/CharacterPieces/Ally/*.gd`) has `const ABILITY_DEFS`
  = array of **2** abilities, each with `base` / `mid` / `upgraded` tier dicts
  (`ABILITY_TIER_KEYS` in `base_character.gd`, `ABILITY_LEVEL_MAX = 3`).
- Per-battle uses come from `Data/abilities.json` via the `AbilityData` autoload
  (`Scripts/Data/ability_data.gd`): `base_uses` / `mid_uses` / `max_uses` per ability id.
- Persistent per-run state lives in `PlayerManager.piece_upgrades`
  (`Scripts/Player/PlayerManager.gd`), keyed by piece type string
  (`"pawn"`, …): `{"slot2_unlocked": bool, "levels": {1: int, 2: int}}`.
  Spending happens ONLY in `try_unlock_slot2` / `try_level_up_ability`.
- `BaseCharacter._load_persistent_upgrades()` copies that into
  `ability2_unlocked` + `ability_levels` on spawn. Battle code reads only those
  (`_tier_data`, `_ability_uses_max`, `get_ability_info`).
- UI: `Scenes/Menu/CampfireUpgradePanel.gd` (opened from `Scripts/Map/campfire.gd`)
  builds one row per owned piece type with UNLOCK / LEVEL UP buttons.
- Battle side panel: `Scripts/Battle/battle_ui.gd` has hardcoded `Ability1*` /
  `Ability2*` node refs, keybinds `ability_1` / `ability_2`, and
  `_clear_ability_rows()`.
- Targeted abilities flow through `Scripts/map_behaviour.gd`
  (`begin_ability_targeting` / `pending_ability` — a single target click).
- Useful existing primitives (reuse these, don't reinvent):
  - `is_capture_immune` on `BaseCharacter` — generic "cannot be captured" flag,
    already checked at capture resolution (`base_character.gd:243`, alongside the
    shop-v2 `is_castle_protected()` check — same `if` line handles both) and
    cleared by `BattleController._clear_expired_evade()`. Knight's Evade just sets it.
  - `BattleController.add_bonus_move()` (`moves_remaining += 1`) — the
    `extra_move` item's mechanism for "grant an extra move this turn," useful
    context but NOT what Queen's Command uses (Command needs the bonus move
    restricted to one chosen ally; `add_bonus_move()` adds to the shared pool
    any piece can spend — see the corrected §4.5 for Command's actual design).
  - `grid_manager.swap_characters(a, b)` — already implemented (for the
    `changeling`/`abduction` curses): vacates both tiles, swaps `grid_pos`,
    re-occupies, slides both sprites. Directly reusable for Rook's Castling
    (§4.4) instead of hand-rolling a swap.
  - `apply_curse(new_curse)` / `clear_curse()` on `BaseCharacter`.
  - King's Cleanse converts an enemy into a **temporary ally for this battle** —
    that spawning pathway is the model for Pawn's Promotion.
  - Rook Reinforce / Bishop Traps — "zone active until this piece moves" pattern.
  - `_area_tiles(tier, pos)` — shared square/plus area helper.
  - `grid_manager.reveal_area(positions)` — snow/fog clearing.

**Key design decision: battle code keeps reading `ability_levels` + slot-unlocked
flags exactly as today. The skill tree only changes HOW those values are derived,
and adds (a) a 3rd ability slot, (b) passive effects.** This keeps the diff small.

---

## 2. Data model

### 2.1 New file `Data/skill_trees.json`

One tree per piece type. Every tree has the **same node-id skeleton** (11 nodes),
so UI and logic are uniform:

| node id     | meaning                                   | requires        | excludes |
|-------------|-------------------------------------------|-----------------|----------|
| `a1_lv2`    | ability 1 → level 2                       | —               | —        |
| `a1_lv3`    | ability 1 → level 3                       | `a1_lv2`        | —        |
| `a2_unlock` | unlock ability slot 2                     | —               | —        |
| `a2_lv2`    | ability 2 → level 2                       | `a2_unlock`     | —        |
| `a2_lv3`    | ability 2 → level 3                       | `a2_lv2`        | —        |
| `p1`        | passive perk                              | —               | —        |
| `a3_unlock` | unlock NEW ability slot 3                 | `p1`            | —        |
| `a3_lv2`    | ability 3 → level 2                       | `a3_unlock`     | —        |
| `a3_lv3`    | ability 3 → level 3                       | `a3_lv2`        | —        |
| `spec_a`    | specialization A (pick one)               | `a3_unlock`     | `spec_b` |
| `spec_b`    | specialization B (pick one)               | `a3_unlock`     | `spec_a` |

Node schema:

```json
{
  "id": "a1_lv2",
  "name": "Rally II",
  "desc": "Rally now moves the 3 closest allies.",
  "cost": 2,
  "requires": ["..."],      // ALL must be purchased; [] = available immediately
  "excludes": ["..."],      // if ANY is purchased, this node is permanently locked
  "effect": { "type": "...", ... }
}
```

`effect.type` vocabulary (complete list — implement exactly these):

| type                  | fields              | meaning |
|-----------------------|---------------------|---------|
| `ability_level`       | `slot` (1/2/3)      | +1 level to that slot (stacking; level = 1 + count owned) |
| `ability_unlock`      | `slot` (2/3)        | unlocks that ability slot |
| `move_range`          | `amount`            | +amount to `move_range` for all pieces of this type |
| `extra_uses`          | `slot`, `amount`    | +amount per-battle uses for that slot |
| `battle_start_reveal` | `radius`            | at battle start, clear snow in (2r+1)² square around each piece of this type |
| `move_reveal`         | `radius`            | after this piece finishes any move, clear snow around landing tile |
| `curse_immune`        | —                   | curses cannot be applied to pieces of this type |
| `flag`                | `flag` (string)     | free-form marker read by piece scripts (used by `queen_spec_a`) |

Costs (uniform across pieces, tune later): `a1_lv2/a1_lv3/a2_lv2/a2_lv3` = 2,
`a2_unlock` = 1, `p1` = 1, `a3_unlock` = 2, `a3_lv2/a3_lv3` = 2, `spec_a/spec_b` = 2.
Full tree ≈ 18 items (specs mutually exclusive), so a full run still can't max
everything — good.

### 2.2 New autoload `Scripts/Data/skill_tree_data.gd` (`SkillTreeData`)

Mirror `ability_data.gd` style (load JSON in `_ready`, `push_error` on missing/invalid).
API:

```gdscript
func get_tree_nodes(piece_type: String) -> Array    # node defs in display order
func get_node_def(piece_type: String, node_id: String) -> Dictionary  # {} if missing
```

Register in `project.godot` under `[autoload]` next to `AbilityData`.
(Names avoid `get_tree`/`get_node` — those would override the native `Node`
methods and fail to compile. Implemented as `get_tree_nodes`/`get_node_def`.)

### 2.3 `PlayerManager` — replace the upgrade struct

`piece_upgrades[piece_type]` becomes `{"nodes": Array[String]}` (purchased node ids).
It is per-run state reset in `setStarting()`, so **no save migration is needed** —
just update every touchpoint in the same commit.

Replace `try_unlock_slot2` / `try_level_up_ability` with:

```gdscript
func has_tree_node(piece_type: String, node_id: String) -> bool
func can_buy_node(piece_type: String, node_def: Dictionary) -> bool
    # false if: already owned, any `requires` missing, any `excludes` owned,
    # or upgrade_items < cost
func try_buy_node(piece_type: String, node_id: String) -> bool
    # looks up def in SkillTreeData, checks can_buy_node, deducts cost,
    # appends id, emits items_changed (same signal the panel already listens to)
```

Derived getters (these are what `BaseCharacter` will call):

```gdscript
func get_ability_level(piece_type: String, slot: int) -> int
    # 1 + number of owned nodes whose effect is {type:"ability_level", slot:slot}
func is_slot_unlocked(piece_type: String, slot: int) -> bool
    # slot 1 always true; else any owned node with {type:"ability_unlock", slot:slot}
func get_passive_effects(piece_type: String) -> Array
    # effect dicts of all owned nodes EXCEPT ability_level/ability_unlock types
```

Update `debug_max_all_upgrades()`: for each type, append every node id except
`spec_b` (so excludes stay consistent).

---

## 3. Per-piece trees — full content for `Data/skill_trees.json`

Ability level nodes (`a*_lv*`) always carry
`"effect": {"type":"ability_level","slot":N}` and unlock nodes
`{"type":"ability_unlock","slot":N}`; descriptions below give name + desc only.
Level-node descs should quote the NEXT tier's ability desc (copy from ABILITY_DEFS)
— e.g. pawn `a1_lv2` desc = the `mid` desc of Rally.

### Pawn — support (Rally / Lantern Signal / **Promotion**)

- `p1` **Long March** (1): `{"type":"move_range","amount":1}` — "Pawns move 1 tile further."
- Ability 3 **Promotion** (`id: "promotion"`, see §4.1).
- `spec_a` **Fresh Powder** (2): `{"type":"battle_start_reveal","radius":2}` —
  "Battles start with snow cleared in 5x5 around each pawn."
- `spec_b` **Drill Sergeant** (2): `{"type":"extra_uses","slot":1,"amount":1}` —
  "Rally gains +1 use per battle."

### Knight — mobility (Evade / Reposition / **Ambush**)

- `p1` **Pathfinder** (1): `{"type":"move_reveal","radius":1}` —
  "After this knight moves, snow clears in 3x3 around its landing tile."
- Ability 3 **Ambush** (`id: "ambush"`, see §4.2).
- `spec_a` **Shadow Rider** (2): `{"type":"curse_immune"}` — "Knights cannot be cursed."
- `spec_b` **Relentless** (2): `{"type":"extra_uses","slot":2,"amount":1}` —
  "Reposition gains +1 use per battle."

### Bishop — control (Longshot / Traps / **Sanctify**)

- `p1` **Vigil** (1): `{"type":"battle_start_reveal","radius":1}` —
  "Battles start with snow cleared in 3x3 around each bishop."
- Ability 3 **Sanctify** (`id: "sanctify"`, see §4.3).
- `spec_a` **Hex Ward** (2): `{"type":"curse_immune"}` — "Bishops cannot be cursed."
- `spec_b` **Sniper** (2): `{"type":"extra_uses","slot":1,"amount":1}` —
  "Longshot gains +1 use per battle."

### Rook — defense/vision (Lookout / Reinforce / **Castling**)

- `p1` **Watchtower** (1): `{"type":"battle_start_reveal","radius":1}` —
  "Battles start with snow cleared in 3x3 around each rook."
- Ability 3 **Castling** (`id: "castling"`, see §4.4).
- `spec_a` **Garrison** (2): `{"type":"extra_uses","slot":2,"amount":1}` —
  "Reinforce gains +1 use per battle."
- `spec_b` **Farsight** (2): `{"type":"extra_uses","slot":1,"amount":1}` —
  "Lookout gains +1 use per battle."

### Queen — power (Exterminate / Lure / **Command**)

- `p1` **Regal Presence** (1): `{"type":"curse_immune"}` — "The queen cannot be cursed."
- Ability 3 **Command** (`id: "command"`, see §4.5).
- `spec_a` **Scorched Earth** (2): `{"type":"flag","flag":"blast_clears_snow"}` —
  "Exterminate's blast also clears all snow in its area."
- `spec_b` **Siren Song** (2): `{"type":"extra_uses","slot":2,"amount":1}` —
  "Lure gains +1 use per battle."

### King — leader (Cleanse / Heal / **Royal Decree**)

- `p1` **Crown Authority** (1): `{"type":"move_range","amount":1}` —
  "The king moves 1 tile further."
- Ability 3 **Royal Decree** (`id: "royal_decree"`, see §4.6).
- `spec_a` **Beacon of Hope** (2): `{"type":"battle_start_reveal","radius":2}` —
  "Battles start with snow cleared in 5x5 around the king."
- `spec_b` **Divine Favor** (2): `{"type":"extra_uses","slot":2,"amount":1}` —
  "Heal gains +1 use per battle."

---

## 4. New third abilities (one per piece)

Add as the **3rd entry** in each piece's `ABILITY_DEFS` and a matching branch in its
`_execute_ability`. Add to `Data/abilities.json`:

```json
"promotion":    {"base_uses": 1, "mid_uses": 1, "max_uses": 1},
"ambush":       {"base_uses": 1, "mid_uses": 1, "max_uses": 2},
"sanctify":     {"base_uses": 1, "mid_uses": 1, "max_uses": 2},
"castling":     {"base_uses": 1, "mid_uses": 1, "max_uses": 2},
"command":      {"base_uses": 1, "mid_uses": 1, "max_uses": 2},
"royal_decree": {"base_uses": 1, "mid_uses": 1, "max_uses": 1}
```

(`level_up_cost` / `unlock_cost` fields are now dead — costs live in
`skill_trees.json`. Leave the old fields on existing entries; `AbilityData`
getters for them can stay but nothing calls them after §6.)

### 4.1 Pawn — Promotion (`needs_target: false`)

> base: "This pawn permanently becomes a knight for the rest of this battle."
> mid: "…becomes a rook…" · upgraded: "…becomes a queen…"

Tier dicts: `{"promote_to": "knight"}` / `{"promote_to": "rook"}` / `{"promote_to": "queen"}`.
Implementation: reuse the King-Cleanse temp-ally pathway — spawn a temporary ally
of `promote_to` type at the pawn's tile, then remove the pawn from the grid.
**Critical:** removing the pawn must NOT count as a death (it must not enter the
fallen-pieces list that Heal reads, and must not trigger death persistence) —
follow how Cleanse removes the converted enemy, not the capture path. The temp
piece must not join the roster (roster is string-based; temp allies already
handle this — copy Cleanse's approach exactly).

### 4.2 Knight — Ambush (`needs_target: true`)

> base/mid/upgraded: "Jump to any snow-free empty tile within N tiles." N = 3/4/5.

Tier dicts: `{"radius": 3}` / `{"radius": 4}` / `{"radius": 5}`.
`get_ability_targets`: free tiles within Chebyshev radius that are inside the
boundary, not occupied, and not snow-covered. "Snow" here means the
**curse-hazard overlay** (`grid_manager.curse_fog_nodes`, the dictionary
`Snowfall`/`Blizzard`/`Contagion` curses populate via `cover_area()`) —
`grid_manager.curse_fog_nodes.has(pos)` — NOT the base fog-of-war
(`grid_manager.fog_nodes`, always called "megla"/fog in this codebase, never
"snow"; those tiles are typically already excluded from targeting by virtue of
being unexplored). Execute: `execute_move(target)` (knight already jumps; no
path needed).

### 4.3 Bishop — Sanctify (`needs_target: false`)

> base: "Remove curses from all allied pieces within 3x3 of this bishop."
> mid: plus-shape · upgraded: 5x5.

Tier dicts follow the existing shape pattern:
`{"shape":"square","radius":1}` / `{"shape":"plus"}` / `{"shape":"square","radius":2}`.
Execute: for each ally in `_area_tiles(tier, grid_pos)` with `curse != null`,
call `clear_curse()`. Return true if at least one curse was removed (false = no
valid use, same convention as other abilities).

### 4.4 Rook — Castling (`needs_target: true`)

> base: "Swap positions with your king if he is in this rook's line of sight."
> mid: "Swap positions with any ally in this rook's line of sight."
> upgraded: "Swap positions with any allied piece anywhere."

Tier dicts: `{"who":"king","los":true}` / `{"who":"any","los":true}` / `{"who":"any","los":false}`.

`get_ability_targets` (LOS case): walk `get_move_directions()` same as
`find_visible_enemies()`/`get_empty_tiles_in_los()` (`base_character.gd:421`/
`:446`) — per direction, step until boundary or an occupied tile; if the first
occupant is an ally (`seen_char.is_enemy == is_enemy`, matching `who`
filter), collect it, then stop (LOS is blocked either way, ally or not — copy
`find_visible_enemies`'s break behavior exactly, just flip the enemy check to
an ally check). Non-LOS case (`los: false`): all matching allies on the board,
no walk needed.

Execute: **`grid_manager.swap_characters(a, b)` already exists and does exactly
this** — vacates both tiles, swaps `grid_pos`, re-occupies, slides both
sprites. It was added for the `changeling`/`abduction` curse effects (grep
`swap_characters` in `grid_manager.gd`) and is already curse/battle-log
agnostic — no need to hand-roll occupancy updates or grep `execute_move`, just
call it directly with the two `BaseCharacter` instances. Do NOT call
`execute_move` for the swap (it would path/capture) — `swap_characters` is the
correct, already-proven primitive.

### 4.5 Queen — Command (`needs_target: true`)

> base: "A chosen ally in this queen's line of sight may immediately make a free move."
> mid: "Any chosen ally may immediately make a free move."
> upgraded: same as mid (2 uses via abilities.json).

Tier dicts: `{"los": true}` / `{"los": false}` / `{"los": false}`.

**Correction (was wrong in an earlier draft of this plan):** this does NOT mirror
Reposition. Reposition is a single-shot targeted ability that resolves the move
itself inside its own execution and spends an *ability* use
(`_do_reposition(target)` in `knight.gd`) — it never grants a separate,
player-driven free move, so there is nothing to "mirror" there.

**Decision: build the restricted version, not the shared-pool one.** The whole
point of `needs_target: true` here is choosing *which* ally benefits — a
shared-pool `add_bonus_move()` would make that targeting step pointless (any
piece could spend the bonus move regardless of who got picked), which
contradicts the ability's own text ("*a chosen* ally... may make a free move").
So:

- Add `var free_move_character: BaseCharacter = null` to `BattleController`.
- Command's execution (after target selection): set
  `battle_controller.free_move_character = target_char`.
- At both `consume_move()` call sites in `Scripts/map_behaviour.gd` (`:234` and
  `:287`), guard the call: skip `battle_controller.consume_move()` (and clear
  `free_move_character` back to `null`) when the piece that just moved
  `== battle_controller.free_move_character`; otherwise consume as normal.
  Simplest shape: a new `BattleController.consume_move_for(character)` helper
  that both call sites use instead of calling `consume_move()` directly —
  `if character == free_move_character: free_move_character = null; return`
  else falls through to the existing `consume_move()` body. This keeps the
  "skip once" logic in one place instead of duplicating the check at both
  `map_behaviour.gd` sites.
- Clear `free_move_character = null` in `start_player_turn()` too, so an unused
  free move can't leak into the following turn.
- `add_bonus_move()` stays untouched (still used by the `extra_move` item) —
  Command does not call it.

### 4.6 King — Royal Decree (`needs_target: false`)

> base: "Allies within 3x3 of the king cannot be captured until your next turn."
> mid: plus-shape · upgraded: "No ally can be captured until your next turn."

Tier dicts: `{"shape":"square","radius":1}` / `{"shape":"plus"}` / `{"all": true}`.
Execute: set `is_capture_immune = true` on each affected ally — the capture check
(`base_character.gd:235`) and expiry (`BattleController._clear_expired_evade()`)
already exist and are generic. Verify `_clear_expired_evade` clears ALL pieces'
flags, not just knights; generalize if needed.

---

## 5. Engine-side changes (battle code)

### 5.1 `base_character.gd`

- Replace `ability2_unlocked: bool` with `var unlocked_slots: Array[int] = [1]`
  plus `func is_slot_unlocked(slot: int) -> bool`. Update `get_ability_info`'s
  `locked` line to `slot >= 2 and not is_slot_unlocked(slot)`, and remove the
  `unlock_cost`/`level_up_cost` keys from the returned dict.
  **Confirmed reader that will break silently if not updated in the same
  commit:** `battle_ui.gd:850` does
  `character.get_ability_info(2).get("unlock_cost", 1)` to build the
  slot-2-locked message — once the key is gone this always falls back to `1`
  regardless of the real cost. Repoint it (and the new slot-3 locked message
  from §5.3) at `SkillTreeData.get_node_def(piece_type, "a2_unlock")["cost"]`
  / `"a3_unlock"` respectively.
- `ability_levels` becomes `{1:1, 2:1, 3:1}`.
- `_load_persistent_upgrades()`: read via the new PlayerManager getters
  (`get_ability_level`, `is_slot_unlocked` per slot 1–3), and store
  `var passives: Array = player_manager.get_passive_effects(strName)`.
  Then apply immediate ones: `move_range += amount` for each `move_range` effect.
  Add helpers:
  ```gdscript
  func has_passive(effect_type: String) -> bool
  func get_passive(effect_type: String) -> Dictionary   # {} if none
  func has_flag(flag_name: String) -> bool              # flag-type passives
  ```
- `_ability_uses_max(slot)`: after the existing match, add
  `+ amount` for each `extra_uses` passive with matching `slot`.
- `apply_curse()`: first line — `if has_passive("curse_immune"): return` (also
  skip spawning the marker).
- End of `execute_move` (the point where the move is finalized): if
  `has_passive("move_reveal")`, `grid_manager.reveal_area(...)` around the
  landing tile with the passive's radius.

### 5.2 `BattleController.gd`

- Battle start (where pieces are placed / first turn begins): for every allied
  piece with a `battle_start_reveal` passive, reveal the square around it.
- `free_move_character` support for Queen's Command (§4.5).
- Check `_clear_expired_evade()` covers `is_capture_immune` set by Royal Decree.

### 5.3 `battle_ui.gd` + its scene, keybinds

- Scene: duplicate the `Ability2*` node block (Name/Level/Uses/Desc/Button/Body/Locked)
  as `Ability3*` with unique names (`%Ability3Name` etc.).
- Script: add the `@onready` refs, wire `ability3_button` to
  `_on_ability_pressed.bind(3)`, extend `_clear_ability_rows()` and the refresh
  code that fills rows from `get_ability_info(slot)` to loop slots 1–3.
  Locked text for slot 3: "Unlock the third ability in this piece's skill tree at a rest."
- `project.godot`: add input action `ability_3` (key `3`), handle it in
  `battle_ui._input` like the other two.
- Note: `get_ability_defs()` is empty for enemies (curse display path at
  `battle_ui.gd:760` onward) — the slot loop must tolerate defs.size() < 3, which
  it does if driven by `defs.size()` / `get_ability_info` returning `{}`.

### 5.4 Enemy/inspection safety

`get_ability_info(slot)` already returns `{}` for out-of-range slots — keep that,
it's what protects enemy pieces and older content from the new slot 3.

---

## 6. Campfire panel rewrite (`Scenes/Menu/CampfireUpgradePanel.gd` + `.tscn`)

Keep: CanvasLayer, `%ItemsLabel`, `%TypeList`, `%BackButton`, `_owned_types()`,
`items_changed` refresh, ESC-to-close. Replace `_build_type_row` internals:

For each owned type, build a row: piece icon (48×48, same as now) + **4 columns**
(HBox of VBoxes), one per track:

1. "ABILITY 1 — <name>": nodes `a1_lv2`, `a1_lv3`
2. "ABILITY 2 — <name>": nodes `a2_unlock`, `a2_lv2`, `a2_lv3`
3. "ABILITY 3 — <name>": nodes `a3_unlock`, `a3_lv2`, `a3_lv3`
   (ability names from `_get_ability_defs(piece_type)` — keep the existing
   instantiate-and-free trick)
4. "PERKS": nodes `p1`, then `spec_a` / `spec_b`

Each node renders as one Button, top-to-bottom in tree order. Button state logic:

```gdscript
if player_manager.has_tree_node(type, id):        text = "✔ " + name;         disabled = true
elif excluded (any `excludes` node owned):        text = name + " (path closed)"; disabled = true
elif requirements not all owned:                  text = "🔒 " + name;         disabled = true
elif upgrade_items < cost:                        text = "%s (%d)" % [name, cost]; disabled = true
else:                                             text = "%s (%d)" % [name, cost]; disabled = false
                                                  pressed → player_manager.try_buy_node(type, id)
```

`tooltip_text` = node `desc`; for `a*_lv*` nodes append the ability tier desc it
unlocks (from ABILITY_DEFS `mid`/`upgraded`), for `a3_unlock` append the `base` desc.
`try_buy_node` emits `items_changed`, which already triggers `_refresh()` — no
extra wiring.

Header row unchanged (`UPGRADE ITEMS: x%d`). If width is a problem, wrap
`%TypeList` in a ScrollContainer.

---

## 7. Tests (`team-berry-game/tests/`, run with `run_all.sh`)

Remember the harness gotchas (no `tests/README` exists — see `run_all.sh`'s own
comments and `FIX_PROGRESS.md`): `MainLoop._process()` returning **true = stop**,
and zero-errors ≠ pass — assert explicitly.

1. **Update** `tests/smoke/smoke_upgrade_panel.gd`: panel builds with the new
   node buttons; buying a purchasable node deducts items and flips the button to owned.
2. **New** `tests/unit/test_skill_tree.gd`:
   - `skill_trees.json` loads; every piece type has all 11 skeleton node ids;
     every `requires`/`excludes` id exists in the same tree; every `effect.type`
     is in the §2.1 vocabulary; every `a3_*`/new ability id exists in `abilities.json`.
   - purchase rules: cannot buy without requirements / without items / twice;
     buying `spec_a` permanently locks `spec_b`.
   - derived state: buying `a1_lv2` ⇒ `get_ability_level(type,1) == 2`;
     `a3_unlock` ⇒ `is_slot_unlocked(type,3)`; passives list contents.
3. **New** `tests/unit/test_new_abilities.gd` (or extend existing ability tests —
   check what's already there and follow its pattern): one happy-path per new
   ability. Priority order if time is short: `royal_decree` (capture immunity
   set + expires), `sanctify` (curse cleared), `castling` (positions + occupancy
   swapped), `ambush` (knight lands on target), `command` (move doesn't consume
   turn), `promotion` (pawn gone without entering fallen list, temp piece present).
4. Headless sanity: `~/.local/bin/godot4` is available for headless scene/script
   checks after scene edits (battle UI + campfire panel).

---

## 8. Milestones (each = one commit, game runs after each)

1. **Data + purchase logic.** `skill_trees.json`, `SkillTreeData` autoload,
   `PlayerManager` node struct + buy + derived getters + debug_max update,
   `test_skill_tree.gd`. (Old panel temporarily broken is NOT acceptable — do
   milestone 2 in the same commit if needed, or keep old methods as thin shims
   over `try_buy_node` until milestone 5.)
   **STATUS: DONE** (branch `features/skill-trees`). Notes for the next
   milestone: legacy shims live in PlayerManager under "ZAČASNE LEGACY ŠIME"
   (`get_piece_upgrades` is now a DERIVED read-only view, `try_unlock_slot2`/
   `try_level_up_ability` delegate to `try_buy_node`; remove all three in M5).
   The §4 `abilities.json` entries were already added in this milestone (skip
   that step in M4). Unit suite 890/890 green + `smoke_upgrade_panel` passes.
2. **BaseCharacter generalization.** 3-slot `ability_levels`, `unlocked_slots`,
   passive loading, `extra_uses` in `_ability_uses_max`, curse immunity,
   `move_range`/`move_reveal` hooks; `battle_start_reveal` in BattleController.
   **STATUS: DONE.** Deviations/notes:
   - `move_range` passives are applied idempotently: `_load_persistent_upgrades`
     captures the scene's base value in `_base_move_range` on first call and
     recomputes `move_range = base + bonuses` (plain `+=` per the plan text
     would stack on any re-registration of the same instance).
   - battle_ui.gd had a SECOND reader beyond the `unlock_cost` one flagged in
     §5.1: `character.ability2_unlocked` at the top of `_show_abilities` —
     repointed to `character.is_slot_unlocked(2)` in the same commit.
   - `battle_start_reveal` hook lives in `start_player_turn()` inside a
     `turn_count == 1` block (same spot as the bounty/courier first-turn
     logic), NOT `initialize_battle()` — pieces are only on the board after
     the placement phase.
   - §5.2 checklist item verified, no change needed: `_clear_expired_evade()`
     already loops ALL allied pieces (not just knights), so Royal Decree's
     `is_capture_immune` will expire correctly in M4.
   - Tests: unit suite 893/893 green; `smoke_upgrade_panel` passes.
     `smoke_ability_ui_pipeline` fails PRE-EXISTINGLY on this branch (6
     Queen.Lure/King.Cleanse/King.Heal assertions — verified byte-identical
     with M2 stashed, so unrelated to skill trees; investigate separately).
     `smoke_spyglass` is flaky (failed one run, passed the next, both
     unrelated to this diff).
3. **Battle UI slot 3.** Scene block, script wiring, `ability_3` keybind.
   **STATUS: DONE.** Deviations/notes:
   - `ability_3` keybind is **`E`** (physical_keycode 69), not literal digit
     `3` as the plan text said — digit `3` is already bound to `piece_slot_3`
     (select roster slot 3 via `_unhandled_input`'s `piece_slot_%d` loop in
     `battle_ui.gd`), so reusing it for `ability_3` would silently shadow that
     shortcut any time the third ability button is enabled. `E` sits between
     the existing `ability_1`=D / `ability_2`=F bindings (D/E/F are
     consecutive `KEY_*` codes), consistent with the S/D/F/G home-row layout
     already used for select/ability1/ability2/toggle-items.
   - Scene: added an `HSep3` separator before `Ability3Body` (not in the
     plan's literal Name/Level/Uses/Desc/Button/Body/Locked list) so ability 2
     and 3 don't visually run together, matching `HSep2`'s role before
     `Ability2Body`.
   - Script: slots 2 and 3 share the body/locked pattern (unlike slot 1,
     which has no locked state), so `_show_abilities()`/`_clear_ability_rows()`
     handle them via a small `for slot in [2, 3]` loop over a node-ref lookup
     dict, rather than a literal "loop slots 1–3" — slot 1 stays its own
     explicit block since it has no body/locked wrapper to loop over. Mirrors
     the `for slot in [2, 3]` / `for slot in [1, 2, 3]` pattern
     `base_character.gd` already established in M2.
   - Slot 3's locked text is the single fixed string from this plan ("Unlock
     the third ability in this piece's skill tree at a rest.") used in both
     `_clear_ability_rows()` and `_show_abilities()` — unlike slot 2, which
     shows a generic default in the cleared state but a dynamic cost-derived
     message in `_show_abilities()`. Slot 3's cost isn't in the string at all
     per the plan's own wording, so there was no dynamic part to add.
   - Correction to the M2 note above: re-ran `smoke_ability_ui_pipeline` on
     this milestone's diff and, separately, on the stashed M2 baseline —
     byte-identical failure set both times, confirming it's still pre-existing
     and unrelated to skill-tree changes. But the actual failing assertions
     are **Knight.Reposition, Bishop.Traps, Rook.Reinforce, Queen.Lure,
     King.Cleanse, King.Heal** (6 total) — broader than M2's note ("6
     Queen.Lure/King.Cleanse/King.Heal assertions"), which undercounted which
     abilities were affected while getting the total right. Investigate
     separately, per M2's note.
   - Tests: unit suite 894/894 green (one higher than M2's recorded 893 —
     count is stable across repeated runs on this branch; likely M2's note was
     off by one rather than a real change). `smoke_battle` (scene-load sanity
     check on the edited `battle_ui.tscn`, since no smoke test yet drives
     slot 3 specifically — that lands with M4's abilities) passes cleanly.
4. **New abilities.** Suggested order: royal_decree → sanctify → ambush →
   castling → command → promotion (easiest to hardest; promotion last since the
   temp-ally + not-a-death handling has the most edge cases). Smoke/unit test each.
   **STATUS: FIRST HALF DONE** (royal_decree, sanctify, ambush; branch
   `features/skill-trees`, 3 separate commits). castling/command/promotion are
   still open (next session). Deviations/notes:
   - Tests (`tests/unit/test_new_abilities.gd`, new file, built up across the
     3 commits): pieces are instantiated directly (`KingScript.new()` etc.,
     same `.new()`-without-scene-tree pattern as
     `test_battle_controller_path.gd`) with `grid_manager`/`grid_pos` wired
     manually - `_execute_ability(id, target)` is called directly, bypassing
     `activate_ability`'s `battle_controller`/`player_manager` gate (neither
     is initialized off-tree). This only exercises the ability-execution
     logic, not targeting/UI - `get_ability_targets` for the new abilities
     stays smoke-test-only coverage (existing repo convention: no unit test
     touches `get_ability_targets` for any piece).
   - **Ambush's `execute_move` needed a scene-tree workaround:**
     `BaseCharacter.slide_to()` reads `settings_manager.reduced_motion` to
     decide between an instant jump and `create_tween()` - the latter errors
     on a node that was never added to the tree. The test temporarily flips
     the real `SettingsManager` autoload's `reduced_motion` to `true` around
     the call (save/restore, same temporary-global-mutation pattern
     `test_curses.gd` already uses for `CurseData._curses`), rather than
     stubbing a fake settings object.
   - Ambush's own validation is intentionally minimal (`_do_ambush` only
     re-checks `is_occupied`, not curse-fog or boundary) - it trusts
     `get_ability_targets(3)` already filtered the click, matching the
     existing "UI already filtered it" convention `_do_reposition`/
     `_do_longshot` use (neither re-validates against their own targets list
     either).
   - Royal Decree's expiry needed no new code: confirmed (again, by direct
     `BattleController._clear_expired_evade()` call in the test) that it's
     still ally-loop-only per M2's note - unaffected by M3/M4.
   - Tests: unit suite 914/914 green (16 new asserts across 7 test methods
     added incrementally, 1 per commit's worth). `smoke_ability_ui_pipeline`
     still fails exactly the same pre-existing 6 assertions (Knight.Reposition,
     Bishop.Traps, Rook.Reinforce, Queen.Lure, King.Cleanse, King.Heal) after
     each of the 3 commits - no new failures. `smoke_abilities` passes.
5. **Campfire panel rewrite** + smoke test update; delete the old shim methods.
6. **Balance pass** over costs and uses; update this file's numbers if changed.

## 9. Out of scope (explicitly)

- No respec / refund mechanic.
- No cross-piece or global tree; trees are strictly per piece type.
- No new art; reuse existing icons and Button UI.
- Enemy pieces get no skill trees (their curses are a separate system).

# Battle UI ability panel redesign

**STATUS: DONE (steps 1-3 of Verification), manual pass (step 4) deferred to
Miha.** Implemented on `features/improved-battle-ui` (branched from `develop`).
See "Deviations from plan" at the end for the handful of places the
implementation differs from what's written below.

## Context

The battle UI's detail panel (right-hand "red area" when a piece is selected)
currently shows a permanent full-sentence explanation ("Use 1 upgrade item at a
rest to unlock the second ability.") any time ability slot 2 or 3 is locked, and a
permanent word-wrapped description label under every unlocked ability. Neither is
gated behind any interaction — they're just always there.

This causes two problems:
1. The locked-slot text and the always-on description text are visual clutter and
   spoil ability info before it's earned.
2. Worse, `DetailPanel` has no fixed minimum size anywhere in its ancestry, so its
   height is purely the sum of whichever child labels happen to be visible/wrapped
   at the moment. Every time locked-state or description-wrap-length changes, the
   whole side panel reflows — pushing `BudgetRow`, `TurnLabel`, and critically the
   **END TURN button** up or down, sometimes off past the visible area.

The fix redesigns the panel per Miha's sketch: every ability slot always renders as
a compact fixed-shape row (icon + name + level + uses), locked or not, so nothing
ever toggles visibility or changes height. Ability descriptions and unlock-reason
text move out of the inline layout entirely into a floating hover/click bubble
(fixed width, word-wrapped, clamped to stay on-screen) — modeled on the campfire
panel's tooltip-on-hover idea, but built as a real custom widget since the campfire
panel's tooltip turns out to be Godot's bare `tooltip_text` (no wrap, no width
control, no screen-edge protection — nothing like that exists anywhere in this
codebase yet, confirmed by a repo-wide grep for tooltip/hover/bubble/PopupPanel).

Confirmed decisions (from clarifying questions with Miha, don't re-litigate):
- Locked-slot text appears **on click** of that specific locked row (not on hover,
  and not by merely selecting the piece as today).
- Icons: **one shared placeholder texture** reused by all 18 abilities, following
  this repo's existing ImageMagick-generated-PNG convention (see `TEMP_SPRITES.md`).
- Locked rows **hide the real ability name** too (show "???"), not just level/uses.

## Current state (verified directly against the files, 2026-07-19)

`team-berry-game/Scripts/Battle/battle_ui.gd` (1070 lines) /
`team-berry-game/Scenes/Battle/battle_ui.tscn` (412 lines). Inside
`DetailPanel > DetailMargin > DetailHBox > DetailVBox`:
- Slot 1: `Ability1Header` (HBox: Name/Level/Uses) + `Ability1Desc` (always-visible
  wrapped Label) + `Ability1Button`. No lock state.
- Slots 2/3: `AbilityXBody` (VBox: Header + Desc + Button) **or** `AbilityXLocked`
  (Label, sibling of Body, not nested) — visibility toggled as complementary bools
  in `_show_abilities()` (`battle_ui.gd:841-889`) and `_clear_ability_rows()`
  (`:817-828`).
- No icon/texture infrastructure exists for abilities anywhere (no `icon` field on
  any ability def, no TextureRect for abilities in the scene).
- `DetailPanel` (`PanelContainer`, `size_flags_vertical=3`) has **no
  `custom_minimum_size`** anywhere in its subtree — height is 100% content-driven,
  and `VBoxContainer` skips invisible children in min-size math, which is the
  direct cause of the reflow bug.
- `_show_enemy()` (`:777-790`) repurposes `ability1_name`/`ability1_desc` to show a
  cursed enemy's curse name/description (since enemies have no real abilities) —
  this reuse point must be updated in the same change or it'll throw on a deleted
  node reference.
- `SKILL_TREE_PLAN.md:365-421` already documents that slot 3's locked text *should*
  look up its real cost from `SkillTreeData.get_node_def(type, "a3_unlock")["cost"]`
  the same way slot 2 does — today it's a hardcoded string with no cost. Today,
  `Data/skill_trees.json` has `a2_unlock.cost=1` / `a3_unlock.cost=2` uniformly
  across all 6 piece types (verified), but the lookup must stay dynamic per-type
  (don't hardcode "1"/"2" — read them, since costs may change in a future balance
  pass, e.g. `SKILL_TREE_PLAN.md`'s own still-open M6).
- No test references any of the nodes/vars being removed (`Ability2Locked`,
  `Ability3Locked`, `Ability1Desc`, `Ability2Desc`, `Ability3Desc`, `Ability2Body`,
  `Ability3Body` — grepped repo-wide, zero hits outside `battle_ui.gd` itself).

## Approach

### 1. Placeholder icon asset

Generate one new file, `team-berry-game/Assets/Sprites/ability_placeholder.png`,
using this repo's established ImageMagick placeholder convention (see the
`item_*.png` rows in `TEMP_SPRITES.md` for examples/style — 256×256, solid
background, short glyph, matching border color). Example command:

```bash
convert -size 256x256 xc:'#2a4a7a' \
	-gravity center -pointsize 160 -fill '#dce8fa' -annotate +0+0 '?' \
	-fill none -stroke '#dce8fa' -strokewidth 8 -draw 'rectangle 4,4 251,251' \
	team-berry-game/Assets/Sprites/ability_placeholder.png
```

Add a row for it to `TEMP_SPRITES.md` (same table format as the existing rows).
Don't hand-create the `.png.import` file — Godot generates it on next
editor/headless launch, same as every other sprite in this repo.

### 2. Scene restructuring (`battle_ui.tscn`)

Replace the `Ability1Header`+`Ability1Desc` / `Ability2Body`+`Ability2Locked` /
`Ability3Body`+`Ability3Locked` structure (currently lines 226-354) with three
identical, always-visible `AbilityXRow` blocks, one per slot, as direct children
of `DetailVBox` (same place the old blocks lived, same relative order, `HSep1`/
`HSep2`/`HSep3` unchanged in between):

```
AbilityXRow (HBoxContainer, unique_name_in_owner, mouse_filter=0 [STOP])
├─ AbilityXIcon (TextureRect, unique_name_in_owner, custom_minimum_size≈20x20,
│                mouse_filter=2 [IGNORE], expand_mode=1, stretch_mode=5
│                — same expand/stretch values as the existing Portrait node)
├─ AbilityXName (Label, unique_name_in_owner, mouse_filter=2, size_flags_horizontal=3)
├─ AbilityXLevel (Label, unique_name_in_owner, mouse_filter=2)
└─ AbilityXUses (Label, unique_name_in_owner, mouse_filter=2)
AbilityXButton (Button, unchanged, sibling below the row, same as today)
```

`mouse_filter=STOP` on the row + `IGNORE` on its children is the same
icon+label-row-is-clickable idiom already used by `_build_item_row()`
(`battle_ui.gd:982-1015`) and `PieceIcon` (`Scripts/Battle/piece_icon.gd`) — reuse
it, don't invent a new pattern. 7 nodes are deleted total (`Ability1Desc`,
`Ability2Desc`, `Ability2Body`, `Ability2Locked`, `Ability3Desc`, `Ability3Body`,
`Ability3Locked`); the kept Name/Level/Uses/Button nodes for slots 2/3 just get
reparented directly into `DetailVBox` instead of living inside the (deleted) Body
wrapper. No `texture=` needs setting in the scene for the icons (matches
`Portrait`, which is also script-populated only).

Add one new overlay node, appended at the very end of the scene (after the
existing `DragGhost` node, as a sibling of `SidePanel` under `Root` — **not**
inside `SidePanel`/`DetailPanel`, both of which are deliberately opaque
`StyleBoxFlat`s that would otherwise clip it, and Godot draws Control siblings in
tree order, so it must come after everything else to render on top of it all):

```
AbilityBubble (PanelContainer, unique_name_in_owner, visible=false,
               layout_mode=0 [manually positioned, like DragGhost],
               mouse_filter=2 [IGNORE], theme_override_styles/panel reuses the
               existing StyleBoxFlat_inner sub-resource already used by
               DetailPanel/RosterPanel/etc. — no new sub-resource needed)
└─ AbilityBubbleLabel (Label, unique_name_in_owner, custom_minimum_size=(260,0),
                        autowrap_mode=3 [AUTOWRAP_WORD_SMART, same value the
                        deleted AbilityXDesc labels used], mouse_filter=2)
```

### 3. Script changes (`battle_ui.gd`)

- Update the `@onready` block (currently lines 27-47): drop the 7 vars for deleted
  nodes (`ability1_desc`, `ability2_desc`, `ability2_body`, `ability2_locked`,
  `ability3_desc`, `ability3_body`, `ability3_locked`), add
  `abilityX_row`/`abilityX_icon` per slot (6 new vars), add
  `ability_bubble`/`ability_bubble_label` (2 new vars).
- New consts: `ABILITY_ICON_PLACEHOLDER` (preload the new PNG),
  `ABILITY_ICON_LOCKED_TINT` (reuse `PieceIcon.COLOR_DEAD`'s existing
  `Color(0.35,0.35,0.35)` for visual consistency with how "unavailable" already
  looks elsewhere in this UI), `ABILITY_ICON_UNLOCKED_TINT := Color(1,1,1)`,
  `ABILITY_BUBBLE_WIDTH := 260.0`, `ABILITY_BUBBLE_MARGIN := 8.0`.
- New `var _slot_bubble_state: Dictionary` (slot int → `{"locked": bool, "text":
  String}`, default all 3 slots to `{"locked": true, "text": ""}`), populated by
  `_show_abilities()`/`_clear_ability_rows()`/`_show_enemy()`, read only by the
  hover/click handlers below — this is what lets the enemy-curse repurposing of
  slot 1 work through the same generic mechanism with no special-casing in the
  handlers themselves.
- **Unify `_show_abilities()` into one `for slot in [1, 2, 3]` loop** (currently
  slot 1 is handled separately, lines 849-854, from the `for slot in [2, 3]` loop,
  lines 866-888). This is a net simplification, not just a style choice:
  `is_slot_unlocked(1)` is unconditionally true (`base_character.gd`), so the
  loop's locked-branch structurally never fires for slot 1 — no special case
  needed. Build a small `_ability_slot_widgets()` helper returning
  `{1: {...}, 2: {...}, 3: {...}}` (icon/name/level/uses/button refs per slot),
  same pattern as the existing `slot_widgets` dict at line 860 but covering all 3
  slots and adding `icon`.
  - Locked branch: icon = placeholder tinted gray, name = `"???"`, level/uses =
    `""`, button disabled, `_slot_bubble_state[slot]` set to the unlock-cost
    message — looked up dynamically via
    `skill_tree_data.get_node_def(character.strName, "aN_unlock").get("cost", 1)`
    for **both** slot 2 and slot 3 (fixing slot 3's currently-hardcoded, cost-less
    string in the process, per `SKILL_TREE_PLAN.md`'s own documented intent).
    Suggested wording, mirroring the existing slot-2 sentence exactly:
    `"Use %d upgrade item%s at a rest to unlock the %s ability." % [cost, "" if
    cost==1 else "s", "second"/"third"]`.
  - Unlocked branch: icon = placeholder normal tint, real name/level/uses (same
    `get_ability_info(slot)` calls as today), `_slot_bubble_state[slot]` set to
    the ability's `desc` text (`info.get("desc", "")`).
- `_clear_ability_rows()` (currently lines 817-828): loop all 3 slots to a neutral
  `"-"` state (dimmed icon, no name/level/uses, button disabled), and call the new
  `_hide_ability_bubble()` at the end.
- `_show_character()` (currently lines 753-769): add one line, `_hide_ability_bubble()`
  (anywhere before `_show_abilities(character)` is fine), so switching pieces never
  leaves a stale bubble floating over the newly-shown piece's panel.
- `_show_enemy()` (currently lines 777-790): **required fix, not optional** —
  replace the `ability1_desc.text = character.curse.description()` line (which
  will reference a deleted node and throw at runtime) with setting
  `_slot_bubble_state[1] = {"locked": false, "text": character.curse.description()}`,
  so hovering the repurposed slot-1 row shows the curse's description in the
  bubble exactly like a normal ability would. Also make sure `_clear_ability_rows()`
  (already called at the top of `_show_enemy()`) runs before this override, same
  as today.
- New functions:
  - `_show_ability_bubble(anchor_row: Control, text: String) -> void`: if `text`
    is empty, just call `_hide_ability_bubble()` and return. Otherwise: set
    `ability_bubble_label.text = text`, `ability_bubble.visible = true`, then call
    `ability_bubble.reset_size()` (**required** — a manually-positioned
    `PanelContainer` in `layout_mode=0` doesn't auto-resize per-frame like a
    normal container child would, so without this call it keeps a stale size from
    whatever the previous call's text length produced). Then compute position from
    `anchor_row.get_global_rect()` and `get_viewport().get_visible_rect().size`:
    prefer opening left+up from the row (since `SidePanel` occupies the right
    ~42% of the screen, `anchor_left=0.58`, so there's more open room to the left
    toward the board than further right), i.e. desired position ≈
    `row_rect.position - Vector2(bubble_size.x, bubble_size.y) -
    Vector2(ABILITY_BUBBLE_MARGIN, ABILITY_BUBBLE_MARGIN)`, then **clamp** both
    x and y with `clampf(value, ABILITY_BUBBLE_MARGIN, viewport_size.{x,y} -
    bubble_size.{x,y} - ABILITY_BUBBLE_MARGIN)` so the bubble can never render
    off-screen regardless of which row triggered it or where on screen that row
    is. Finally set `ability_bubble.global_position = <clamped position>`.
  - `_hide_ability_bubble() -> void`: `ability_bubble.visible = false`.
  - `_on_ability_row_mouse_entered(slot: int, row: Control) -> void`: read
    `_slot_bubble_state.get(slot, {})`; if `locked` is true, do nothing (hover has
    no effect on locked slots, per the confirmed click-only decision); else if
    `text` is non-empty, call `_show_ability_bubble(row, text)`.
  - `_on_ability_row_gui_input(event: InputEvent, slot: int, row: Control) -> void`:
    if `event` isn't a pressed left-click `InputEventMouseButton`, return. Read
    `_slot_bubble_state.get(slot, {})`; if `locked` is false, do nothing (click has
    no effect on unlocked slots); else if `text` is non-empty, call
    `_show_ability_bubble(row, text)`.
  - In `_ready()` (after the existing `ability3_button.pressed.connect(...)` line),
    wire per row: `abilityX_row.mouse_entered.connect(_on_ability_row_mouse_entered.bind(X, abilityX_row))`,
    `abilityX_row.mouse_exited.connect(_hide_ability_bubble)`,
    `abilityX_row.gui_input.connect(_on_ability_row_gui_input.bind(X, abilityX_row))`,
    for X in 1/2/3 (9 new connections total).

### 4. `DetailPanel` sizing — no hardcoded floor needed

After the above, `DetailVBox`'s content is exclusively fixed-height, always-visible
children (2 single-line status labels, 3 separators, 3 icon+label rows, 3 buttons)
— nothing left in the subtree toggles visibility or wraps to a variable number of
lines, since both variable-content label types (`AbilityXDesc`, `AbilityXLocked`)
are gone, replaced by the bubble overlay which sits outside this container
entirely. `DetailPanel`'s minimum height therefore becomes structurally constant
for every reachable state (any character, any lock combination, dead/benched/
enemy-with-or-without-curse) — this removes the root cause rather than papering
over it with a hardcoded `custom_minimum_size`, which would risk silently going
stale if a future change shrinks the natural content height. **Do not add an
explicit min-size** to `DetailPanel`/`DetailVBox` — it isn't needed and would be
redundant given the structural guarantee above.

## Critical files

- `team-berry-game/Scenes/Battle/battle_ui.tscn` — scene restructuring (§2)
- `team-berry-game/Scripts/Battle/battle_ui.gd` — all script logic (§3)
- `team-berry-game/Assets/Sprites/ability_placeholder.png` — new placeholder icon (§1)
- `TEMP_SPRITES.md` — new tracking row for the placeholder
- Reference only (read, don't need to change): `Scripts/CharacterPieces/base_character.gd`
  (`get_ability_info`, `is_slot_unlocked`), `Data/skill_trees.json` (unlock costs),
  `Scripts/Battle/piece_icon.gd` (the mouse_filter STOP/IGNORE idiom + `COLOR_DEAD`
  constant being reused), `Scenes/Menu/CampfireUpgradePanel.gd` (the hover-tooltip
  idea this generalizes, though the actual bubble implementation is new, not
  copied — the campfire panel's tooltip is just bare `tooltip_text` with no
  wrap/width/clamp behavior to reuse)

## Verification

1. Run `team-berry-game/tests/run_all.sh` **before** changing anything and note the
   baseline (expect the 6 known pre-existing `smoke_ability_ui_pipeline` failures —
   Knight.Reposition/Bishop.Traps/Rook.Reinforce/Queen.Lure/King.Cleanse/King.Heal —
   plus general awareness that `smoke_spyglass`/`smoke_ability_ui_pipeline` are
   known-flaky under full-suite load; don't chase pre-existing flakiness).
2. After changes, targeted headless checks via `~/.local/bin/godot4` (run from repo
   root, `--path team-berry-game`):
   - `smoke_battle.gd` — catches any scene/node-name mistake from the restructuring.
   - `smoke_ability_ui_pipeline.gd` — exercises all 3 slots across all 6 piece
     types including unlocked slot 2/3 (via `debug_max_all_upgrades()`); confirm
     its failure count is unchanged from baseline (still exactly those same 6, not
     more — if it's more, that's a real regression, investigate before proceeding).
   - `smoke_inspect.gd` — exercises the `_show_enemy()` curse-repurposing edit
     (asserts on `status_value.text`, unaffected by this change, but exercises the
     exact code path §3's `_show_enemy()` fix touches).
3. Full `run_all.sh`, confirm no new failures beyond baseline.
4. Manual in-game pass (launch the actual game — headless tests can't see pixel
   layout/wrapping):
   - Select a piece with slot 2/3 locked: both render as a small fixed row (dimmed
     icon, "???", blank level/uses), "Use Ability" button visible-but-greyed (not
     hidden).
   - Click a locked row: bubble shows the real unlock-cost text for that piece
     type; confirm slot 3 now shows a real looked-up cost, not a hardcoded string
     (e.g. temporarily edit one piece type's `a3_unlock.cost` in
     `Data/skill_trees.json` and confirm only that piece's bubble text changes).
   - Hover an unlocked row: bubble shows the ability's real description, wrapped
     at the fixed width, never clipped/cut off.
   - Confirm the bubble never renders partially off-screen from any row position.
   - Switch between several pieces with different lock states, and between
     friendly/dead/benched/enemy-with-curse/enemy-without-curse views: confirm
     `DetailPanel`'s height never changes and `BudgetRow`/`TurnLabel`/`ActionButton`
     (END TURN) never move or disappear.
   - Confirm switching pieces while a bubble is open dismisses it (no stale bubble
     left floating over the newly-shown piece's panel).
   - Confirm END TURN stays clickable throughout everything above.

## Deviations from plan

1. **Test baseline gotcha, not a code deviation**: running the smoke scripts
   directly (`godot4 --headless --script ... --quit-after N`) requires the
   exact `--quit-after` value `run_all.sh` uses per test, or the process never
   self-quits (it just hangs). Confirmed baseline this way instead:
   `smoke_ability_ui_pipeline.gd --quit-after 8` reproduced exactly the 6
   documented pre-existing failures (Knight.Reposition/Bishop.Traps/
   Rook.Reinforce/Queen.Lure/King.Cleanse/King.Heal), matching this doc's
   step-1 expectation.
2. **New-asset import gotcha, not a code deviation**: after adding
   `ability_placeholder.png`, `preload()` in `battle_ui.gd` failed ("has no
   resource loaders") until an explicit `godot4 --headless --import --path .`
   was run. `run_all.sh` only auto-imports when `.godot/` doesn't exist yet,
   which it already did here, so the script's own import step was skipped.
   Anyone pulling this branch fresh needs one `--import` pass (or an editor
   launch) before the new PNG's `.import` file exists — same as any other
   newly-added sprite in this repo, just calling it out since it bit the
   verification pass once.
3. **`ABILITY_BUBBLE_WIDTH` applied from script, not left as a
   scene-only value**: rather than letting the const sit unused next to the
   scene's hardcoded `custom_minimum_size = Vector2(260, 0)` on
   `AbilityBubbleLabel`, `_ready()` now does
   `ability_bubble_label.custom_minimum_size.x = ABILITY_BUBBLE_WIDTH` so
   there's a single source of truth for the bubble width instead of two
   `260`s that could drift apart.
4. **Enemy-curse row (slot 1) keeps a dimmed icon**: `_show_enemy()` overrides
   `ability1_name.text` and `_slot_bubble_state[1]` for the curse case, but
   `_clear_ability_rows()` (called just before it, per plan) already tinted
   `ability1_icon` to the locked/gray tint and that's never reset to the
   unlocked tint for this repurposed row. Hover still works (bubble state is
   `locked: false`), the icon is just visually dim. Plan didn't call for an
   icon-tint override here ("no special-casing in the handlers"), so left as
   specified — flagging in case the dim icon on a hoverable curse row reads
   as a bug during the manual pass.
5. **Manual in-game verification (step 4) not run by Claude**: this sandbox
   has a reachable X display but no click/hover automation (`xdotool`/
   `ydotool` not installed), so the actual pixel/interaction checklist above
   needs a human pass. Steps 1-3 (baseline, targeted smoke tests, full
   `run_all.sh`) all ran clean with zero new failures beyond the same 6
   pre-existing ones. Miha is doing the manual pass himself.

## Post-implementation revision (per Miha's sketch, after his manual pass)

Miha tested the above and liked it, but asked for two follow-up changes to each
ability row (same overall row width, just restyled):

- Icon grows from 20x20 to 64x64, and the "Use Ability" button moves from a
  separate row below to sit next to the icon, under the name/level/uses line
  — i.e. `AbilityXRow` now contains `AbilityXIcon` + a new `AbilityXInfo`
  VBox (`AbilityXHeader` HBox with Name/Level/Uses, then `AbilityXButton`
  underneath), instead of the button being a DetailVBox sibling below the row.
- Hover-for-description now also triggers over the "Use Ability" button, not
  just the icon/name/level/uses — this falls out for free once the button is
  nested inside `AbilityXRow`, since `mouse_entered`/`mouse_exited` fire on the
  row's own bounding rect regardless of which descendant the cursor is over.
- Locked rows now show "?" as the button text (was always "Use Ability",
  just disabled) — matches Miha's sketch of the locked state.

One non-obvious fix this required: a disabled `Button` still defaults to
`mouse_filter = STOP`, which would silently swallow clicks landing on the
button's own rect before they reached `AbilityXRow`'s `gui_input` handler —
breaking click-to-reveal specifically when the click landed on the "?"
button rather than the icon/name area. Fixed by toggling the button's
`mouse_filter` alongside its `disabled` state in `_show_abilities()`/
`_clear_ability_rows()`: `IGNORE` while locked (so clicks pass through to the
row), `STOP` while unlocked (so its own `pressed` signal still fires).

Verified with the same three targeted smoke tests
(`smoke_battle`/`smoke_ability_ui_pipeline`/`smoke_inspect`) plus a full
`run_all.sh` — identical results to the original implementation pass, same
6 pre-existing `smoke_ability_ui_pipeline` failures, nothing new.

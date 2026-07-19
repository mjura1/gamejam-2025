# AI Difficulty Plan — chess-style enemy AI tiers, decoupled from curse difficulty

Implementation plan for a **second, independent difficulty slider** — "AI difficulty" —
that sits next to the existing curse-difficulty selector in Settings. The existing enemy
AI (`base_character.calculate_best_move()`) was hand-tuned for one purpose (mild,
always-beatable bias, explicitly "no minimax/lookahead" per `ENEMY_CURSES_PLAN.md` Phase
5) and was never built to be a spectrum. Rather than keep bolting branches onto that
function, this plan extracts the *decision* half of it into a **new, standalone,
data-driven AI strategy module** with real chess-engine techniques (value-aware capture,
danger avoidance, hanging-piece avoidance / static exchange evaluation, fork/threat
detection, minimax with alpha-beta, and curse-synergy scoring), gated tier-by-tier by
bools + params in a new JSON file. Written to be followed step-by-step; each milestone is
a self-contained commit that leaves the game working and green on
`./tests/run_all.sh`.

Branch: create `features/ai-difficulty` off `develop`. Merge back with `--no-ff` (house
rule — see `[[feedback-no-fast-forward-merges]]`-equivalent: never fast-forward into
develop/main).

**Convention for whoever implements this:** as you deviate from anything written here,
add a `**DEVIATION:**` callout under the relevant milestone's checklist explaining what
changed and why (same convention as `ENEMY_CURSES_PLAN.md` / `SKILL_TREE_PLAN.md`) — the
plan doc becomes the historical record, not just the upfront spec.

**Testing-log convention:** whenever you run `./tests/run_all.sh` (or any headless
Godot scene/script boot) for this plan, note the result under the relevant milestone
(pass/fail, and which new smoke tests were included) — e.g. add a one-line
`**Ran:** ./tests/run_all.sh — green, incl. new smoke_ai_hard/smoke_ai_minimax/...`
under that milestone's checklist. This lets a second agent picking up mid-plan see
what's already been verified instead of re-running the whole suite from scratch.
Nothing has been run yet as of this plan's initial write-up (pure research/read-only
pass, no code changed) — the first entry belongs to M1.

---

## 0. Scope in one paragraph

Today `SettingsManager.difficulty` (EASY/NORMAL/HARD) does two unrelated jobs: it scales
curse *chance*, and it gates the AI's `danger_avoid_prob`. This plan **splits those
jobs**. `SettingsManager.difficulty` keeps doing curse chance only. A new
`SettingsManager.ai_difficulty` (NORMAL/HARD/EXTREME/IMPOSSIBLE — no EASY rung; NORMAL
*is* the floor and reproduces today's behavior exactly) drives a new pluggable AI
strategy that replaces steps 6–8 of `calculate_best_move()`. IMPOSSIBLE gets every
technique turned on, including curse-aware positioning; each lower tier turns
progressively fewer of them on. Perception (line-of-sight spotting, blind seek, panic
detection) is untouched and shared by all four tiers — only the *decision* layer changes.

---

## 1. Current system (what exists today — do not re-derive)

- **`Scripts/SettingsManager.gd`** (autoload): `difficulty: String` ∈
  `["easy","normal","hard"]`, persisted to `user://settings.cfg`. This plan adds a
  sibling field, same file, same save/load pattern.
- **`Scripts/Data/curse_data.gd`** (autoload `CurseData`): also owns
  `GameParameters/ai_config.json` (`piece_values` for value-aware capture,
  `danger_avoid_prob` keyed by **curse**-difficulty). `get_piece_value(name)` and
  `get_ai_param(difficulty, key, default)` are the two AI-relevant getters. This plan
  removes `danger_avoid_prob` from here (see §3.3) — `piece_values` stays, it's
  difficulty-independent (material values don't change per tier).
- **`Scripts/CharacterPieces/base_character.gd::calculate_best_move()`** (~l.706–883),
  enemy-only (`if not is_enemy: return {}`), called once per enemy per action from
  `BattleController._take_enemy_action()`. Current steps, **in order**:
  1. Lured move override (Queen.Lure curse item interaction) — untouched by this plan.
  2. Line-of-sight spotting (`can_see_player`) — sets `has_spotted_player` — **perception, untouched**.
  3. `calculate_valid_targets()`, then filters out capture targets if
     `curse and not curse.can_capture()` (Fey Step) — **untouched, feeds the new strategy**.
  4. Blind-seek (hasn't spotted player yet: walk toward board-center row) — **perception, untouched**.
  5. Closest-visible-player + panic check (`is_panicking`) — **perception, untouched**.
  6. **Capture priority, value-aware**: scans all simultaneously-capturable targets,
     picks the highest `get_piece_value()`. Always on, no difficulty gate ("captures
     stay aggressive, that's the fun" — Miha's words, `ENEMY_CURSES_PLAN.md`). Returns
     immediately if any capture exists — **panic randomness (step 8) never overrides a
     capture**, this invariant must survive the refactor.
  7. **Chase toward `last_known_player_pos`**, with probabilistic danger avoidance:
     `avoid_prob = get_ai_param(difficulty, "danger_avoid_prob")` (today: curse
     difficulty EASY 0% / NORMAL 50% / HARD 100%); among equally-good chase candidates,
     prefers one not in `grid_manager.tiles_reachable_by(false)` (tiles any ally could
     capture next turn).
  8. **Panic randomness**: if panicking, `panic_randomness` chance to pick a fully
     random valid target instead — only reachable when step 6 didn't already return.
- **`Scripts/TileMap/grid_manager.gd`**: `tiles_reachable_by(is_enemy_side)` — union of
  `calculate_valid_targets()` over all living non-obstacle characters on one side. No
  fixed board size — bounds always come from `tile_map.get_used_rect()`. Reuse this,
  don't recompute it.
- **`Scripts/settings_menu.gd` / `Scenes/Menu/settings_menu.tscn`**: `DifficultyRow`
  (`HBoxContainer` → `Label` + `OptionButton %DifficultyOption`, 3 items EASY/NORMAL/HARD,
  `DIFFICULTY_IDS` array indexed to match). New `AiDifficultyRow` goes right after it,
  same pattern.
- **`tests/smoke/smoke_ai.gd`**: covers value-aware capture and probabilistic danger
  avoidance via hand-teleported boards + `settings_manager.difficulty = "hard"/"easy"`.
  After this plan, its danger-avoidance assertions move to drive
  `settings_manager.ai_difficulty` instead (see §5).
- **`BattleController.start_enemy_turn()`**: loops `grid_manager.get_all_characters()`
  in scene order (not AI-chosen), gives each enemy `1 + curse.extra_actions()` actions
  (frenzy), plus a bonus action on capture if `curse.grants_bonus_action_on_capture()`
  (bloodlust). **Per-piece decisions are independent — there is no shared "this turn's
  plan" state today.** Relevant for curse synergy (§2.6) and for the explicitly-deferred
  coordinated-targeting idea (§6).
- **Curses relevant to "make max use of curses" (all in `Scripts/Curses/`,
  `BaseCurse` base class + one hook file per variant, `Data/curses.json` config)**:
  read `GameParameters/curses.json` `_comment_*` fields for full flavor text.
  `on_action_taken(owner, bc)` fires after every action the curse-bearer takes.
  - `frenzy` / `bloodlust`: extra action(s) this enemy turn (frenzy always, bloodlust
    only after a capture).
  - `stunning_gaze` / `entangle`: after moving, affects the **closest visible
    player-side piece** (`find_visible_enemies()` — named from the caller's
    perspective, so for an `is_enemy` owner it returns visible *player* pieces, per the
    comment at `base_character.gd` ~l.480). Picks by raw distance, not value.
  - `abduction`: swaps places with the closest visible player-side piece (pulls it
    toward the enemy cluster — or occasionally pulls the enemy out, "risk is mutual").
  - `changeling`: swaps places with the closest **fellow enemy** (reshuffles the
    enemy's own side).
  - `snowfall` / `contagion` / `blizzard` / `wraith_cloak`: leave curse-fog behind after
    moving (area denial / vision-block).
  - `fey_step`: `can_capture() → false`; already filtered out of `valid_targets` at step
    3 above — no synergy work needed beyond what exists.

---

## 2. Key design decisions

### 2.1 Two independent difficulty axes, going forward

| Setting | Values | Controls | File |
|---|---|---|---|
| `SettingsManager.difficulty` (existing, unchanged name) | easy / normal / hard | Curse chance only (`CurseData.get_curse_chance`) | `GameParameters/curses.json` |
| `SettingsManager.ai_difficulty` (**new**) | normal / hard / extreme / impossible | Enemy move/capture decision-making | `GameParameters/ai_difficulty.json` (**new**) |

Default `ai_difficulty = "normal"` must reproduce **today's** NORMAL-curse-difficulty AI
behavior bit-for-bit (50% danger-avoid, value-aware capture, no search, no curse
synergy) — this is the regression-safety anchor for the whole refactor, and
`smoke_ai.gd`'s existing assertions (adapted to the new setting name) are the
proof.

### 2.2 One new strategy class, data-driven by tier — not four hand-duplicated scripts

The obvious literal reading of "a script per difficulty" is four files
(`ai_normal.gd`, `ai_hard.gd`, `ai_extreme.gd`, `ai_impossible.gd`). **Don't do that** —
the four tiers are a strict superset ladder (§2.4), not four qualitatively different
behaviors, so four subclasses would be ~80% duplicated code. Instead: **one** new class,
`Scripts/AI/enemy_ai_strategy.gd` (`class_name EnemyAIStrategy`), whose behavior is
entirely parametrized by a `Dictionary` of bools/params loaded per-tier from
`GameParameters/ai_difficulty.json`. This still satisfies "entirely new AI script" (the
old `calculate_best_move()` decision logic is fully replaced, not extended) and directly
matches Miha's own instinct to use bools for feature gating. If a future tier needs
genuinely different *shape* of logic (not just more features), split it out then — cheap
to do later since every call site only knows the `EnemyAIStrategy` interface (§2.3).

New autoload **`Scripts/Data/ai_strategy_data.gd`** (`AiStrategyData`, registered in
`project.godot` next to `CurseData`) loads `ai_difficulty.json` and hands out one cached
`EnemyAIStrategy` instance per tier name (`get_strategy(tier: String) -> EnemyAIStrategy`)
— same "1 JSON loader autoload" convention as `ItemData`/`CurseData`.

### 2.3 Split point: perception stays, decision moves

`calculate_best_move()` keeps steps 1–5 (lured move, spotting, valid-targets +
curse-capture filter, blind seek, closest-player/panic) exactly as-is. After step 5, it
calls into the strategy instead of running steps 6–8 inline:

```gdscript
var strategy: EnemyAIStrategy = ai_strategy_data.get_strategy(settings_manager.ai_difficulty)
var action := strategy.choose_action(self, {
    "valid_targets": valid_targets,          # already curse-filtered (Fey Step)
    "capture_candidates": capture_candidates, # subset of valid_targets, obstacles excluded
    "last_known_player_pos": last_known_player_pos,
})
if action.is_empty():
    return {}
# Panic randomness stays a base_character-level trait, NOT part of the difficulty
# ladder (every tier's characters panic the same way) — and, matching today's
# invariant, only ever overrides a MOVE, never a CAPTURE.
if is_panicking and action.get("move_type") != "CAPTURE" and randf() < panic_randomness:
    action = {"move_type": "MOVE", "target_pos": valid_targets[randi() % valid_targets.size()]}
return action
```

`EnemyAIStrategy.choose_action(character, context) -> Dictionary` returns the same
`{"move_type": "MOVE"|"CAPTURE", "target_pos": Vector2i}` shape as today — every caller
downstream (`_take_enemy_action`, `try_move`) is unaffected.

Internally, `choose_action` branches once on the tier's `min_max` flag:

- `min_max == false` (NORMAL, HARD): run the **heuristic ladder** — value-aware capture
  priority (step 6, always), then chase-with-danger-avoidance (step 7) — same structure
  as today, with `avoid_hanging_pieces` (§2.4) as an extra filter layered on for HARD.
- `min_max == true` (EXTREME, IMPOSSIBLE): collapse "capture" and "chase" into **one**
  evaluation — score every entry in `valid_targets` (captures included) via minimax
  (§2.5) and pick the max. Real chess engines don't special-case captures either; they
  just tend to score well because of the material swing in the evaluation function.

### 2.4 The tier ladder (placeholder numbers — Miha's to balance)

`GameParameters/ai_difficulty.json`, one object per tier, **strictly additive**
(IMPOSSIBLE = every bool true; each lower tier is a subset):

| Param | NORMAL | HARD | EXTREME | IMPOSSIBLE |
|---|---|---|---|---|
| `danger_avoid_prob` | 0.5 | 1.0 | 1.0 | 1.0 |
| `avoid_hanging_pieces` | false | **true** | true | true |
| `static_exchange_evaluation` | false | false | **true** | true |
| `threat_creation` (fork bonus) | false | false | **true** | true |
| `min_max` | false | false | **true** | true |
| `minimax_depth` | 0 | 0 | **1** | **2** |
| `curse_synergy` | false | false | false | **true** |

Rationale for the cut points (change freely, this is the "you pick" part, just keep the
superset property so IMPOSSIBLE stays the ceiling):

- **HARD** = today's danger-avoidance made deterministic, plus `avoid_hanging_pieces`
  (see below) — a real chess-engine "level 1" is usually just *don't blunder*, no search
  yet. No `min_max` — still O(valid_targets), still fast, still visibly "the same AI,
  just less forgiving."
- **EXTREME** = first tier with real search (`min_max`, 1-ply — "what's the opponent's
  best reply to each of my candidate moves") plus SEE and fork-awareness. This is the
  jump from "smarter heuristics" to "actually looks ahead."
- **IMPOSSIBLE** = deeper search (2-ply) + curse synergy. Everything on.

Feature definitions:

- **`avoid_hanging_pieces`**: generalizes today's danger-avoidance from the chase step
  to *every* candidate, captures included (today's code explicitly never filters
  captures — "captures stay aggressive"). For each candidate destination, if it's in
  `grid_manager.tiles_reachable_by(false)` (ally-reachable) **and** the capturing ally's
  `get_piece_value()` isn't clearly worth less than what we'd gain, deprioritize it in
  favor of an equally-good-or-better safe candidate. Never leaves the AI with zero
  moves — same "fall back to normal best if all candidates are dangerous" rule as today.
- **`static_exchange_evaluation`** (SEE — standard chess-engine term, use it verbatim so
  future readers recognize the technique): before committing to a capture, check
  whether the destination square is itself defended (`tiles_reachable_by(false)` again,
  value-aware). If the piece we'd lose in the recapture is worth more than the piece we
  just captured, and a less-tempting-but-safe capture or non-capture move nets more
  material overall, prefer that instead. This is what stops IMPOSSIBLE/EXTREME from
  trading a rook for a defended pawn.
- **`threat_creation`**: when no immediate capture wins outright, add a small
  evaluation bonus to candidates that would put 2+ player pieces within this piece's
  *next-turn* capture range simultaneously (a fork) — count via a hypothetical
  `calculate_valid_targets()`-shaped scan from the candidate tile against the board
  snapshot (§2.5), not a live move.
- **`min_max` / `minimax_depth`**: see §2.5, this is the one that needs its own section.
- **`curse_synergy`**: see §2.6.

### 2.5 Minimax scope — read this before writing any search code

**This is not classic 1-piece-per-turn chess** — every enemy moves every enemy-turn, and
turn order is scene order, not AI-chosen (§1). A literal full-board game tree (branch on
every piece's every move, every ply) is both wrong (doesn't match how a "turn" actually
works here) and combinatorially too slow for GDScript in a jam project. Scope it down
like this:

- **Unit of search = one piece's one decision**, not the whole board. `minimax_depth`
  counts *adversarial replies*, not full game turns:
  - Depth 1 (EXTREME): for each candidate destination, simulate it, then find the
    single best-for-the-opponent response among **nearby player-side pieces only**
    (bound the opponent's move generation to pieces within, say,
    `move_range + opponent's own move_range` tiles of the contested square — pieces far
    away can't plausibly punish this move, and scanning them wastes time). Evaluate the
    resulting position (§2.5.1); this is the candidate's minimax value.
  - Depth 2 (IMPOSSIBLE): same, plus one more ply — our best reply to their best reply
    — still radius-bounded, still only the pieces that were actually part of the
    depth-1 exchange (not a fresh full-board scan).
  - Implement as a small recursive `_minimax(state, depth, maximizing, alpha, beta)`
    with **alpha-beta pruning required** (not optional) — without it, depth 2 with even
    a handful of nearby pieces gets slow.
- **Never mutate the live game during search.** `grid_manager.occupy`/`vacate`,
  `character.grid_pos` writes, curse hooks, and signals all have real side effects
  (fog, visuals, `on_action_taken`). Build a **lightweight board snapshot** at the start
  of one piece's `choose_action` call instead:
  `Dictionary[Vector2i, {is_enemy: bool, strName: String, value: int}]`, cloned once
  from `grid_manager.get_all_characters()`. Write a small pure move-generator against
  this dictionary that reuses `get_move_directions()` + `move_range` geometry (same
  loop shape as `calculate_valid_targets()`, minus LOS/fog/entry-denial concerns — those
  don't matter for a hypothetical 1–2 ply lookahead) instead of touching
  `grid_manager`/scene-tree state at all. This sidesteps an entire class of
  flicker/signal bugs that mutate-then-revert would risk.
- **Evaluation function** (§2.5.1) is the only place minimax reads "how good is this
  position" — keep move generation and evaluation cleanly separate so `threat_creation`
  and `curse_synergy` (both additive score terms) plug into the same function without
  touching the search code.

#### 2.5.1 Evaluation function components

`func _evaluate(snapshot, mover_is_enemy: bool) -> float`, higher = better for the
mover's side:

1. **Material**: Σ `get_piece_value()` for mover's side − Σ for opponent's side (reuse
   `ai_config.json` `piece_values`, unchanged by this plan).
2. **Board control** (lightweight piece-square-table analogue): small bonus for tiles
   closer to board center (`tile_map.get_used_rect()` center) — mirrors real engines'
   center-control heuristic without needing real piece-square tables.
3. **Mobility**: small bonus proportional to `valid_targets.size()` from the candidate
   position (more options = better position) — cheap, reuses the snapshot move
   generator from §2.5.
4. **Curse synergy bonus** (IMPOSSIBLE only, `curse_synergy` flag) — see §2.6, additive
   term.

Keep weights as named constants in `enemy_ai_strategy.gd` (or a small sub-object in
`ai_difficulty.json` if Miha wants them tunable without touching code) — placeholder
values, his to balance.

### 2.6 Curse synergy — new `BaseCurse` hook, per-curse overrides

Follow the existing "1 base class, variants override hooks" pattern (`BaseCurse`
already has `on_action_taken`/`on_applied`/`can_capture`/`grants_bonus_action_on_capture`
— this is the same shape). Add one new hook:

```gdscript
# base_curse.gd
# IMPOSSIBLE-tier AI positioning bonus: how much does ending THIS turn's move at
# candidate_pos help this curse's post-move effect (see enemy_ai_strategy.gd
# curse_synergy scoring). 0 = no opinion (default — most curses don't need this).
func ai_positioning_bonus(_owner, _candidate_pos: Vector2i, _snapshot: Dictionary) -> float:
    return 0.0
```

Only override it where positioning genuinely changes the curse's outcome (curses whose
`on_action_taken` picks a target "closest to me" — moving changes who's closest):

- **`stunning_gaze_curse.gd` / `entangle_curse.gd`**: today's hook picks the *nearest*
  visible player-side piece by raw distance, not value — the AI can't change *that*
  it'll pick nearest, but it CAN change *which piece ends up nearest* by choosing where
  to stand. Override: among visible player-side pieces reachable from `candidate_pos`
  within `move_range`, bonus scales with the value of whichever one would end up
  closest (i.e. steer toward being nearest to the *expensive* piece, not just any
  piece).
- **`abduction_curse.gd`**: same "nearest visible" targeting, but the effect (swap
  places, yanking a player piece into the enemy cluster) is far more punishing — weight
  this bonus higher than stunning_gaze/entangle's, scaled by both the target's value
  and how much worse its resulting position looks (e.g. resulting tile's
  `tiles_reachable_by(true)` count — more enemies able to reach it next turn = better
  abduction).
- **`changeling_curse.gd`**: swaps with the nearest *fellow enemy* — bonus for
  positioning so that swap pulls a valuable-but-exposed ally enemy back to safety
  (candidate positions where the nearest fellow-enemy-after-swap improves that ally's
  own safety, per `tiles_reachable_by(false)`).
  Skip this one if it's not worth the complexity for v1 — it's the least impactful
  curse to optimize (reshuffles the enemy's own side, no direct effect on the player);
  fine to leave at the default 0.0 bonus and note it as deferred.
- **`frenzy_curse.gd` / `bloodlust_curse.gd`**: no positioning override needed — instead,
  when the strategy is evaluating a candidate for a piece carrying either curse, treat
  it as "this piece gets to act again immediately" in the evaluation (small bonus for
  candidates that also set up an *additional* capture opportunity for the guaranteed
  follow-up action — cheap to approximate: does this candidate's own
  `valid_targets`-from-there include a capture?). This lives in
  `enemy_ai_strategy.gd`'s scoring, not on `BaseCurse` (it's about the piece's own
  extra-action mechanic, not a per-curse "who do I target" question).
- **`snowfall`/`contagion`/`blizzard`/`wraith_cloak`**: leave curse-fog behind — bonus
  for candidates whose resulting fog coverage overlaps
  `grid_manager.tiles_reachable_by(false)` (area-denial on tiles the player could
  otherwise use). Small weight — this is positional flavor, not a big swing.
- **`fey_step`**: no override — `can_capture() == false` is already fully handled
  upstream at step 3; nothing curse-specific left for the strategy to optimize.

`enemy_ai_strategy.gd` calls `character.curse.ai_positioning_bonus(character,
candidate_pos, snapshot)` once per candidate when `curse_synergy` is enabled and
`character.curse != null`, adds it into `_evaluate`'s score for that branch.

---

## 3. Data model

### 3.1 `SettingsManager.gd` additions

```gdscript
const VALID_AI_DIFFICULTIES := ["normal", "hard", "extreme", "impossible"]
var ai_difficulty: String = "normal"

func set_ai_difficulty(value: String):
    if value not in VALID_AI_DIFFICULTIES:
        return
    ai_difficulty = value
    save_settings()
```

Mirror `load_settings()`/`save_settings()` exactly like the existing `difficulty` field
(new `cfg.get_value`/`set_value` calls, same `SECTION`).

### 3.2 New `GameParameters/ai_difficulty.json`

Schema per §2.4's table — one object per tier name, all four required keys present for
all four tiers (no implicit defaults across tiers, to keep the file self-documenting):

```json
{
  "normal":     {"danger_avoid_prob": 0.5, "avoid_hanging_pieces": false, "static_exchange_evaluation": false, "threat_creation": false, "min_max": false, "minimax_depth": 0, "curse_synergy": false},
  "hard":       {"danger_avoid_prob": 1.0, "avoid_hanging_pieces": true,  "static_exchange_evaluation": false, "threat_creation": false, "min_max": false, "minimax_depth": 0, "curse_synergy": false},
  "extreme":    {"danger_avoid_prob": 1.0, "avoid_hanging_pieces": true,  "static_exchange_evaluation": true,  "threat_creation": true,  "min_max": true,  "minimax_depth": 1, "curse_synergy": false},
  "impossible": {"danger_avoid_prob": 1.0, "avoid_hanging_pieces": true,  "static_exchange_evaluation": true,  "threat_creation": true,  "min_max": true,  "minimax_depth": 2, "curse_synergy": true}
}
```

Use the same `_comment_<field>`-sibling-key convention as `curses.json` (strict JSON,
no real comments) if inline documentation is useful.

### 3.3 `GameParameters/ai_config.json` change

Remove `danger_avoid_prob` (superseded by `ai_difficulty.json`, and the curse-difficulty
keys `easy`/`normal`/`hard` no longer make sense next to `ai_difficulty`'s
`normal`/`hard`/`extreme`/`impossible`). Keep `piece_values` as-is. Remove the matching
`get_ai_param()` getter from `curse_data.gd` if nothing else uses it after this change
(grep first — `smoke_ai.gd` calls into `calculate_best_move()`, not `get_ai_param`
directly, so this should be safe, but verify).

---

## 4. Milestones

### M1 — Settings plumbing (no AI behavior change yet)

- [x] `SettingsManager`: add `ai_difficulty` field + `set_ai_difficulty` + persistence
      (§3.1).
- [x] `settings_menu.tscn`: new `AiDifficultyRow` (`HBoxContainer`, mirrors
      `DifficultyRow`) placed directly after it, `OptionButton` with 4 items
      NORMAL/HARD/EXTREME/IMPOSSIBLE.
- [x] `settings_menu.gd`: `@onready var ai_difficulty_option`, `AI_DIFFICULTY_IDS`
      const, wire `item_selected` → `SettingsManager.set_ai_difficulty`, same shape as
      the existing difficulty handler (incl. `UiAudio.play_click()`).
- [x] Confirm curse-difficulty selector is untouched and still only reads/writes
      `SettingsManager.difficulty`.

**Ran:** `./tests/run_all.sh` — 1 pre-existing failure (`smoke_ability_ui_pipeline`,
`Queen.Lure`/`King.Cleanse`/`King.Heal` UI-pipeline assertions), confirmed present
identically on baseline `develop` via `git stash` before this milestone's changes even
existed — unrelated to this plan, not caused by M1. Every other check (incl.
`smoke_ai.gd`) green. No new smoke tests this milestone (no AI behavior changed yet,
per §0/§2.1 — this is settings plumbing only).

### M2 — Strategy scaffolding + NORMAL tier (regression milestone)

- [ ] `GameParameters/ai_difficulty.json` (§3.2).
- [ ] `Scripts/Data/ai_strategy_data.gd` new autoload, registered in `project.godot`:
      loads the JSON, `get_strategy(tier) -> EnemyAIStrategy`, caches one instance per
      tier name.
- [ ] `Scripts/AI/enemy_ai_strategy.gd` (`class_name EnemyAIStrategy`, `extends
      RefCounted` — same base as `BaseCurse`): constructor takes the tier's param
      dict; `choose_action(character, context) -> Dictionary` entry point (§2.3).
      For this milestone, implement ONLY the `min_max == false` heuristic path,
      reproducing steps 6–7 of today's `calculate_best_move()` verbatim (value-aware
      capture always-on, `danger_avoid_prob`-gated chase). `avoid_hanging_pieces` stub
      returns unfiltered for now (wired in M3).
- [ ] `base_character.gd::calculate_best_move()`: replace steps 6–8 with the
      strategy call + the panic-randomness wrapper shown in §2.3. Steps 1–5 untouched.
- [ ] Remove `danger_avoid_prob` from `ai_config.json` + `get_ai_param()` if unused
      elsewhere (§3.3).
- [ ] `smoke_ai.gd`: change `settings_manager.difficulty = "hard"/"easy"` to
      `settings_manager.ai_difficulty = "hard"/"normal"` for the danger-avoidance
      assertions (HARD → `danger_avoid_prob = 1.0` deterministic, same expected tile;
      NORMAL → `0.5`, same probabilistic-but-seedable-by-tile-tie test as today's
      "easy" case — check whether the existing test relied on `0.0` exactly, in which
      case keep a `normal` assertion but adjust the expected probability/behavior
      description, don't just rename the string). Value-aware capture assertions are
      unaffected either way.
- [ ] `./tests/run_all.sh` green. This milestone should be a **behavior no-op** for
      `ai_difficulty = "normal"` vs. today's `difficulty = "normal"` AI.

### M3 — HARD + EXTREME tiers

- [ ] `avoid_hanging_pieces`: implement the value-aware danger filter (§2.4),
      applied inside the heuristic path (both capture and chase candidates), gated on
      the tier flag. Verify HARD still returns a move when *every* candidate is
      dangerous (never paralyze).
- [ ] `static_exchange_evaluation` + `threat_creation`: implement as scoring
      adjustments (§2.4), only reachable once `min_max == true`, i.e. these live in the
      minimax evaluation path (§2.5.1), not the heuristic path — EXTREME is the first
      tier where both `min_max` and these two flags are true together.
- [ ] Minimax core (§2.5): board snapshot builder, radius-bounded opponent
      move generation, `_minimax(state, depth, maximizing, alpha, beta)` with
      alpha-beta pruning, `_evaluate()` (material + board-control + mobility, no curse
      term yet). Wire depth 1 for EXTREME.
- [ ] Smoke test: small hand-built board where the "obviously good" move (grab a
      pawn) is actually a **trap** (that square is defended by a rook worth more than
      the pawn) — assert EXTREME/IMPOSSIBLE decline the trade and NORMAL/HARD still
      walk into it (proves SEE + minimax are actually doing something, not just present
      but inert).

### M4 — IMPOSSIBLE tier + curse synergy

- [ ] Bump minimax to depth 2 for IMPOSSIBLE (still radius-bounded, still
      alpha-beta pruned — re-check perf, see M5).
- [ ] `BaseCurse.ai_positioning_bonus()` new hook (default `0.0`), wired into
      `_evaluate()` behind the `curse_synergy` flag (§2.6).
- [ ] Per-curse overrides: `stunning_gaze_curse.gd`, `entangle_curse.gd`,
      `abduction_curse.gd` (required); `changeling_curse.gd` and the
      fog-curse family (optional for v1, note as deferred if skipped — see §2.6).
- [ ] `frenzy`/`bloodlust` extra-action awareness in `enemy_ai_strategy.gd`'s own
      scoring (not a `BaseCurse` hook — §2.6).
- [ ] Smoke test: enemy with `stunning_gaze` (or `entangle`) on IMPOSSIBLE, two
      visible player pieces of different `piece_values` both reachable — assert it
      chooses the move that ends up nearest the *higher-value* one, vs. NORMAL/HARD/
      EXTREME which (no curse_synergy) pick whichever nearest-by-raw-distance the
      existing on_action_taken hook would've picked regardless of the AI's move choice.

### M5 — Performance guardrail

- [ ] Headless timing smoke: a battle with a realistic worst-case enemy count (check
      `MapGenerator`/`GameParameters` for the actual max enemies-per-battle used at the
      hardest map tier) on IMPOSSIBLE, measure wall-clock for one full
      `start_enemy_turn()` pass. No hard frame budget exists elsewhere in this codebase
      to match against — pick a sane ceiling (e.g. a few hundred ms total, not
      per-piece) and print the measured time so Miha can judge by feel; don't silently
      pass/fail on an arbitrary threshold.
- [ ] If too slow: tighten the opponent-move-generation radius bound (§2.5) before
      reducing search depth — radius is the cheaper lever.

### M6 — Wrap up

- [ ] Full `./tests/run_all.sh` green, including all new smoke tests from M2–M5.
- [ ] Headless `battle.tscn` boot, `--quit-after 5`, zero ERROR lines, at a forced
      floor where curses are active (reuses the pattern from `ENEMY_CURSES_PLAN.md`
      Phase 6) — confirms curse synergy code paths don't error even when
      `curse_synergy` is off (default guard clauses) and when on.
- [ ] `CHANGELOG.md` entry.
- [ ] Small per-milestone commits, Claude co-author line, leave branch unmerged for
      review (per house convention — Miha merges `--no-ff` himself when ready).

---

## 5. Testing plan (rolled into milestones above, summarized here)

- M2: `ai_difficulty = "normal"` behaves identically to today's AI (regression proof).
- M2: `ai_difficulty = "hard"` danger-avoidance is now deterministic (prob 1.0), not
  probabilistic.
- M3: a defended-pawn "trap" scenario distinguishes NORMAL/HARD (walks in) from
  EXTREME/IMPOSSIBLE (declines) — proves SEE/minimax are load-bearing.
- M3: `avoid_hanging_pieces` never paralyzes HARD when all candidates are dangerous.
- M4: curse-synergy positioning test for `stunning_gaze`/`entangle` (steers toward the
  higher-value visible target).
- M5: coarse perf smoke, printed not asserted (no existing frame-budget convention to
  assert against).

---

## 6. Explicitly out of scope (don't build, note as deferred if tempting)

- **Coordinated targeting / focus-fire across multiple enemies in the same turn.** This
  is the one idea in this plan that reaches past single-piece decision-making — it'd
  need either a shared per-turn blackboard on `BattleController` or a reordering of
  `start_enemy_turn()`'s loop, and it's not required to satisfy "typical chess AI"
  (chess doesn't have this concept at all — it's a many-pieces-move-at-once
  extension). Worth a follow-up plan if Miha wants it later; don't fold it into this
  one.
- **Enemy ability usage.** Enemies don't load `ability_levels` today
  (`base_character.gd` early-returns for `is_enemy` in the ability-loading path) — out
  of scope, unrelated to move/capture AI.
- **An AI-difficulty "EASY" rung.** Not requested (the tier list given was
  normal/hard/extreme/impossible); NORMAL is the floor. Cheap to add later (a fifth
  JSON entry with e.g. `danger_avoid_prob: 0.0` and everything else false) if wanted.
- **Changing `piece_values` or curse chance/weights.** Material values and curse
  balancing are unrelated systems, untouched here.
- **Balancing the actual numbers in `ai_difficulty.json` and the evaluation-function
  weights.** Every number in this plan is a placeholder — Miha's to tune by playtest,
  same convention as every other JSON-driven system in this repo.
- **HARD/EXTREME must stay "beatable."** IMPOSSIBLE is explicitly allowed to be
  unfair (it's the challenge/bragging-rights tier) — but HARD and EXTREME should still
  be playtested for fairness given the existing "all enemies move every turn vs.
  player's ~1" asymmetry noted in `ENEMY_CURSES_PLAN.md`. This is a playtest/tuning
  concern, not something to hard-code a fairness cap for.

extends TestCase

# Testi za GameParameters/skill_trees.json shemo in PlayerManager nakup vozlišč
# (glej SKILL_TREE_PLAN.md §2 in §7).

const PlayerManagerScript = preload("res://Scripts/Player/PlayerManager.gd")

const PIECE_TYPES := ["pawn", "knight", "rook", "bishop", "queen", "king"]
const SKELETON_IDS := ["a1_lv2", "a1_lv3", "a2_unlock", "a2_lv2", "a2_lv3", "p1", "a3_unlock", "a3_lv2", "a3_lv3", "spec_a", "spec_b"]
const EFFECT_TYPES := ["ability_level", "ability_unlock", "move_range", "extra_uses", "battle_start_reveal", "move_reveal", "curse_immune", "flag"]
const NEW_ABILITY_IDS := ["promotion", "ambush", "sanctify", "castling", "command", "royal_decree"]

# ----------------- shema GameParameters/skill_trees.json -----------------

func test_every_piece_type_has_full_skeleton():
	for piece_type in PIECE_TYPES:
		var ids: Array = []
		for node_def in SkillTreeData.get_tree_nodes(piece_type):
			ids.append(node_def.get("id", ""))
		for skeleton_id in SKELETON_IDS:
			assert_true(ids.has(skeleton_id), "%s tree should contain node '%s'" % [piece_type, skeleton_id])
		assert_eq(ids.size(), SKELETON_IDS.size(), "%s tree should have exactly the %d skeleton nodes" % [piece_type, SKELETON_IDS.size()])

func test_requires_and_excludes_reference_existing_nodes():
	for piece_type in PIECE_TYPES:
		for node_def in SkillTreeData.get_tree_nodes(piece_type):
			for req in node_def.get("requires", []):
				assert_false(SkillTreeData.get_node_def(piece_type, req).is_empty(), "%s/%s requires unknown node '%s'" % [piece_type, node_def.get("id"), req])
			for excl in node_def.get("excludes", []):
				assert_false(SkillTreeData.get_node_def(piece_type, excl).is_empty(), "%s/%s excludes unknown node '%s'" % [piece_type, node_def.get("id"), excl])

func test_every_effect_type_is_in_vocabulary():
	for piece_type in PIECE_TYPES:
		for node_def in SkillTreeData.get_tree_nodes(piece_type):
			var effect: Dictionary = node_def.get("effect", {})
			assert_true(EFFECT_TYPES.has(effect.get("type", "")), "%s/%s has unknown effect type '%s'" % [piece_type, node_def.get("id"), effect.get("type", "")])
			if effect.get("type", "") in ["ability_level", "ability_unlock", "extra_uses"]:
				var slot := int(effect.get("slot", 0))
				assert_true(slot >= 1 and slot <= 3, "%s/%s effect slot %d out of range 1-3" % [piece_type, node_def.get("id"), slot])

func test_every_node_has_name_desc_and_positive_cost():
	for piece_type in PIECE_TYPES:
		for node_def in SkillTreeData.get_tree_nodes(piece_type):
			assert_true(node_def.get("name", "") != "", "%s/%s is missing a name" % [piece_type, node_def.get("id")])
			assert_true(node_def.get("desc", "") != "", "%s/%s is missing a desc" % [piece_type, node_def.get("id")])
			assert_true(int(node_def.get("cost", 0)) > 0, "%s/%s should have a positive cost" % [piece_type, node_def.get("id")])

func test_new_ability_ids_exist_in_abilities_json():
	for ability_id in NEW_ABILITY_IDS:
		assert_true(AbilityData.get_base_uses(ability_id) > 0, "abilities.json should define base_uses for new ability '%s'" % ability_id)

# ----------------- nakupna pravila (try_buy_node) -----------------

func test_cannot_buy_without_enough_items():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 1
	assert_false(pm.try_buy_node("pawn", "a1_lv2"), "buying a cost-2 node with 1 item should fail")
	assert_eq(pm.upgrade_items, 1, "a failed buy should not spend items")

func test_cannot_buy_without_requirements():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 10
	assert_false(pm.try_buy_node("pawn", "a1_lv3"), "a1_lv3 requires a1_lv2 first")
	assert_false(pm.try_buy_node("pawn", "a3_unlock"), "a3_unlock requires p1 first")

func test_buy_spends_cost_and_marks_owned():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 3
	assert_true(pm.try_buy_node("pawn", "a1_lv2"), "buy should succeed with enough items")
	assert_eq(pm.upgrade_items, 1, "buy should spend exactly the node cost")
	assert_true(pm.has_tree_node("pawn", "a1_lv2"), "bought node should be owned")

func test_cannot_buy_same_node_twice():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 10
	assert_true(pm.try_buy_node("pawn", "p1"), "first buy should succeed")
	assert_false(pm.try_buy_node("pawn", "p1"), "second buy of the same node should fail")
	assert_eq(pm.upgrade_items, 9, "the failed re-buy should not spend items")

func test_unknown_node_id_fails():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 10
	assert_false(pm.try_buy_node("pawn", "a1_lv4"), "buying a node id not in the tree should fail")
	assert_false(pm.try_buy_node("dragon", "a1_lv2"), "buying for an unknown piece type should fail")

func test_specs_are_mutually_exclusive():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 20
	assert_true(pm.try_buy_node("pawn", "p1"), "p1 buy should succeed")
	assert_true(pm.try_buy_node("pawn", "a3_unlock"), "a3_unlock buy should succeed")
	assert_true(pm.try_buy_node("pawn", "spec_a"), "spec_a buy should succeed")
	assert_false(pm.try_buy_node("pawn", "spec_b"), "spec_b must be locked once spec_a is owned")

func test_purchases_are_per_type_not_shared():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 10
	assert_true(pm.try_buy_node("pawn", "p1"), "pawn p1 buy should succeed")
	assert_false(pm.has_tree_node("rook", "p1"), "buying for one type should not mark another type")

# ----------------- izpeljano stanje -----------------

func test_ability_level_derived_from_owned_nodes():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 10
	assert_eq(pm.get_ability_level("pawn", 1), 1, "fresh type should be level 1")
	pm.try_buy_node("pawn", "a1_lv2")
	assert_eq(pm.get_ability_level("pawn", 1), 2, "owning a1_lv2 should derive level 2")
	pm.try_buy_node("pawn", "a1_lv3")
	assert_eq(pm.get_ability_level("pawn", 1), 3, "owning both level nodes should derive level 3")
	assert_eq(pm.get_ability_level("pawn", 2), 1, "slot 2 level should be untouched by slot 1 nodes")

func test_slot_unlocks_derived_from_owned_nodes():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 10
	assert_true(pm.is_slot_unlocked("pawn", 1), "slot 1 is always unlocked")
	assert_false(pm.is_slot_unlocked("pawn", 2), "slot 2 starts locked")
	assert_false(pm.is_slot_unlocked("pawn", 3), "slot 3 starts locked")
	pm.try_buy_node("pawn", "a2_unlock")
	assert_true(pm.is_slot_unlocked("pawn", 2), "a2_unlock should unlock slot 2")
	pm.try_buy_node("pawn", "p1")
	pm.try_buy_node("pawn", "a3_unlock")
	assert_true(pm.is_slot_unlocked("pawn", 3), "a3_unlock should unlock slot 3")

func test_passive_effects_exclude_level_and_unlock_nodes():
	var pm = PlayerManagerScript.new()
	pm.upgrade_items = 10
	pm.try_buy_node("pawn", "a1_lv2")
	pm.try_buy_node("pawn", "a2_unlock")
	assert_eq(pm.get_passive_effects("pawn").size(), 0, "level/unlock nodes are not passives")
	pm.try_buy_node("pawn", "p1")
	var effects: Array = pm.get_passive_effects("pawn")
	assert_eq(effects.size(), 1, "owning p1 should yield exactly one passive effect")
	assert_eq(effects[0].get("type"), "move_range", "pawn p1 should be a move_range passive")
	assert_eq(int(effects[0].get("amount", 0)), 1, "pawn p1 should grant +1 move range")

func test_debug_max_grants_all_but_spec_b():
	var pm = PlayerManagerScript.new()
	pm.debug_max_all_upgrades()
	for piece_type in PIECE_TYPES:
		assert_eq(pm.get_ability_level(piece_type, 1), BaseCharacter.ABILITY_LEVEL_MAX, "%s slot 1 should be maxed" % piece_type)
		assert_true(pm.is_slot_unlocked(piece_type, 2), "%s slot 2 should be unlocked" % piece_type)
		assert_true(pm.is_slot_unlocked(piece_type, 3), "%s slot 3 should be unlocked" % piece_type)
		assert_true(pm.has_tree_node(piece_type, "spec_a"), "%s should own spec_a" % piece_type)
		assert_false(pm.has_tree_node(piece_type, "spec_b"), "%s should NOT own spec_b (excluded by spec_a)" % piece_type)

# Manual visual preview - NOT part of run_all.sh. Boots a real battle, freezes
# a rook/pawn/king via the real snow-freeze mechanic, grants war_council and
# forces its enemy turn-order badges, screenshots the result, then TELEPORTS
# (not a real move - frozen pieces have no valid moves, see
# tests/smoke/smoke_snow_freeze.gd) the frozen pieces to a new tile and
# screenshots again, to check whether FrozenBadge/OrderBadge actually follow
# their piece (they're regular child nodes, so they should) or are somehow
# anchored elsewhere (Miha's report: "the blue dot isn't located on the
# piece").
#
# Run: godot4 --path . --script res://tests/dev/preview_badge_alignment.gd --quit-after 200
extends SceneTree

enum Stage { WAIT_PLAYER_TURN, SETUP, SHOT_1, WAIT_A_FRAME, TELEPORT, SHOT_2, DONE }
var stage: int = Stage.WAIT_PLAYER_TURN

var battle_instance
var player_manager
var grid_manager
var battle_controller
var battle_ui
var used_rect: Rect2i

var rook: BaseCharacter = null
var pawn: BaseCharacter = null
var king: BaseCharacter = null

const OUT_DIR := "/tmp/godot_badge_preview/"

func _initialize():
	player_manager = root.get_node("PlayerManager")
	battle_instance = BattleBoot.boot(self)

	var roster: Array[String] = ["friendly_rook", "friendly_pawn", "friendly_king"]
	player_manager.friendly_party = roster
	var enemies: Array[String] = ["enemy_pawn", "enemy_pawn"]
	player_manager.enemy_party = enemies
	player_manager.active_enemies = enemies.duplicate()
	player_manager.owned_items["war_council"] = 1

func _teleport(character: BaseCharacter, pos: Vector2i) -> void:
	grid_manager.vacate(character.grid_pos)
	character.grid_pos = pos
	grid_manager.occupy(pos, character)
	character.global_position = grid_manager.grid_to_world(pos)

func _ring_with_ambient_fog(pos: Vector2i) -> void:
	var neighbors: Array[Vector2i] = [
		pos + Vector2i(1, 0), pos + Vector2i(-1, 0),
		pos + Vector2i(0, 1), pos + Vector2i(0, -1),
	]
	grid_manager.cover_area(neighbors)

func _debug_dump(label: String, character: BaseCharacter, badge_name: String) -> void:
	var badge := character.get_node_or_null(badge_name)
	var xform: Transform2D = root.get_viewport().get_final_transform() * root.get_viewport().canvas_transform
	print("--- %s ---" % label)
	print("  character.scale = %s   character.global_position = %s  -> SCREEN %s" % [
		character.scale, character.global_position, xform * character.global_position])
	if badge:
		print("  %s.scale = %s   %s.position = %s   %s.global_position = %s  -> SCREEN %s" % [
			badge_name, badge.scale, badge_name, badge.position, badge_name, badge.global_position,
			xform * badge.global_position])
		print("  offset (badge.global_position - character.global_position) = %s   SCREEN px offset = %s" % [
			badge.global_position - character.global_position,
			xform * badge.global_position - xform * character.global_position])
	else:
		print("  %s not found" % badge_name)
	var sprite := character.get_node_or_null("Sprite2D") as Sprite2D
	if sprite and sprite.texture:
		print("  Sprite2D.scale = %s   texture size = %s   sprite global_scale-equivalent size(px) = %s" % [
			sprite.scale, sprite.texture.get_size(),
			Vector2(sprite.texture.get_size()) * sprite.scale * character.scale])

func _screenshot(path: String) -> void:
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	img.save_png(path)
	print("Saved screenshot: %s" % path)

func _process(_delta: float) -> bool:
	if not is_instance_valid(battle_instance):
		return false

	battle_controller = battle_instance.get_node_or_null("BattleController")
	if not is_instance_valid(battle_controller):
		return false

	match stage:
		Stage.WAIT_PLAYER_TURN:
			if battle_controller.current_state != battle_controller.BattleState.PLAYER_TURN:
				return false
			grid_manager = battle_instance.get_node("GridManager")
			battle_ui = battle_instance.get_node("BattleUI")
			used_rect = battle_instance.get_node("Map/TileMapLayer").get_used_rect()
			stage = Stage.SETUP

		Stage.SETUP:
			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and c.is_obstacle:
					grid_manager.vacate(c.grid_pos)
					c.queue_free()

			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and not c.is_enemy:
					if c.strName == "rook": rook = c
					elif c.strName == "pawn": pawn = c
					elif c.strName == "king": king = c

			var origin: Vector2i = used_rect.position
			_teleport(rook, origin + Vector2i(2, 2))
			_teleport(pawn, origin + Vector2i(5, 2))
			_teleport(king, origin + Vector2i(8, 2))

			var enemy_i := 0
			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and c.is_enemy:
					_teleport(c, origin + Vector2i(2 + enemy_i * 3, 6))
					enemy_i += 1

			# Freeze rook + pawn (real mechanic: ring with ambient fog, then
			# the same turn-start tick smoke_snow_freeze.gd uses - this also
			# emits the real piece_frozen signal battle_ui listens to).
			rook.snow_trapped_turns = 0
			rook.snow_frozen = false
			pawn.snow_trapped_turns = 0
			pawn.snow_frozen = false
			_ring_with_ambient_fog(rook.grid_pos)
			_ring_with_ambient_fog(pawn.grid_pos)
			battle_controller.update_fog_after_turn_start()

			# war_council: force the real refresh (normally fires on entering
			# PLAYER_TURN, which we're already past).
			battle_ui._refresh_war_council_badges()

			# Also exercise Stun (king) + Marked (one enemy) to check the
			# shared-slot reuse (Stun/Marked share SLOT_A, Root/OrderBadge
			# share SLOT_B) actually looks right on real pieces.
			king.stunned_turns = 2
			battle_ui._refresh_stun_badges()
			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and c.is_enemy:
					c.marked_by_vision_item = true
					break
			battle_ui._refresh_marked_badges()

			stage = Stage.SHOT_1

		Stage.SHOT_1:
			_debug_dump("rook", rook, "FrozenBadge")
			_debug_dump("pawn", pawn, "FrozenBadge")
			for c in grid_manager.get_all_characters():
				if c is BaseCharacter and c.is_enemy:
					_debug_dump(c.strName + "_" + str(c.get_instance_id()), c, "OrderBadge")
			_screenshot(OUT_DIR + "1_frozen_and_war_council.png")
			stage = Stage.WAIT_A_FRAME

		Stage.WAIT_A_FRAME:
			# Let the freeze/war_council state settle one more frame before
			# yanking pieces around.
			stage = Stage.TELEPORT
			return false

		Stage.TELEPORT:
			print("rook frozen? %s  pos before move: %s" % [rook.is_snow_frozen_now(), rook.grid_pos])
			print("pawn frozen? %s  pos before move: %s" % [pawn.is_snow_frozen_now(), pawn.grid_pos])
			_teleport(rook, used_rect.position + Vector2i(2, 5))
			_teleport(pawn, used_rect.position + Vector2i(5, 5))
			print("rook pos after move: %s" % [rook.grid_pos])
			print("pawn pos after move: %s" % [pawn.grid_pos])
			stage = Stage.SHOT_2

		Stage.SHOT_2:
			_screenshot(OUT_DIR + "2_after_moving_frozen_pieces.png")
			stage = Stage.DONE

		Stage.DONE:
			print(">>> PREVIEW_BADGE_ALIGNMENT_DONE <<<")
			return true

	return false

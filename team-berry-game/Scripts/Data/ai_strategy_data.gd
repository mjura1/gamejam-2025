# res://Scripts/Data/ai_strategy_data.gd
# Autoload. Prebere GameParameters/ai_difficulty.json (tier bools/params za
# Scripts/AI/enemy_ai_strategy.gd) po vzoru item_data.gd/curse_data.gd ("1 avtoload
# prebere JSON" vzorec) - en cache-ran EnemyAIStrategy na tier (get_strategy).
extends Node

const AI_DIFFICULTY_PATH := "res://GameParameters/ai_difficulty.json"

var _tiers: Dictionary = {}
var _strategy_cache: Dictionary = {}

func _ready():
	_tiers = _load_json(AI_DIFFICULTY_PATH)

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("AiStrategyData: manjka datoteka %s" % path)
		return {}

	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("AiStrategyData: neveljaven JSON v %s" % path)
	return {}

# tier: "normal"|"hard"|"extreme"|"impossible" (SettingsManager.VALID_AI_DIFFICULTIES).
# Neznan tier pade nazaj na "normal" (najbolj varno privzeto obnašanje - glej
# SettingsManager.ai_difficulty privzeto vrednost).
func get_strategy(tier: String) -> EnemyAIStrategy:
	if not _strategy_cache.has(tier):
		var params: Dictionary = _tiers.get(tier, _tiers.get("normal", {}))
		_strategy_cache[tier] = EnemyAIStrategy.new(params)
	return _strategy_cache[tier]

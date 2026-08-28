class_name AttackSoundResolver extends RefCounted

## AttackSoundResolver - 攻擊音效節點解析器
##
## 職責: 把 `attack_type`（例如 "st_lp" / "cr_hk" / "jump_mp"）對應到角色場景
##       內部的 AudioStreamPlayer 節點名稱，並統一負責播放。
##
## 三組音效：
##
## 1. 擊中音效（Hit SFX）— 按「攻擊按鈕」分開，角色無關
##    lp → LPSoundPlayer、mp → MPSoundPlayer、hp → HPSoundPlayer
##    lk → LKSoundPlayer、mk → MKSoundPlayer、hk → HKSoundPlayer
##    只在真正打中對手（未被格擋）時播放。
##    重拳（st/cr/jump_hp）**一律**播該角色場景的 HPSoundPlayer；
##    重踢（st/cr/jump_hk）**一律**播該角色場景的 HKSoundPlayer。
##    兩者絕不可對調，也不可因傷害高低改播對方的節點。
##
## 2. 揮空音效（Whoosh SFX）— 按「攻擊強度」分開
##    輕(l) → LWhooshSoundPlayer、中(m) → MWhooshSoundPlayer、重(h) → HWhooshSoundPlayer
##    攻擊發動（_execute_attack）時即播放，不論有否打中對手。
##
## 3. 普通攻擊喊聲（Attack Grunt）— 按「攻擊強度」分開
##    輕(l) → AttackGrunt_l1、中(m) → AttackGrunt_m1、重(h) → AttackGrunt_h1
##    出招當下播放，不論有否打中對手。
##    機制：以角色 attack_grunt_chance（@export，預設 50%）機率才播；
##    若喊聲播放期間被對方打中則立刻中斷。
##
## 向後兼容：
## - 若角色場景未加設對應節點（例如仍是舊設定的 WOO），
##   擊中音效會自動回退到舊有的 HitSoundPlayer / HeavyHitSoundPlayer；
##   揮空音效與攻擊喊聲則靜默略過，不會產生錯誤。
## - 特殊招式（fireball / dp / powerkk …）不屬於 6 按鈕普通攻擊，
##   其擊中音效同樣走舊有的傷害判定回退路徑，
##   而招式本身的語音由 MoveSet 的 `sound_type` 負責。

# ── 攻擊按鈕 → 擊中音效節點 ──────────────────────────────
const HIT_SOUND_PLAYERS: Dictionary = {
	"lp": "LPSoundPlayer",
	"mp": "MPSoundPlayer",
	"hp": "HPSoundPlayer",
	"lk": "LKSoundPlayer",
	"mk": "MKSoundPlayer",
	"hk": "HKSoundPlayer",
}

# ── 攻擊強度 → 揮空音效節點 ──────────────────────────────
const WHOOSH_SOUND_PLAYERS: Dictionary = {
	"l": "LWhooshSoundPlayer",
	"m": "MWhooshSoundPlayer",
	"h": "HWhooshSoundPlayer",
}

# ── 攻擊強度 → 普通攻擊喊聲節點 ──────────────────────────
const GRUNT_SOUND_PLAYERS: Dictionary = {
	"l": "AttackGrunt_l1",
	"m": "AttackGrunt_m1",
	"h": "AttackGrunt_h1",
}

# 普通攻擊喊聲播放機率改由角色場景的 `attack_grunt_chance`（@export，預設 0.5）
# 控制，可在編輯器調整，程式不再寫死。預設值保留 0.5 以維持既有行為。

# ── 舊有（回退用）音效節點 ────────────────────────────────
const LEGACY_HIT_SOUND_PLAYER: String = "HitSoundPlayer"
const LEGACY_HEAVY_HIT_SOUND_PLAYER: String = "HeavyHitSoundPlayer"
const BLOCK_SOUND_PLAYER: String = "BlockSoundPlayer"
const HEAVY_BLOCK_SOUND_PLAYER: String = "HeavyBlockSoundPlayer"

# 傷害 >= 此值視為「強力」攻擊（只用於沒有專屬節點時的回退判定）
const HEAVY_HIT_DAMAGE_THRESHOLD: float = 8.0

# 攻擊喊聲專用 RNG，避免消耗 AI 決策用的全域 randf()
static var _grunt_rng: RandomNumberGenerator = null


static func get_button_id(attack_type: String) -> String:
	"""
	從 attack_type 取出 6 按鈕代號（lp/mp/hp/lk/mk/hk）。

	"st_lp" → "lp"、"cr_hk" → "hk"、"jump_mp" → "mp"
	非普通攻擊（"throw_enter"、"fireballL"、"powerkk" …）回傳 ""。
	"""
	if attack_type.is_empty() or attack_type == "none":
		return ""
	var parts: PackedStringArray = attack_type.to_lower().split("_", false)
	if parts.size() < 2:
		return ""
	var button: String = parts[parts.size() - 1]
	return button if HIT_SOUND_PLAYERS.has(button) else ""


static func get_strength_id(attack_type: String) -> String:
	"""從 attack_type 取出強度代號：l（輕）/ m（中）/ h（重）；非普通攻擊回傳 ""。"""
	var button: String = get_button_id(attack_type)
	return button.substr(0, 1) if button != "" else ""


static func get_hit_sound_player_name(attack_type: String) -> String:
	"""回傳該攻擊對應的擊中音效節點名稱；非普通攻擊回傳 ""。"""
	var button: String = get_button_id(attack_type)
	if button.is_empty():
		return ""
	return String(HIT_SOUND_PLAYERS[button])


static func get_whoosh_sound_player_name(attack_type: String) -> String:
	"""回傳該攻擊對應的揮空音效節點名稱；非普通攻擊回傳 ""。"""
	var strength: String = get_strength_id(attack_type)
	if strength.is_empty():
		return ""
	return String(WHOOSH_SOUND_PLAYERS[strength])


static func get_grunt_sound_player_name(attack_type: String) -> String:
	"""回傳該攻擊對應的普通攻擊喊聲節點名稱；非普通攻擊回傳 ""。"""
	var strength: String = get_strength_id(attack_type)
	if strength.is_empty():
		return ""
	return String(GRUNT_SOUND_PLAYERS[strength])


static func get_legacy_hit_sound_player_name(damage: float) -> String:
	"""舊有的擊中音效節點（按傷害選普通 / 強力），供沒有專屬節點時回退使用。"""
	return LEGACY_HEAVY_HIT_SOUND_PLAYER if damage >= HEAVY_HIT_DAMAGE_THRESHOLD else LEGACY_HIT_SOUND_PLAYER


static func get_block_sound_player_name(damage: float) -> String:
	"""格擋音效節點（維持原有的傷害判定：>= 8 用強力格擋音效）。"""
	return HEAVY_BLOCK_SOUND_PLAYER if damage >= HEAVY_HIT_DAMAGE_THRESHOLD else BLOCK_SOUND_PLAYER


static func play(owner_node: Node, player_name: String) -> bool:
	"""
	播放 owner_node 底下名為 player_name 的音效節點。

	回傳 true 表示成功播放；節點不存在或名稱為空則回傳 false（不報錯，方便回退）。
	"""
	if owner_node == null or player_name.is_empty():
		return false
	var sound_player: Node = owner_node.get_node_or_null(player_name)
	if sound_player == null or not sound_player.has_method("play"):
		return false
	sound_player.play()
	return true


static func stop(owner_node: Node, player_name: String) -> bool:
	"""停止 owner_node 底下名為 player_name 的音效節點。節點不存在則靜默略過。"""
	if owner_node == null or player_name.is_empty():
		return false
	var sound_player: Node = owner_node.get_node_or_null(player_name)
	if sound_player == null or not sound_player.has_method("stop"):
		return false
	sound_player.stop()
	return true


static func play_hit_sound(owner_node: Node, attack_type: String, damage: float) -> bool:
	"""
	播放「擊中」音效：優先使用攻擊類型專屬節點。

	重拳（*_hp）→ HPSoundPlayer，重踢（*_hk）→ HKSoundPlayer，
	兩者絕不可對調。找不到專屬節點時才回退到舊有的
	HitSoundPlayer / HeavyHitSoundPlayer（按傷害判定）。
	"""
	if play(owner_node, get_hit_sound_player_name(attack_type)):
		return true
	return play(owner_node, get_legacy_hit_sound_player_name(damage))


static func play_block_sound(owner_node: Node, damage: float) -> bool:
	"""播放「格擋」音效（行為與改動前一致）。"""
	return play(owner_node, get_block_sound_player_name(damage))


static func play_whoosh_sound(owner_node: Node, attack_type: String) -> bool:
	"""
	播放「揮空 / 出招」音效：按輕中重強度播放，不論攻擊有否打中對手。
	角色場景未加設對應節點時靜默略過。
	"""
	return play(owner_node, get_whoosh_sound_player_name(attack_type))


static func _should_play_grunt(chance: float) -> bool:
	if _grunt_rng == null:
		_grunt_rng = RandomNumberGenerator.new()
		_grunt_rng.randomize()
	return _grunt_rng.randf() < chance


static func play_attack_grunt(owner_node: Node, attack_type: String, chance: float = 0.5) -> bool:
	"""
	播放普通攻擊喊聲（輕/中/重 → AttackGrunt_l1/m1/h1）。

	不論之後有否打中對手；非普通攻擊（摔投、特殊招式）不播放。
	以 `chance` 機率才真正播放（由角色的 attack_grunt_chance 傳入，編輯器可調）。
	角色場景未加設對應節點時靜默略過。
	若上一次喊聲尚未結束，先中斷再播新的，避免疊聲。
	"""
	var grunt_name: String = get_grunt_sound_player_name(attack_type)
	if grunt_name.is_empty():
		return false
	if not _should_play_grunt(chance):
		return false
	stop_attack_grunts(owner_node)
	return play(owner_node, grunt_name)


static func stop_attack_grunts(owner_node: Node) -> void:
	"""中斷角色正在播放的普通攻擊喊聲（被對方打中時呼叫）。"""
	for grunt_name in GRUNT_SOUND_PLAYERS.values():
		stop(owner_node, String(grunt_name))

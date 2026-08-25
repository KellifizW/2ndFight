extends SceneTree
## 2ndFight Frame 測試 Runner（Stage 0 安全網）
##
## 執行方式（在 repo 根目錄）:
##   godot --headless --path . -s res://tests/frame_tests/run_tests.gd
## 或:
##   bash tests/frame_tests/run_frame_tests.sh
##
## 退出碼: 0 = 全部通過, 1 = 有用例失敗（含 world 載入失敗的環境錯誤）
##
## 設計:
## - 每個用例生成一個全新的 world（狀態隔離）
## - 物理為固定 120 FPS tick（project.godot），測試用 await physics_frame 推進
## - 輸入透過 Input.action_press/release 餵入（與現有 tests/runtime_*.gd 同模式）
## - 測試輸出直接 print（不經過 Debug logger，確保 runner 結果一定可見）

const WORLD_SCENE := "res://scenes/gameplay/world.tscn"

const CASES: Array = [
	"res://tests/frame_tests/cases/test_01_world_spawn.gd",
	"res://tests/frame_tests/cases/test_02_walk_movement.gd",
	"res://tests/frame_tests/cases/test_03_jump_and_landing.gd",
	"res://tests/frame_tests/cases/test_04_ground_attack_frames.gd",
	"res://tests/frame_tests/cases/test_05_hit_damage_hitstun.gd",
	"res://tests/frame_tests/cases/test_06_block_no_damage.gd",
	"res://tests/frame_tests/cases/test_07_fireball_spawn.gd",
	"res://tests/frame_tests/cases/test_08_frame_counter_determinism.gd",
	"res://tests/frame_tests/cases/test_09_debug_logger_default_off.gd",
	"res://tests/frame_tests/cases/test_10_hitstun_decrement.gd",
	"res://tests/frame_tests/cases/test_11_landing_lock_frames.gd",
	"res://tests/frame_tests/cases/test_12_dash_frames.gd",
	"res://tests/frame_tests/cases/test_13_combo_requires_active_stun.gd",
	"res://tests/frame_tests/cases/test_14_dash_window_expires.gd",
	"res://tests/frame_tests/cases/test_15_vfx_preloader_character_vfx.gd",
	"res://tests/frame_tests/cases/test_16_landing_lock_is_frame_based.gd",
]

var _passed: int = 0
var _failed: int = 0
var _failed_names: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_all")

func _run_all() -> void:
	_ensure_autoloads()
	print("")
	print("======================================================================")
	print(" 2ndFight Frame Tests — deterministic physics-frame verification")
	print(" physics ticks: %d/s" % Engine.physics_ticks_per_second)
	print("======================================================================")

	for path in CASES:
		var script: Script = load(path)
		if script == null:
			_failed += 1
			_failed_names.append(path + " (load failed)")
			print("\n--- %s" % path)
			print("  ✗ FAIL: script load failed")
			continue

		var world = await _spawn_world()
		if world == null:
			_failed += 1
			_failed_names.append(path.get_file() + " (world spawn failed)")
			print("\n--- %s" % path)
			print("  ✗ FAIL: world failed to spawn")
			continue

		var tc = script.new()
		tc.world = world
		tc.p1 = world.player_a
		tc.p2 = world.player_b

		print("\n--- %s" % script.resource_path.get_file().get_basename())
		var ok: bool = await tc.run()

		if ok and not tc.has_failures():
			_passed += 1
			print("  ✓ PASS")
		else:
			_failed += 1
			_failed_names.append(script.resource_path.get_file().get_basename())
			print("  ✗ FAIL")
			print(tc.failure_report())

		await _free_world(world)
		# 清空殘留輸入，避免污染下一用例
		_release_all_inputs()

	print("")
	print("======================================================================")
	print(" RESULT: %d passed, %d failed, %d total" % [_passed, _failed, CASES.size()])
	if _failed > 0:
		print(" Failed:")
		for name in _failed_names:
			print("   - " + name)
	print("======================================================================")
	quit(1 if _failed > 0 else 0)

## 生成全新 world；失敗回傳 null
func _spawn_world() -> Node:
	var ps: PackedScene = load(WORLD_SCENE)
	if ps == null:
		print("  ERROR: cannot load %s" % WORLD_SCENE)
		return null
	var world = ps.instantiate()
	# 明確指定對戰角色（與選角畫面預設一致：DAV vs DEN）
	# ⚠️ 必须在 add_child(world) 之前：world._ready() 會讀取 SelectedCharacters
	if root.has_node("SelectedCharacters"):
		var sc = root.get_node("SelectedCharacters")
		sc.p1_character = load("res://characters/DAV.character.tres")
		sc.p2_character = load("res://characters/DEN.character.tres")
	# 模擬正常遊戲：world 是 current_scene（fireball 等生成節點會加到 current_scene）
	root.add_child(world)
	current_scene = world
	await physics_frame
	if world.get("player_a") == null or world.get("player_b") == null:
		print("  ERROR: players not spawned")
		await _free_world(world)
		return null
	return world

func _free_world(world: Node) -> void:
	if is_instance_valid(world):
		current_scene = null
		world.queue_free()
		await physics_frame
		await physics_frame

## 若 -s 模式未載入 autoload，手動補上（belt-and-suspenders）
func _ensure_autoloads() -> void:
	if not root.has_node("SelectedCharacters"):
		var sc = load("res://characters/CharacterSelectData.gd").new()
		sc.name = "SelectedCharacters"
		root.add_child(sc)
	if not root.has_node("Debug"):
		var dbg = load("res://scripts/core/DebugLogger.gd").new()
		dbg.name = "Debug"
		root.add_child(dbg)

func _release_all_inputs() -> void:
	for action in InputMap.get_actions():
		Input.action_release(action)

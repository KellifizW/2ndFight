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
	"res://tests/frame_tests/cases/test_17_ai_toggle_drives_player.gd",
	"res://tests/frame_tests/cases/test_18_stun_lock_is_frame_based.gd",
	"res://tests/frame_tests/cases/test_19_hit_lock_freezes_in_hitstop.gd",
	"res://tests/frame_tests/cases/test_20_block_lock_is_frame_based.gd",
	"res://tests/frame_tests/cases/test_21_combo_window_is_frame_based.gd",
	"res://tests/frame_tests/cases/test_22_time_conversion_boundaries.gd",
	"res://tests/frame_tests/cases/test_23_ai_decision_timers_in_frames.gd",
	"res://tests/frame_tests/cases/test_24_double_tap_window_frames.gd",
	"res://tests/frame_tests/cases/test_25_state_machine_invariants.gd",
	"res://tests/frame_tests/cases/test_26_state_matches_animation_chain.gd",
	"res://tests/frame_tests/cases/test_27_crossup_facing_after_landing.gd",
	"res://tests/frame_tests/cases/test_28_landing_input_instant_skip.gd",
	"res://tests/frame_tests/cases/test_29_attack_state_is_paired.gd",
	"res://tests/frame_tests/cases/test_30_attack_gates_match_legacy.gd",
	"res://tests/frame_tests/cases/test_31_movement_gates_match_legacy.gd",
	"res://tests/frame_tests/cases/test_32_ai_attack_type_parity.gd",
	"res://tests/frame_tests/cases/test_34_hit_reaction_gates_match_legacy.gd",
	"res://tests/frame_tests/cases/test_35_ai_backdash_blocked_while_crouching.gd",
	"res://tests/frame_tests/cases/test_36_block_gates_match_legacy.gd",
	"res://tests/frame_tests/cases/test_37_hitstop_decoupled.gd",
	"res://tests/frame_tests/cases/test_38_long_hitstop_single_attack.gd",
	"res://tests/frame_tests/cases/test_39_attacker_pose_frozen_on_hit.gd",
	"res://tests/frame_tests/cases/test_40_animation_chain_matches_legacy.gd",
	"res://tests/frame_tests/cases/test_41_den_fireball_resource_source.gd",
	"res://tests/frame_tests/cases/test_42_dash_commitment.gd",
	"res://tests/frame_tests/cases/test_43_woo_fireball.gd",
	"res://tests/frame_tests/cases/test_44_air_reset.gd",
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

		# 允許個別用例指定對戰角色（例如 WOO fireball 測試需要 WOO 上場）。
		# 用例可宣告 `func case_characters() -> Array` 回傳 [p1, p2] 兩個
		# .character.tres 路徑；未宣告時維持預設 DAV vs DEN。
		var case_characters: Array = []
		var tc_probe = script.new()
		if tc_probe and tc_probe.has_method("case_characters"):
			case_characters = tc_probe.case_characters()
		tc_probe = null  # RefCounted：釋放參照後自動回收，勿手動 free()

		var world = await _spawn_world(case_characters)
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
			var case_name: String = script.resource_path.get_file().get_basename()
			_failed_names.append(case_name)
			print("  ✗ FAIL")
			print(tc.failure_report())
			_emit_ci_annotation(case_name, tc.failure_report(), script.resource_path)

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

	# 摘要也送一份到 annotations，讓 job 頁面直接看得到「哪幾個掛了」。
	if _failed > 0 and OS.get_environment("GITHUB_ACTIONS") == "true":
		print("::error title=frame tests: %d/%d failed::%s" % [
			_failed, CASES.size(), ", ".join(_failed_names)])

	# 收尾：釋放測試期間手動補上的 autoload 替身並等待 queue_free 生效，
	# 降低 Godot 結束時的節點/資源洩漏警告（不影響任何測試結果）。
	await _release_autoload_stubs()
	quit(1 if _failed > 0 else 0)

## 以 GitHub Actions workflow command 形式輸出失敗，讓它出現在 job 的
## ANNOTATIONS 區塊（而不只是埋在 raw log 裡）。
##
## 為什麼需要：raw job log 存放在 Azure blob CDN，某些受限網路環境
## （例如 agent sandbox 的 egress allowlist）抓不到，只能看到
## 「Process completed with exit code 1」而不知道哪個用例、為什麼失敗。
## annotation 走 GitHub API，取得成本低得多，能大幅縮短除錯迴圈。
##
## 只在 CI 環境（GITHUB_ACTIONS=true）輸出，本地執行不受影響。
func _emit_ci_annotation(case_name: String, report: String, res_path: String) -> void:
	if OS.get_environment("GITHUB_ACTIONS") != "true":
		return
	# workflow command 必須單行：換行以 %0A 編碼，並跳脫 % 與 CR。
	var message: String = report.strip_edges()
	if message.is_empty():
		message = "case reported failure without detail"
	message = message.replace("%", "%25").replace("\r", "").replace("\n", "%0A")
	var file_hint: String = res_path.replace("res://", "")
	print("::error file=%s,title=frame test failed: %s::%s" % [
		file_hint, case_name, message])

## 釋放 _ensure_autoloads 補上的根節點替身（SelectedCharacters / Debug）
func _release_autoload_stubs() -> void:
	for stub_name in ["SelectedCharacters", "Debug"]:
		var stub: Node = root.get_node_or_null(stub_name)
		if stub:
			stub.queue_free()
	await physics_frame
	await physics_frame

## 生成全新 world；失敗回傳 null
## case_characters 可選：回傳 [p1, p2] 的 .character.tres 路徑（見 _run_all 的說明）
func _spawn_world(case_characters: Array = []) -> Node:
	var p1_char_path: String = "res://characters/DAV.character.tres"
	var p2_char_path: String = "res://characters/DEN.character.tres"
	if case_characters.size() >= 2:
		p1_char_path = str(case_characters[0])
		p2_char_path = str(case_characters[1])
	var ps: PackedScene = load(WORLD_SCENE)
	if ps == null:
		print("  ERROR: cannot load %s" % WORLD_SCENE)
		return null
	var world = ps.instantiate()
	# 明確指定對戰角色（預設與選角畫面一致：DAV vs DEN）
	# ⚠️ 必须在 add_child(world) 之前：world._ready() 會讀取 SelectedCharacters
	if root.has_node("SelectedCharacters"):
		var sc = root.get_node("SelectedCharacters")
		sc.p1_character = load(p1_char_path)
		sc.p2_character = load(p2_char_path)
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

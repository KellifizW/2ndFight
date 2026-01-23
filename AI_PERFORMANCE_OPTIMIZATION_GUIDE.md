# AI Performance Optimization Guide

## Executive Summary

This guide provides a comprehensive optimization plan for the 2ndFight AI system to address performance degradation after implementing the advanced AI opponent system. The proposed optimizations are expected to improve performance by **30-50%** through caching, intelligent decision intervals, and reduced redundant calculations.

---

## 📋 Table of Contents

1. [Current Performance Issues](#current-performance-issues)
2. [Optimization Roadmap](#optimization-roadmap)
3. [Phase 1: Quick Wins](#phase-1-quick-wins)
4. [Phase 2: Medium-Term Improvements](#phase-2-medium-term-improvements)
5. [Phase 3: Advanced Optimizations](#phase-3-advanced-optimizations)
6. [Implementation Checklist](#implementation-checklist)
7. [Performance Monitoring](#performance-monitoring)

---

## 🔍 Current Performance Issues

### Issue #1: No Decision Caching (CRITICAL)
**File:** `ai/AIDecisionLayers.gd`

**Problem:**
- AI recalculates all 5 decision layers every frame (60 FPS = 300 evaluations/second)
- Each evaluation includes:
  - Distance calculations
  - Threat assessments
  - Frame data lookups
  - Combo availability checks
  - Space control evaluations

**Impact:** High CPU usage, visible framerate drops during AI combat

---

### Issue #2: Excessive Scene Tree Queries
**File:** `ai/ThreatAssessment.gd`

**Problem:**
```gdscript
# Called EVERY frame
var projectiles = get_tree().get_nodes_in_group("fireball")
```

**Impact:** Scales poorly with multiple projectiles in the scene

---

### Issue #3: Input Buffer Overhead for AI
**File:** `PlayerController.gd`

**Problem:**
- AI-controlled players still record input every frame
- 7+ input action checks per frame that are never used

**Impact:** Wasted CPU cycles on unnecessary input polling

---

### Issue #4: Short Decision Interval
**File:** `ai/ai_behavior.gd`

**Problem:**
```gdscript
const DECISION_INTERVAL: float = 0.15  # Re-evaluate every 9 frames
```

**Impact:** AI thinks too frequently, causing unnecessary recalculations

---

### Issue #5: Unoptimized Frame Data Lookups
**File:** `ai/FrameDataManager.gd`

**Problem:**
- Nested dictionary lookups for every frame data query
- No pre-computed values

**Impact:** Accumulated overhead from frequent lookups

---

## 🗺️ Optimization Roadmap

### Phase 1: Quick Wins (1-2 days)
**Expected Improvement:** 30-40% performance gain  
**Risk Level:** Low  
**Required Testing:** Medium

### Phase 2: Medium-Term (1 week)
**Expected Improvement:** Additional 10-15% gain  
**Risk Level:** Medium  
**Required Testing:** High

### Phase 3: Advanced (2-3 weeks)
**Expected Improvement:** Additional 5-10% gain  
**Risk Level:** High  
**Required Testing:** Extensive

---

## 🚀 Phase 1: Quick Wins

### 1.1 Implement Decision Caching

**File:** `ai/AIDecisionLayers.gd`

**Add these variables:**
```gdscript
# ============================================================
# DECISION CACHING SYSTEM
# ============================================================
var decision_cache: Decision = null
var cache_timer: float = 0.0
const CACHE_DURATION: float = 0.1  # Cache for 6 frames (~100ms)

@export var enable_decision_cache: bool = true
@export var cache_duration_override: float = 0.1
```

**Modify `get_best_decision()` method:**
```gdscript
func get_best_decision(ai_player: Player, opponent: Player) -> Decision:
	# Use cached decision if valid
	if enable_decision_cache and cache_timer > 0 and decision_cache != null:
		return decision_cache
	
	# Original decision calculation logic here
	var decisions: Array[Decision] = []
	var filtered_count = 0
	
	# Layer 1: Survival
	var survival = _evaluate_survival_layer(ai_player, opponent)
	if survival and survival.priority >= 95:
		if survival.action in restricted_moves:
			survival.action = "stand_block"
			survival.reason = "Survival (restricted move fallback)"
		_cache_decision(survival)
		return survival
	elif survival:
		if survival.action in restricted_moves:
			filtered_count += 1
		else:
			decisions.append(survival)
	
	# ... rest of the layers ...
	
	# Select best decision
	var best_decision = _select_best_decision(decisions)
	_cache_decision(best_decision)
	return best_decision

func _cache_decision(decision: Decision) -> void:
	"""Cache the decision for reuse"""
	if enable_decision_cache:
		decision_cache = decision
		cache_timer = cache_duration_override if cache_duration_override > 0 else CACHE_DURATION

func _process(delta: float) -> void:
	"""Update cache timer"""
	if cache_timer > 0:
		cache_timer -= delta
```

**Expected Gain:** 15-20% CPU reduction

---

### 1.2 Cache Projectile References

**File:** `ai/ThreatAssessment.gd`

**Add these variables:**
```gdscript
# ============================================================
# PROJECTILE TRACKING CACHE
# ============================================================
var tracked_projectiles: Array = []
var projectile_check_timer: float = 0.0
const PROJECTILE_CHECK_INTERVAL: float = 0.15  # Check every 9 frames

@export var enable_projectile_cache: bool = true
```

**Replace `_evaluate_projectile_threat()` method:**
```gdscript
func _evaluate_projectile_threat(ai_player: Player, opponent: Player) -> ThreatInfo:
	var threat = ThreatInfo.new()
	
	# Refresh projectile list periodically
	if enable_projectile_cache:
		if projectile_check_timer <= 0:
			tracked_projectiles = get_tree().get_nodes_in_group("fireball")
			projectile_check_timer = PROJECTILE_CHECK_INTERVAL
			
			if debug_mode:
				print("[THREAT EVAL] Refreshed projectile cache: %d fireballs" % tracked_projectiles.size())
			
		projectile_check_timer -= get_process_delta_time()
	else:
		# Fallback to original behavior
		tracked_projectiles = get_tree().get_nodes_in_group("fireball")
		
	# Process cached projectiles
	for proj in tracked_projectiles:
		# Validate projectile still exists
		if not is_instance_valid(proj):
			continue
		
		# ... existing threat evaluation logic ...
	
	return threat
```

**Expected Gain:** 10-15% reduction in scene tree queries

---

### 1.3 Skip Input Buffer for AI Players

**File:** `PlayerController.gd`

**Modify `_physics_process()` method:**
```gdscript
func _physics_process(_delta: float) -> void:
	# Skip input recording for AI-controlled players
	var player_node = get_parent()
	if player_node and player_node is Player and player_node.is_ai_controlled:
		return
	
	# Record button presses into buffer
	var suffix = "_p2" if player_seat == "player_b" else ""
	
	# Record all button presses (only for human players now)
	if Input.is_action_just_pressed("st_mp" + suffix):
		input_buffer.record_input("st_mp")
	if Input.is_action_just_pressed("st_mk" + suffix):
		input_buffer.record_input("st_mk")
	# ... rest of input recording ...
```

**Expected Gain:** 5% CPU reduction for AI players

---

### 1.4 Increase Decision Interval

**File:** `ai/ai_behavior.gd`

**Modify constant:**
```gdscript
# OLD
const DECISION_INTERVAL: float = 0.15  # Re-evaluate every 9 frames

# NEW
const DECISION_INTERVAL: float = 0.25  # Re-evaluate every 15 frames at 60fps

@export var decision_interval_override: float = 0.25  # Allow tuning in Inspector
```

**Update decision cooldown logic in `_physics_process()`:**
```gdscript
func _physics_process(delta: float) -> void:
	if not ai_enabled or not parent:
		return
	
	# Use override if set
	var active_interval = decision_interval_override if decision_interval_override > 0 else DECISION_INTERVAL
	
	# Update commitment timer
	if commitment_timer > 0:
		commitment_timer -= delta
		if commitment_timer <= 0:
			current_committed_action = ""
			committed_input = {}
	
	# Update decision cooldown
	if decision_cooldown > 0:
		decision_cooldown -= delta
		return
	
	# Make new decision
	decision_cooldown = active_interval
	# ... rest of decision logic ...
```

**Expected Gain:** 5-10% CPU reduction

---

## 🔧 Phase 2: Medium-Term Improvements

### 2.1 Pre-Compute Frame Data Lookups

**File:** `ai/FrameDataManager.gd`

**Add cached lookups:**
```gdscript
class_name FrameDataManager extends Node

# Original database
var frame_database: Dictionary = {
	"st_mp": {"startup": 5, "active": 3, "recovery": 8, "total": 16},
	"st_mk": {"startup": 7, "active": 4, "recovery": 10, "total": 21},
	# ... rest of data ...
}

# ============================================================
# PRE-COMPUTED CACHES
# ============================================================
var startup_cache: Dictionary = {}
var total_cache: Dictionary = {}
var active_cache: Dictionary = {}
var recovery_cache: Dictionary = {}

func _ready() -> void:
	_build_caches()

func _build_caches() -> void:
	"""Pre-compute all frame data for fast lookups"""
	for move_name in frame_database:
		var data = frame_database[move_name]
		startup_cache[move_name] = data.get("startup", 10)
		total_cache[move_name] = data.get("total", 30)
		active_cache[move_name] = data.get("active", 3)
		recovery_cache[move_name] = data.get("recovery", 10)
		
		print("[FRAME DATA] Pre-computed %d move entries" % startup_cache.size())

# Replace existing methods with cached lookups
func get_startup_frames(move_name: String) -> int:
	return startup_cache.get(move_name, 10)

func get_total_frames(move_name: String) -> int:
	return total_cache.get(move_name, 30)

func get_active_frames(move_name: String) -> int:
	return active_cache.get(move_name, 3)

func get_recovery_frames(move_name: String) -> int:
	return recovery_cache.get(move_name, 10)
```

**Expected Gain:** 3-5% reduction in lookup overhead

---

### 2.2 Adaptive Decision Intervals

**File:** `ai/ai_behavior.gd`

**Add adaptive system:**
```gdscript
# ============================================================
# ADAPTIVE DECISION INTERVAL SYSTEM
# ============================================================
@export var enable_adaptive_interval: bool = true

const INTERVAL_CRITICAL: float = 0.1   # React fast to danger
const INTERVAL_HIGH: float = 0.15      # Normal reaction
const INTERVAL_NORMAL: float = 0.25    # Relaxed thinking
const INTERVAL_SAFE: float = 0.3       # Very relaxed

var current_adaptive_interval: float = INTERVAL_NORMAL

func _adjust_decision_interval(threat_level: ThreatAssessment.ThreatLevel, distance: float) -> void:
	"""Dynamically adjust decision speed based on game state"""
	if not enable_adaptive_interval:
		return
	
	match threat_level:
		ThreatAssessment.ThreatLevel.CRITICAL:
			current_adaptive_interval = INTERVAL_CRITICAL
		ThreatAssessment.ThreatLevel.HIGH:
			current_adaptive_interval = INTERVAL_HIGH
		ThreatAssessment.ThreatLevel.MEDIUM:
			current_adaptive_interval = INTERVAL_NORMAL
		_:
			# Safe - adjust by distance
			if distance > 300:
				current_adaptive_interval = INTERVAL_SAFE
			else:
				current_adaptive_interval = INTERVAL_NORMAL

func _physics_process(delta: float) -> void:
	if not ai_enabled or not parent:
		return
	
	# ... existing timer updates ...
	
	# Use adaptive interval
	var active_interval = current_adaptive_interval if enable_adaptive_interval else DECISION_INTERVAL
	
	if decision_cooldown > 0:
		decision_cooldown -= delta
		return
	
	# Make decision and adjust interval
	var threat = threat_system.evaluate_threats(parent, opponent) if threat_system else null
	var distance = abs(parent.global_position.x - opponent.global_position.x)
	
	if threat:
		_adjust_decision_interval(threat.level, distance)
	
	decision_cooldown = active_interval
	# ... rest of decision logic ...
```

**Expected Gain:** 5-8% adaptive CPU reduction

---

### 2.3 Optimize HitboxCache Initialization

**File:** `ai/HitboxCache.gd`

**Add lazy loading:**
```gdscript
# ============================================================
# LAZY LOADING SYSTEM
# ============================================================
var lazy_loading_enabled: bool = true
var characters_to_cache: Array[String] = []
var cache_progress: int = 0

func _initialize_cache() -> void:
	"""Initialize with lazy loading support"""
	var start_time = Time.get_ticks_msec()
	
	var players = get_tree().get_nodes_in_group("players")
	
	if players.is_empty():
		if debug_mode:
			print("[HITBOX CACHE] No players found, deferring initialization")
			call_deferred("_initialize_cache")
			return
		
	if lazy_loading_enabled:
		# Queue characters for lazy loading
		for player in players:
			var char_id = player.character_id if "character_id" in player else "UNKNOWN"
			if char_id not in characters_to_cache:
				characters_to_cache.append(char_id)
			
			# Start lazy loading
			_lazy_load_next_character()
		else:
			# Original immediate loading
			_load_all_characters_immediate(players)

func _lazy_load_next_character() -> void:
	"""Load one character per frame to avoid lag spikes"""
	if cache_progress >= characters_to_cache.size():
		is_initialized = true
		if debug_mode:
			print("[HITBOX CACHE] Lazy loading complete!")
		return
		
	var char_id = characters_to_cache[cache_progress]
	_scan_character_hitboxes(char_id)
	
	cache_progress += 1
	
	# Schedule next character
	call_deferred("_lazy_load_next_character")
```

**Expected Gain:** Eliminates initialization lag spikes

---

## 🏆 Phase 3: Advanced Optimizations

### 3.1 Spatial Partitioning for Projectiles

**Create new file:** `ai/ProjectileSpatialGrid.gd`

```gdscript
class_name ProjectileSpatialGrid extends Node

# ============================================================
# SPATIAL GRID FOR EFFICIENT PROJECTILE QUERIES
# ============================================================
# Divides the arena into cells to quickly find nearby projectiles

const CELL_SIZE: int = 200  # Grid cell size in pixels

var grid: Dictionary = {}  # Key: cell_id (Vector2i) → Value: Array[Projectile]
var all_projectiles: Array = []

func _ready() -> void:
	add_to_group("projectile_grid")

func register_projectile(proj: Node) -> void:
	"""Add projectile to spatial grid"""
	all_projectiles.append(proj)
	_update_projectile_cell(proj)

func unregister_projectile(proj: Node) -> void:
	"""Remove projectile from spatial grid"""
	all_projectiles.erase(proj)
	var cell_id = _get_cell_id(proj.global_position)
	if grid.has(cell_id):
		grid[cell_id].erase(proj)

func get_nearby_projectiles(position: Vector2, radius: float = 300.0) -> Array:
	"""Get projectiles within radius of position"""
	var nearby: Array = []
	var center_cell = _get_cell_id(position)
	
	# Check center cell and 8 neighboring cells
	for x in range(-1, 2):
		for y in range(-1, 2):
			var cell_id = center_cell + Vector2i(x, y)
			if grid.has(cell_id):
				for proj in grid[cell_id]:
					if is_instance_valid(proj):
						var dist = position.distance_to(proj.global_position)
						if dist <= radius:
							nearby.append(proj)
			
	return nearby

func _update_projectile_cell(proj: Node) -> void:
	"""Update projectile's grid cell"""
	var cell_id = _get_cell_id(proj.global_position)
	if not grid.has(cell_id):
		grid[cell_id] = []
	if proj not in grid[cell_id]:
		grid[cell_id].append(proj)

func _get_cell_id(position: Vector2) -> Vector2i:
	"""Convert world position to grid cell ID"""
	return Vector2i(
		int(position.x / CELL_SIZE),
		int(position.y / CELL_SIZE)
	)

func _physics_process(_delta: float) -> void:
	"""Update projectile positions in grid"""
	for proj in all_projectiles:
		if is_instance_valid(proj):
			_update_projectile_cell(proj)
```

**Update `ThreatAssessment.gd` to use spatial grid:**
```gdscript
func _evaluate_projectile_threat(ai_player: Player, opponent: Player) -> ThreatInfo:
	var threat = ThreatInfo.new()
	
	# Use spatial grid if available
	var spatial_grid = get_tree().get_first_node_in_group("projectile_grid")
	var projectiles: Array = []
	
	if spatial_grid:
		# Fast spatial query
		projectiles = spatial_grid.get_nearby_projectiles(ai_player.global_position, 600.0)
	else:
		# Fallback to cached search
		if projectile_check_timer <= 0:
			tracked_projectiles = get_tree().get_nodes_in_group("fireball")
			projectile_check_timer = PROJECTILE_CHECK_INTERVAL
		projectiles = tracked_projectiles
		
	# ... rest of threat evaluation ...
```

**Expected Gain:** 10-15% for scenes with many projectiles

---

### 3.2 Object Pooling for VFX

**Create new file:** `vfx/VFXPool.gd`

```gdscript
class_name VFXPool extends Node

# ============================================================
# OBJECT POOL FOR VFX (Hit Sparks, Block Effects, etc.)
# ============================================================

var pool: Dictionary = {}  # Key: effect_type → Value: Array[Node]
var pool_size: int = 10

@export var vfx_scenes: Dictionary = {
	"hit_spark": preload("res://vfx_hit.tscn"),
	"block_spark": preload("res://vfx_blk.tscn"),
	# Add more VFX types
}

func _ready() -> void:
	add_to_group("vfx_pool")
	_initialize_pools()

func _initialize_pools() -> void:
	"""Pre-instantiate VFX objects"""
	for effect_type in vfx_scenes:
		pool[effect_type] = []
		for i in range(pool_size):
			var instance = vfx_scenes[effect_type].instantiate()
			instance.visible = false
			add_child(instance)
			pool[effect_type].append(instance)
		
	print("[VFX POOL] Initialized %d effect types" % pool.size())

func spawn_effect(effect_type: String, position: Vector2) -> Node:
	"""Get effect from pool or create new one"""
	if not pool.has(effect_type):
		push_warning("[VFX POOL] Unknown effect type: %s" % effect_type)
		return null
	
	# Find inactive effect
	for effect in pool[effect_type]:
		if not effect.visible:
			effect.global_position = position
			effect.visible = true
			if effect.has_method("restart"):
				effect.restart()
			return effect
	
	# Pool exhausted, create new instance
	var new_effect = vfx_scenes[effect_type].instantiate()
		add_child(new_effect)
		new_effect.global_position = position
		pool[effect_type].append(new_effect)
	return new_effect

func return_to_pool(effect: Node) -> void:
	"""Return effect to pool"""
	effect.visible = false
```

**Expected Gain:** Reduces instantiation overhead by 20-30%

---

## ✅ Implementation Checklist

### Phase 1 (Priority: HIGH)
- [ ] 1.1 Implement decision caching in `AIDecisionLayers.gd`
- [ ] 1.2 Add projectile reference caching in `ThreatAssessment.gd`
- [ ] 1.3 Skip input buffer for AI in `PlayerController.gd`
- [ ] 1.4 Increase decision interval to 0.25s in `ai_behavior.gd`
- [ ] Test Phase 1 changes thoroughly
- [ ] Benchmark performance improvement

### Phase 2 (Priority: MEDIUM)
- [ ] 2.1 Pre-compute frame data lookups in `FrameDataManager.gd`
- [ ] 2.2 Implement adaptive decision intervals in `ai_behavior.gd`
- [ ] 2.3 Add lazy loading to `HitboxCache.gd`
- [ ] Test Phase 2 changes
- [ ] Benchmark cumulative improvements

### Phase 3 (Priority: LOW)
- [ ] 3.1 Create spatial partitioning system for projectiles
- [ ] 3.2 Implement VFX object pooling
- [ ] 3.3 Profile entire AI system for remaining bottlenecks
- [ ] Final performance benchmarking
- [ ] Document final results

---

## 📊 Performance Monitoring

### Add Performance Profiler

**Create new file:** `debug/AIPerformanceMonitor.gd`

```gdscript
extends Node

# ============================================================
# AI PERFORMANCE MONITORING TOOL
# ============================================================

@export var enabled: bool = false
@export var log_interval: float = 5.0  # Log every 5 seconds

var frame_times: Array = []
var decision_times: Array = []
var threat_eval_times: Array = []

var log_timer: float = 0.0

func _ready() -> void:
	if not enabled:
		set_process(false)
		return
		
	add_to_group("ai_profiler")
	print("[AI PROFILER] Monitoring enabled")

func record_decision_time(time_usec: int) -> void:
	decision_times.append(time_usec)

func record_threat_eval_time(time_usec: int) -> void:
	threat_eval_times.append(time_usec)

func _process(delta: float) -> void:
	frame_times.append(delta * 1000.0)  # Convert to ms
		
	log_timer += delta
	if log_timer >= log_interval:
		_print_stats()
		_reset_stats()
		log_timer = 0.0

func _print_stats() -> void:
	if frame_times.is_empty():
		return
		
	var avg_frame_time = _calculate_average(frame_times)
	var avg_decision_time = _calculate_average(decision_times) / 1000.0  # Convert to ms
	var avg_threat_time = _calculate_average(threat_eval_times) / 1000.0
	
	print("\n=== AI Performance Report ===")
	print("Avg Frame Time: %.2f ms (%.1f FPS)" % [avg_frame_time, 1000.0 / avg_frame_time])
	print("Avg Decision Time: %.2f ms" % avg_decision_time)
	print("Avg Threat Eval Time: %.2f ms" % avg_threat_time)
	print("Decision Overhead: %.1f%%" % ((avg_decision_time / avg_frame_time) * 100.0))
	print("============================\n")

func _calculate_average(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var sum: float = 0.0
	for val in arr:
		sum += val
	return sum / arr.size()

func _reset_stats() -> void:
	frame_times.clear()
	decision_times.clear()
	threat_eval_times.clear()
```

### Integrate Profiler

**In `ai_behavior.gd`, add profiling:**
```gdscript
func _make_decision() -> void:
	var start_time = Time.get_ticks_usec()
	
	# ... existing decision logic ...
	
	var end_time = Time.get_ticks_usec()
	var profiler = get_tree().get_first_node_in_group("ai_profiler")
	if profiler:
		profiler.record_decision_time(end_time - start_time)
```

---

## 🎯 Expected Results

### Performance Improvement Summary

| Phase | Optimization | Expected Gain | Risk |
|-------|-------------|---------------|------|
| 1 | Decision Caching | 15-20% | Low |
| 1 | Projectile Cache | 10-15% | Low |
| 1 | Skip AI Input Buffer | 5% | Low |
| 1 | Increase Decision Interval | 5-10% | Low |
| **Phase 1 Total** | | **30-40%** | **Low** |
| 2 | Pre-computed Frame Data | 3-5% | Medium |
| 2 | Adaptive Intervals | 5-8% | Medium |
| 2 | Lazy Hitbox Loading | Eliminates lag spikes | Medium |
| **Phase 2 Total** | | **+10-15%** | **Medium** |
| 3 | Spatial Partitioning | 10-15% | High |
| 3 | VFX Pooling | 5-10% | Medium |
| **Phase 3 Total** | | **+5-10%** | **High** |
| **CUMULATIVE TOTAL** | | **45-65%** | **Varies** |

### Before vs After (Projected)

**Current State:**
- FPS during AI combat: ~45-50 FPS
- Decision calculation: ~2-3ms per frame
- Noticeable stuttering during projectile spawns

**After Phase 1:**
- FPS during AI combat: ~55-60 FPS
- Decision calculation: ~0.8-1.2ms per frame
- Smooth gameplay with minimal stuttering

**After All Phases:**
- FPS during AI combat: Stable 60 FPS
- Decision calculation: ~0.5-0.8ms per frame
- Buttery smooth gameplay even with multiple projectiles

---

## 🛠️ Testing Guidelines

### Unit Testing

Test each optimization individually:

```gdscript
# Test decision caching
func test_decision_cache():
	var ai_layers = AIDecisionLayers.new()
	ai_layers.enable_decision_cache = true
	
	var decision1 = ai_layers.get_best_decision(player_a, player_b)
	var decision2 = ai_layers.get_best_decision(player_a, player_b)
		
	assert(decision1 == decision2, "Cache should return same decision")
	print("✓ Decision cache working")
```

### Integration Testing

Test all optimizations together:
1. Enable all Phase 1 optimizations
2. Run 10 rounds of AI vs AI combat
3. Monitor FPS, frame times, and decision times
4. Compare against baseline (pre-optimization)

### Performance Benchmarking

Use the AI Performance Monitor to track:
- Average FPS
- Decision calculation time
- Threat evaluation time
- Memory usage (via Godot profiler)

---

## 📝 Notes

- Always backup your project before implementing optimizations
- Test each phase thoroughly before moving to the next
- Use git branches for each optimization phase
- Monitor for regression bugs after each change
- Adjust cache durations and intervals based on gameplay feel

---

## 🔗 Related Files

- `ai/AIDecisionLayers.gd` - Main decision system
- `ai/ThreatAssessment.gd` - Threat evaluation
- `ai/ai_behavior.gd` - AI behavior controller
- `ai/FrameDataManager.gd` - Frame data lookups
- `ai/HitboxCache.gd` - Hitbox caching system
- `PlayerController.gd` - Input handling
- `world.gd` - Main game loop

---

## 🤝 Contributing

If you implement any of these optimizations:
1. Document performance changes in this file
2. Add before/after FPS measurements
3. Note any gameplay behavior changes
4. Share insights with the team

---

**Last Updated:** 2026-01-23 05:21:25  
**Author:** GitHub Copilot  
**Version:** 1.0
# Data-Driven Move Configuration Guide

## Overview

The special move system is now **truly data-driven** using Godot's `.tres` (Resource) format. All move properties are stored in external files that can be edited without touching code.

---

## File Structure

```
res://data/
├── SpecialMoveData.gd          ← Move data class definition
└── moves/
    ├── powerkk.tres            ← PowerKK move properties
    ├── spnk.tres               ← Spnk move properties
    ├── super.tres              ← Super move properties
    ├── dp.tres                 ← DP move properties
    ├── hdk.tres                ← HDK move properties
    └── fireball.tres           ← Fireball move properties
```

---

## How to Edit Move Properties

### Method 1: Using the Inspector (Recommended for Non-Programmers)

1. **Open the project in Godot Editor**
2. **Navigate** to `res://data/moves/`
3. **Double-click** the `.tres` file you want to edit (e.g., `powerkk.tres`)
4. **The Inspector panel** shows all editable properties
5. **Modify values** directly in the Inspector
6. **Save** (Ctrl+S) - changes take effect immediately!

### Method 2: Editing the .tres File Directly (For Programmers)

Open any `.tres` file in a text editor:

```
[gd_resource type="Resource" script_class="SpecialMoveData" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/SpecialMoveData.gd" id="1_0mkls"]

[resource]
script = ExtResource("1_0mkls")
move_name = "powerkk"
character_requirement = "DAV"
damage = 12.0                    ← Edit this
knockback = 300.0                ← Or this
duration = 0.933
move_distance = 300.0
```

---

## Editable Properties Reference

### Basic Properties

| Property | Type | Example | Purpose |
|----------|------|---------|---------|
| `move_name` | String | "powerkk" | Move identifier |
| `character_requirement` | String | "DAV" or "DEN" or "*" | Who can use this move |
| `damage` | float | 12.0 | Damage dealt on hit |
| `knockback` | float | 300.0 | Distance pushed on hit |

### Timing Properties

| Property | Type | Example | Purpose |
|----------|------|---------|---------|
| `duration` | float | 0.933 | Total move duration (seconds) |
| `move_distance` | float | 300.0 | Forward distance traveled (pixels) |
| `jump_delay` | float | 0.0667 | Delay before jump (seconds) |
| `jump_speed` | float | -2000.0 | Vertical jump velocity (negative = up) |

### Physics Properties

| Property | Type | Example | Purpose |
|----------|------|---------|---------|
| `gravity` | float | 0.0 | Custom gravity during move (0 = normal) |
| `is_projectile` | bool | false | Whether this is a projectile |
| `penetrable` | bool | false | Can pass through other attacks |

### Special Effects

| Property | Type | Example | Purpose |
|----------|------|---------|---------|
| `is_freeze` | bool | false | Freezes screen on hit |
| `freeze_duration` | float | 0.3 | How long to freeze (seconds) |
| `sound_type` | String | "special" | Sound to play ("special" or "fireball") |

### Knockfly Properties (For DP and Similar)

| Property | Type | Example | Purpose |
|----------|------|---------|---------|
| `knockfly_gravity` | float | 6000000.0 | Gravity during knockfly |
| `knockfly_vertical_speed` | float | -2500.0 | Initial upward knockfly velocity |
| `knockfly_horizontal_speed` | float | 100.0 | Horizontal knockfly speed |

---

## Quick Examples

### Increase PowerKK Damage from 12 to 20

**In Inspector:**
1. Open `res://data/moves/powerkk.tres`
2. Find `Damage` field
3. Change `12.0` → `20.0`
4. Save

**In .tres File:**
```
damage = 20.0
```

### Make Spnk Travel Further

**In Inspector:**
1. Open `res://data/moves/spnk.tres`
2. Find `Move Distance` field
3. Change `250.0` → `400.0`
4. Save

### Add Freeze Effect to Super

**In Inspector:**
1. Open `res://data/moves/super.tres`
2. Find `Is Freeze` field (already `true`)
3. Adjust `Freeze Duration` from `0.3` → `0.5`

---

## How It Works in Code

The MoveSet.gd script automatically loads all `.tres` files:

```gdscript
func _initialize_move_library() -> void:
	var moves = ["powerkk", "super", "dp", "spnk", "hdk", "fireball"]
	
	for move_name in moves:
		var path = "res://data/moves/%s.tres" % move_name
		var move_data = load(path)
		
		if move_data is SpecialMoveData:
			move_library[move_name] = move_data
```

When you use a move:

```gdscript
func _start_special(move_name: String) -> void:
	var move_data: SpecialMoveData = move_library[move_name]
	
	# Access properties from the loaded .tres file
	parent.current_damage = move_data.damage
	parent.fixed_velocity.x = int((move_data.move_distance / move_data.duration) * ...)
```

---

## Adding New Special Moves

To add a new move (e.g., "hadoken"):

1. **Create a new file** `res://data/moves/hadoken.tres`
2. **Copy the content** from an existing move file
3. **Edit the values** to match your new move
4. **Update MoveSet.gd** to include "hadoken" in the moves array:

```gdscript
var moves = ["powerkk", "super", "dp", "spnk", "hdk", "fireball", "hadoken"]
```

5. **Create the move starter** in MoveSet.gd:

```gdscript
func start_hadoken() -> void:
	_start_special("hadoken")
```

---

## Benefits of This Approach

✅ **No Code Changes Required** - Edit properties in Inspector  
✅ **Hot-Reloading** - Changes take effect immediately  
✅ **Designer-Friendly** - Non-programmers can balance moves  
✅ **Easy Prototyping** - Quick iteration on move properties  
✅ **Version Control** - .tres files show property changes clearly  
✅ **Professional Standard** - Used by AAA fighting game studios  

---

## Troubleshooting

### Move doesn't load
- Check the filename matches exactly (case-sensitive on some systems)
- Verify the path is `res://data/moves/[movename].tres`
- Check the console for error messages

### Changes don't take effect
- Ensure you saved the .tres file (Ctrl+S)
- Reload the scene or restart the game

### Getting UID errors
- The UID is auto-generated by Godot
- Don't manually edit UIDs - let Godot manage them

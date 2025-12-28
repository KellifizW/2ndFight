# CharacterData.gd
class_name CharacterData
extends Resource

@export var display_name: String = "Davis"          # 顯示名稱（如選角畫面用）
@export var short_id: String = "DAV"                # 角色簡稱（可用於其他地方，如存檔）
@export var scene: PackedScene                      # 角色場景（必須填）
@export var portrait: Texture2D = null              # 選角畫面頭像（未來用）

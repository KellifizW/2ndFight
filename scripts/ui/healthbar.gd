# Healthbar.gd （最終完美修正版：完全相容 TextureProgressBar，並解決型別錯誤）

extends TextureProgressBar

@export var max_health: float = 100.0

# 公開的血量變數，讓 Player 腳本直接設定
var current_health: float = max_health :
	set(value):
		var new_value = clamp(value, 0.0, max_health)
		if current_health == new_value:
			return
		current_health = new_value
		
		# 主血條立即反映新血量
		self.value = current_health
		
		# 當血量減少時啟動延遲條追趕
		if current_health < max_health:
			if has_node("Timer") and $Timer.is_stopped():
				$Timer.start()
		else:
			# 滿血時立即同步延遲條並停止計時器
			if damage_bar:
				damage_bar.value = current_health
			if has_node("Timer"):
				$Timer.stop()
		
		# 血量歸零提示（可自行移除）
		if current_health <= 0:
			Debug.log("Debug: Healthbar %s 已歸零！" % name)

# 延遲條：使用 Node 類型宣告，避免任何型別衝突（因為 ProgressBar 和 TextureProgressBar 都繼承自 Control）
@onready var damage_bar: Node = $DamageBar

func _ready() -> void:
	# 設定最大值
	max_value = max_health
	if damage_bar and damage_bar is Range:  # 安全檢查，確保它有 value 屬性
		damage_bar.max_value = max_health
	
	# 初始同步兩條血條
	self.value = current_health
	if damage_bar and damage_bar is Range:
		damage_bar.value = current_health
	
	# Timer 設定
	if has_node("Timer"):
		$Timer.wait_time = 0.4
		$Timer.one_shot = true
		if not $Timer.timeout.is_connected(_on_timer_timeout):
			$Timer.timeout.connect(_on_timer_timeout)
	else:
		push_warning("Healthbar %s 缺少 Timer 子節點，請在場景中新增一個 Timer 並命名為 Timer" % name)

func _on_timer_timeout() -> void:
	# 延遲條緩慢追上實際血量
	if damage_bar and damage_bar is Range:
		damage_bar.value = current_health

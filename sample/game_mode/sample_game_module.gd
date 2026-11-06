extends GDGameFramework.GameModuleBase

const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.PLAYER
const TICK_ENABLED := true
const DEBUG_RESTARTABLE := true

var elapsed: float = 0.0


func on_construct(_ctx: GDGameFramework.GameModeContext) -> void:
	provide_service(&"sample_game_flow", self)
	listen(&"sample_ping", _on_ping)


func on_update(delta: float) -> void:
	elapsed += delta


func _on_ping(_event: Variant) -> void:
	print("示例游戏模块收到一次 ping，实例 #", instance_serial)

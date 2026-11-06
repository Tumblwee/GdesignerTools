extends GDGameFramework.GameModuleBase

const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.MISC
const TICK_ENABLED := false
const DEBUG_RESTARTABLE := false

var state_changes: int = 0


func on_construct(_ctx: GDGameFramework.GameModeContext) -> void:
	provide_service(&"sample_session", self)
	listen(GDGameFramework.GameStateMachine.EVENT_GAME_STATE_CHANGED, _on_state_changed)


func _on_state_changed(_event: Variant) -> void:
	state_changes += 1

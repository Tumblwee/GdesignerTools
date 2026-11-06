extends GDGameFramework.GameModuleBase

const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.SCENE
const PARAMS_SCRIPT := preload("sample_flow_params.gd")
const TICK_ENABLED := true
const DEBUG_RESTARTABLE := false

var flow_params: Resource
var elapsed: float = 0.0


func configure(value: Resource) -> void:
	super.configure(value)
	flow_params = params


func on_update(delta: float) -> void:
	if flow_params == null or flow_params.auto_advance_seconds <= 0.0:
		return
	elapsed += delta
	if elapsed >= flow_params.auto_advance_seconds and GDGameMode.current != null:
		GDGameMode.current.switch_state(flow_params.next_state)

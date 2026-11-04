@tool
class_name GDSceneEditorL10n
extends RefCounted

## 关卡编辑器多语言（中/英）系统（对应 SceneEditorL10n）
## 默认中文（key 即中文原文），英文态查表命中返回英文、未命中回退中文原文。

enum Language {
	CHINESE = 0,
	ENGLISH = 1,
}

const PREF_KEY := "Gdesigner.SceneEditor.Language"

static var _on_language_changed_callbacks: Array[Callable] = []

const ENGLISH_TABLE := {
	"关卡编辑器": "Level Editor",
	"路径编辑器": "Path Editor",
	"相机配置": "Camera Pose Editor",
	"原型创建向导": "Archetype Creator Wizard",
	"模块创建向导": "Create Module Wizard",
	"迁移关卡场景 ID": "Migrate Layout IDs",
	"打开关卡场景…": "Open Level Scene...",
	"(无关卡场景)": "(No Level Scene)",
	"编辑中：": "Editing: ",
	"工具": "Tools",
	"场景工具": "Scene Tools",
	"可选·烘焙导航": "Optional · Bake NavMesh",
	"地面透明度": "Ground Opacity",
	"加载美术场景（叠加）": "Load Art Scene (Additive)",
	"卸载美术场景": "Unload Art Scene",
	"运行": "Play",
	"返回编辑器": "Return to Editor",
	"建筑原型目录 · 按类型分组": "Archetype Catalog · Grouped by Type",
	"编辑类型": "Edit Types",
	"+ 原型": "+ Archetype",
	"未分类": "Unclassified",
	"属性": "Properties",
	"已摆放实例": "Placed Instances",
	"关卡场景资产": "Level Scene Asset",
	"保存": "Save",
	"重新加载": "Reload",
	"位置": "Position",
	"旋转（欧拉角）": "Rotation (Euler)",
	"锁定缩放 = 1": "Lock Scale = 1",
	"缩放": "Scale",
	"固有属性": "Intrinsic Properties",
	"实例 ID": "Instance ID",
	"名称": "Name",
	"显示名": "Display Name",
	"自定义属性": "Custom Attributes",
	"+ 添加属性": "+ Add Attribute",
	"预览模型": "Preview Model",
	"显示预览模型": "Show Preview Model",
	"清除预览模型": "Clear Preview Model",
	"实例 ID 段": "Instance ID Range",
	"自定义 ID 段": "Custom ID Range",
	"标准化实例 ID": "Standardize Instance IDs",
	"重设 ID": "Reset ID",
	"删除实例项": "Delete Instance",
	"在 Project 中定位": "Ping in Project",
	"重命名": "Rename",
	"复制原型": "Duplicate Archetype",
	"新建 Variant 实例": "New Variant Instance",
	"重设碰撞盒（预览模型 AABB）": "Fit Collider (Preview AABB)",
	"删除原型": "Delete Archetype",
	"帮助": "Help",
	"清空": "Clear",
}

static var current_language: int:
	get:
		return GDHybridPrefs.get_int(PREF_KEY, Language.CHINESE)
	set(val):
		var prev := GDHybridPrefs.get_int(PREF_KEY, Language.CHINESE)
		if prev == val:
			return
		GDHybridPrefs.set_int(PREF_KEY, val)
		for cb in _on_language_changed_callbacks:
			if cb.is_valid():
				cb.call()

static func register_language_changed(cb: Callable) -> void:
	if cb.is_valid() and not _on_language_changed_callbacks.has(cb):
		_on_language_changed_callbacks.append(cb)

static func unregister_language_changed(cb: Callable) -> void:
	_on_language_changed_callbacks.erase(cb)

static func l(zh: String) -> String:
	if current_language == Language.ENGLISH and ENGLISH_TABLE.has(zh):
		return str(ENGLISH_TABLE[zh])
	return zh

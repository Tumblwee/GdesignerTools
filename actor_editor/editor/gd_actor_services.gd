@tool
class_name GDActorEditorServices
extends RefCounted

## 演员编辑器路径约定与重命名/复制/Override/建库服务
## 对应 ActorArchetypeAssetPaths / ActorArchetypeRenameService / ActorArchetypeOverrideService / ActorArchetypeDuplicatePopup / ActorLibraryCreatorWindow

class ActorArchetypeAssetPaths extends RefCounted:
	const LIBRARY_ASSET_PREFIX := "ActorLibrary_"
	const ARCHETYPE_FILE_PREFIX := "ActorArchetype_"
	const ENTITY_FILE_PREFIX := "Entity_"
	const ARCHETYPE_FOLDER_SUFFIX := "Actor"

	static func resolve_resource_root(library: GDActorLibraryRes) -> String:
		if library == null:
			return ""
		if not library.resource_path.is_empty():
			return library.resource_path.replace("\\", "/").get_base_dir()
		if library.has_meta("virtual_resource_root"):
			return str(library.get_meta("virtual_resource_root"))
		return "res://game_res/actors"

	static func resolve_module_name(library: GDActorLibraryRes) -> String:
		if library == null:
			return ""
		var stem := ""
		if not library.resource_path.is_empty():
			stem = library.resource_path.get_file().get_basename()
		elif not library.resource_name.is_empty():
			stem = library.resource_name
		elif not library.display_name.is_empty():
			stem = library.display_name
		else:
			stem = "Actors"
		if stem.begins_with(LIBRARY_ASSET_PREFIX):
			return stem.substr(LIBRARY_ASSET_PREFIX.length())
		return stem

	static func archetype_folder(resource_root: String, archetype_name: String) -> String:
		return "%s/Actors/%s%s" % [resource_root.trim_suffix("/"), archetype_name, ARCHETYPE_FOLDER_SUFFIX]

	static func archetype_so_path(folder: String, module_name: String, archetype_name: String) -> String:
		return "%s/%s%s_%s.tres" % [folder.trim_suffix("/"), ARCHETYPE_FILE_PREFIX, module_name, archetype_name]

	static func entity_prefab_path(folder: String, module_name: String, archetype_name: String) -> String:
		return "%s/%s%s_%s.tscn" % [folder.trim_suffix("/"), ENTITY_FILE_PREFIX, module_name, archetype_name]

	static func is_standard_archetype_folder(folder: String) -> bool:
		return not folder.is_empty() and folder.to_lower().contains("/actors/") and folder.ends_with(ARCHETYPE_FOLDER_SUFFIX)

	static func resolve_archetype_stem(archetype: GDActorLibraryRes.ActorArchetypeRes, module_name: String) -> String:
		if archetype == null:
			return ARCHETYPE_FOLDER_SUFFIX
		var so_path := archetype.resource_path
		if not so_path.is_empty():
			var folder := so_path.replace("\\", "/").get_base_dir()
			var folder_name := folder.get_file()
			if folder_name.ends_with(ARCHETYPE_FOLDER_SUFFIX) and folder_name.length() > ARCHETYPE_FOLDER_SUFFIX.length():
				return folder_name.substr(0, folder_name.length() - ARCHETYPE_FOLDER_SUFFIX.length())
			var file_stem := so_path.get_file().get_basename()
			var expected_prefix := "%s%s_" % [ARCHETYPE_FILE_PREFIX, module_name]
			if file_stem.begins_with(expected_prefix) and file_stem.length() > expected_prefix.length():
				return file_stem.substr(expected_prefix.length())
		var fallback := archetype.resource_name if not archetype.resource_name.is_empty() else archetype.display_name
		fallback = fallback.replace(ARCHETYPE_FILE_PREFIX, "")
		if not module_name.is_empty():
			fallback = fallback.replace(module_name + "_", "")
		return fallback if not fallback.is_empty() else ARCHETYPE_FOLDER_SUFFIX

	static func is_archetype_name_taken(library: GDActorLibraryRes, archetype_name: String) -> bool:
		if library == null:
			return false
		var mod := resolve_module_name(library)
		for a in library.archetypes:
			if a != null and resolve_archetype_stem(a, mod) == archetype_name:
				return true
		var root := resolve_resource_root(library)
		var folder := archetype_folder(root, archetype_name)
		var so_path := archetype_so_path(folder, mod, archetype_name)
		return ResourceLoader.exists(so_path)


class ActorArchetypeRenameService extends RefCounted:
	static func validate(
		archetype: GDActorLibraryRes.ActorArchetypeRes,
		library: GDActorLibraryRes,
		new_archetype_name: String,
		new_display_name: String
	) -> Dictionary:
		if archetype == null:
			return {"ok": false, "module_name": "", "error": "原型为空。"}
		if library == null:
			return {"ok": false, "module_name": "", "error": "请先打开一个演员库，再重命名原型。"}
		var clean_name := new_archetype_name.strip_edges()
		if clean_name.is_empty() or not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(
			clean_name, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME
		):
			return {"ok": false, "module_name": "", "error": "名称必须是合法 C# 标识符（字母/数字/下划线，不可数字开头）。"}
		if new_display_name.strip_edges().is_empty():
			return {"ok": false, "module_name": "", "error": "显示名不能为空。"}
		var mod := ActorArchetypeAssetPaths.resolve_module_name(library)
		var cur_stem := ActorArchetypeAssetPaths.resolve_archetype_stem(archetype, mod)
		if clean_name != cur_stem and ActorArchetypeAssetPaths.is_archetype_name_taken(library, clean_name):
			return {"ok": false, "module_name": mod, "error": "已存在同名原型：%s" % clean_name}
		return {"ok": true, "module_name": mod, "error": ""}

	static func try_rename(
		archetype: GDActorLibraryRes.ActorArchetypeRes,
		library: GDActorLibraryRes,
		new_archetype_name: String,
		new_display_name: String
	) -> Dictionary:
		var val := validate(archetype, library, new_archetype_name, new_display_name)
		if not bool(val.get("ok", false)):
			return val
		var mod := str(val.get("module_name", ""))
		var clean_name := new_archetype_name.strip_edges()
		var clean_disp := new_display_name.strip_edges()
		var cur_stem := ActorArchetypeAssetPaths.resolve_archetype_stem(archetype, mod)
		if clean_name != cur_stem:
			archetype.resource_name = "%s%s_%s" % [ActorArchetypeAssetPaths.ARCHETYPE_FILE_PREFIX, mod, clean_name]
			var old_addr := archetype.manufactured_prefab_address
			if old_addr.begins_with(ActorArchetypeAssetPaths.ENTITY_FILE_PREFIX):
				var new_addr := "%s%s_%s" % [ActorArchetypeAssetPaths.ENTITY_FILE_PREFIX, mod, clean_name]
				var preview_hit := archetype.preview_prefab_address == old_addr
				archetype.editor_set_prefab_addresses(new_addr, new_addr if preview_hit else archetype.preview_prefab_address)
		if clean_disp != archetype.display_name:
			archetype.editor_set_display_name(clean_disp)
		return {"ok": true, "error": ""}


class ActorArchetypeDuplicateService extends RefCounted:
	static func try_build_defaults(
		source: GDActorLibraryRes.ActorArchetypeRes,
		library: GDActorLibraryRes
	) -> Dictionary:
		if source == null or library == null:
			return {"ok": false, "archetype_name": "", "display_name": "", "error": "源原型或演员库为空。"}
		var mod := ActorArchetypeAssetPaths.resolve_module_name(library)
		var base_stem := ActorArchetypeAssetPaths.resolve_archetype_stem(source, mod)
		var base_disp := source.display_name if not source.display_name.is_empty() else base_stem
		for i in range(1, 1000):
			var cand := "%s_%d" % [base_stem, i]
			if not ActorArchetypeAssetPaths.is_archetype_name_taken(library, cand):
				return {"ok": true, "archetype_name": cand, "display_name": "%s_%d" % [base_disp, i], "error": ""}
		return {"ok": false, "archetype_name": "", "display_name": "", "error": "无法找到可用的 _N 后缀。"}

	static func try_duplicate(
		source: GDActorLibraryRes.ActorArchetypeRes,
		library: GDActorLibraryRes,
		archetype_name: String,
		display_name: String
	) -> Dictionary:
		if source == null or library == null:
			return {"ok": false, "created": null, "error": "源原型或演员库为空。"}
		return _create_in_library(source, library, archetype_name, display_name, false)

	## 校验名称后，按演员命名约定（ActorArchetype_<模块>_<名> / Entity_<模块>_<名>）复制原型并加入演员库。
	static func _create_in_library(
		source: GDActorLibraryRes.ActorArchetypeRes,
		library: GDActorLibraryRes,
		archetype_name: String,
		display_name: String,
		as_override: bool
	) -> Dictionary:
		var clean_name := archetype_name.strip_edges()
		if not GDKeywordCatalogSystem.KeywordIdentifierUtil.is_valid_identifier(
			clean_name, GDKeywordCatalogSystem.KeywordIdentifierUtil.IdentifierPolicy.TYPE_NAME
		):
			return {"ok": false, "created": null, "error": "名称必须是合法 C# 标识符。"}
		if display_name.strip_edges().is_empty():
			return {"ok": false, "created": null, "error": "显示名不能为空。"}
		if ActorArchetypeAssetPaths.is_archetype_name_taken(library, clean_name):
			return {"ok": false, "created": null, "error": "已存在同名原型：%s" % clean_name}

		var mod := ActorArchetypeAssetPaths.resolve_module_name(library)
		library.editor_reconcile_next_ids_after_load()
		var created := GDArchetypeOps.create_duplicate(
			source,
			library.editor_allocate_next_archetype_stable_id(),
			"%s%s_%s" % [ActorArchetypeAssetPaths.ARCHETYPE_FILE_PREFIX, mod, clean_name],
			display_name,
			as_override,
			"%s%s_%s" % [ActorArchetypeAssetPaths.ENTITY_FILE_PREFIX, mod, clean_name]
		) as GDActorLibraryRes.ActorArchetypeRes
		library.editor_add_archetype(created)
		return {"ok": true, "created": created, "error": ""}


## 演员侧的复写命名约定；成环检测 / 计数 / 改挂基底见 GDArchetypeOps。
class ActorArchetypeOverrideService extends RefCounted:
	const OVERRIDE_NAME_SUFFIX := "_Override"
	const OVERRIDE_DISPLAY_SUFFIX := "_复写"

	static func try_build_defaults(
		base_arch: GDActorLibraryRes.ActorArchetypeRes,
		library: GDActorLibraryRes
	) -> Dictionary:
		if base_arch == null or library == null:
			return {"ok": false, "archetype_name": "", "display_name": "", "error": "base 原型或演员库为空。"}
		var mod := ActorArchetypeAssetPaths.resolve_module_name(library)
		var base_stem := ActorArchetypeAssetPaths.resolve_archetype_stem(base_arch, mod)
		var base_disp := base_arch.display_name if not base_arch.display_name.is_empty() else base_stem
		for i in range(1, 1000):
			var ord := "" if i == 1 else str(i)
			var cand := base_stem + OVERRIDE_NAME_SUFFIX + ord
			if not ActorArchetypeAssetPaths.is_archetype_name_taken(library, cand):
				return {"ok": true, "archetype_name": cand, "display_name": base_disp + OVERRIDE_DISPLAY_SUFFIX + ord, "error": ""}
		return {"ok": false, "archetype_name": "", "display_name": "", "error": "无法找到可用的 _Override 后缀。"}

	static func try_create(
		base_arch: GDActorLibraryRes.ActorArchetypeRes,
		library: GDActorLibraryRes,
		archetype_name: String,
		display_name: String
	) -> Dictionary:
		if base_arch == null:
			return {"ok": false, "created": null, "error": "未指定复写目标（base 原型）。"}
		if library == null:
			return {"ok": false, "created": null, "error": "请先打开一个演员库，再新建 Override。"}
		if base_arch.manufactured_prefab_address.is_empty():
			return {"ok": false, "created": null, "error": "base 原型未配置「实例」Prefab，无法建 Prefab Variant。"}
		return ActorArchetypeDuplicateService._create_in_library(base_arch, library, archetype_name, display_name, true)

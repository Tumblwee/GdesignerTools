# GdesignerTools

Godot 4.7 的策划工具套件：关卡、演员、技能、新手引导、游戏进程，共用一套界面和撤销系统。

工具开在一个非模态窗口里，可以放在 3D 视口旁边或第二块屏幕上；原型直接从列表拖进视口摆放。

## 使用

打开方式：顶部工具栏 **GdesignerTools**，或 项目 → 工具 → GdesignerTools。

每一页都是同一个布局：

```
文档名 ●  保存 撤销 重做 | 本页操作 …………………… 右侧操作 ⋯
资产列表        |  工作区                    |  属性
```

| 页面 | 工作区 | 主要操作 |
|------|--------|----------|
| 关卡 | 俯视平面图 + 实例 / 路径 / 相机列表 | 把原型拖进 3D/2D 视口或平面图；拖圆点改位置；双击原型放到视口中心 |
| 演员 | 实时 3D 预览 | 新建、复制、创建变体、改类型和外观 |
| 技能 | 时间轴 | 拖片段移动，拖边缘改时长，双击轨道添加片段，Space 播放 |
| 引导 | 节点图 | 从端口拖出连线，拖到空白处新建节点，F5 试跑，F9 断点 |
| 游戏进程 | 状态图 + 运行监控 + 时间线 | 配置全局与状态模块，按实际切换绘图，调试切换、重启与应用配置 |

通用约定：

- 每一处改动都能撤销（Ctrl+Z / Ctrl+Y），所以删除不弹确认；只有会连带影响别的数据或写磁盘的操作才确认。
- 列表和画布都支持右键菜单，以及 Delete、F2 重命名、Ctrl+D 复制。
- 有未保存改动时，页签和文档名后面显示 ●；关闭编辑器时会提示保存。编辑器的“保存全部”和运行游戏也会一起保存。
- Ctrl+\` 打开控制台。Tab 补全命令，↑↓ 翻历史；当前页面的资产路径会自动带上。

默认保存位置：`res://game_res/level`、`res://game_res/actors`、`res://game_res/skill`、`res://game_res/guide`、`res://game_res/game_mode`。

保存时检查文件归属。遇到同名文件，可以另存为、生成带后缀的新名字或取消。另存为覆盖已有文件会要求确认，已经被其它资源加载的文件需要保存到其它路径。引导图首次保存后保留文件路径，修改图 ID 会重新校验唯一性。

关卡页的“文件 → 打开关卡”显示项目中的关卡资产列表，可按名称或路径搜索。选中资产后会自动打开其 `scene_path` 指定的编辑场景；未配置时会在 `res://game_res/level/editing` 创建独立编辑场景。`art_scene_path` 和 `logic_scene_path` 继续用于运行时装配，不能与编辑场景共用。

演员页的“文件 → 打开演员库”同样显示已有演员库列表，可按名称或路径搜索，选中后点击打开或双击。列表也包含当前已打开但尚未保存的库，切换后保留原来的未保存改动和撤销记录。

选中演员后，中间显示实例 Prefab 或预览 Prefab 的真实形象，自动区分 3D 和 2D。3D 支持左键环绕、右键／中键平移；2D 支持拖动平移；两者都支持滚轮缩放、双击重新取景。预览保留 `@tool` 脚本生成外观所需的初始化，普通游戏脚本和持续处理不运行。缺少可用 Prefab 时会显示说明。

先在关卡页打开目标关卡的编辑场景，再切换到演员页，把演员拖入对应的 3D／2D 视口。落点创建插件内置的**演员生成点**，并保存演员库及演员 ID；取消拖拽不创建资源。生成点原型位于 `actor_editor/builtin/ActorSpawnPoint.tres`，ID `1` 属于插件保留范围（用户原型仍从 `1000` 起分配），不会添加到用户原型库。每个生成点可独立移动、复制、删除、撤销和保存。

编辑场景中的生成点显示演员预览和青色圆环，保存时只写生成点与演员引用；运行时生成真实演员，不保存预览几何，也不会重复生成。关卡实例属性显示绑定的演员和演员库，并提供“自动生成”开关。关闭后可调用生成点节点的 `spawn_actor()` 手动生成，调用 `clear_actor()` 清除；默认生成一个演员，重复调用不会叠加。运行时通过 `GDSceneEditorRuntime.load_session()` 装配关卡时，2D／3D 生成点和已经摆好的场景节点均可直接使用。

关卡左侧按**原型库**管理原型。点击库名称右侧的库图标，选择“选择原型库”可引用项目中已有的库，也可以新建或打开库文件。新建关卡默认沿用当前库；多个关卡引用同一份 `GDLevelLibraryRes`，在其中一个关卡修改原型，其他关卡会使用相同的数据。实例、路径和相机仍由各关卡独立保存。已经有实例的关卡不能切换到缺少这些原型的库；删除原型及撤销新建原型时会检查所有关卡的使用情况。

“全局类型”管理所有关卡原型库共用的类型，保存位置是 `res://game_res/level/libraries/PlacementTypes.tres`。点击类型名称前的色块修改颜色，原型列表、实例列表和俯视图标记立即同步；同类型始终使用同一颜色，修改支持保存、撤销和重做。旧目录自动使用按类型 ID 分配的默认色，未分类或类型丢失时显示灰色。添加类型无需生成代码；如需枚举，点击“生成枚举”，首次会使用 `res://game_res/generated/keywords`。中文显示名会转换为合法的内部名称，停用后再次添加同名类型会沿用原 ID 和颜色。

旧关卡首次打开时，会把内嵌原型迁入独立库，并合并旧类型目录；同号异名的类型会重新分配类型 ID，原型 ID 和摆放实例保持不变。点击保存会依次保存全局类型、原型库、外部原型文件和关卡引用。选中原型时撤销作用于库，选中实例时撤销作用于关卡，编辑类型后撤销作用于全局目录。

只有当前处于该关卡的编辑场景中，才能选中、摆放或修改实例、路径和相机。切换到运行时场景或其他场景会清除选择并停止拖拽，点击“进入编辑场景”可返回。每个 `Placements` 容器绑定一份布局，回拉位姿、同步、撤销和删除只作用于该编辑场景内属于该布局的实例。保存全部会先同步视口位姿，再判断哪些文档需要写盘。

技能运行时先检查费用、冷却和标签，通过后扣费。配置了消耗的单位需要注册属性集，未知的消耗属性会拒绝施放。技能服务和效果应用器在同一个事件总线上共享 `tag_store`，支持标签引用计数和层级匹配。游戏侧可以设置技能服务的 `tag_query(owner_id, tag)` 回调补充已有状态。持续效果到期时移除自己授予的标签，瞬时片段直接应用效果并保留施放者信息。

时间轴播放用于核对片段时序。游戏侧通过 `SkillNodeFiredEvent` 接入命中、投射物、动画和表现。引导宿主负责实际 UI 定位、遮罩和点击转发，进度编码可接入项目自己的存档。

## 游戏进程编辑器（1.2）

从工具窗口的“游戏进程”页签或 项目 → 工具 → GdesignerTools: 游戏进程编辑器 打开。配置包含固定的全局模块节点和以 `StringName` key 标识的状态。状态切换由业务代码驱动，配置图不编辑连线；运行监控只显示实际发生过的切换及次数。

点击“打开”会列出项目中已有的游戏进程配置，可按名称或路径搜索，选中后点击打开或双击。列表也包含当前会话中尚未保存的配置，切换后保留各配置的未保存改动和撤销记录。

在全局模块或状态节点上右键，选择“新建模块…”填写模块名称。代码默认保存到 `res://scripts/game_mdl/`，保存位置旁的文件夹图标可选择项目内的自定义目录。创建后自动加入右键所在的节点，也可通过“添加已有模块…”引用已有脚本。左侧列表提供相同菜单；运行监控中不可修改配置。同名脚本不会被覆盖，撤销添加只移除配置中的模块引用，保留已创建的代码文件。

模块继承 `GDGameFramework.GameModuleBase`，用常量声明元数据。普通业务模块不需要 `@tool`；编辑器检查编译和继承关系，不实例化业务模块。模块及参数脚本的构造函数必须允许无参调用：

```gdscript
extends GDGameFramework.GameModuleBase

const MODULE_CATEGORY := GDCoreTypes.ModuleCategory.SCENE
const PARAMS_SCRIPT := preload("my_params.gd") # 可选，继承 Resource 的 @tool 纯数据脚本
const TICK_ENABLED := true
const DEBUG_RESTARTABLE := false

func on_construct(_ctx: GDGameFramework.GameModeContext) -> void:
    listen("MyEvent", _on_event)
    provide_service("MyService", self)

func _on_event(_event: Variant) -> void:
    pass
```

参数类型须匹配 `PARAMS_SCRIPT` 或其子类。没有 `@tool` 的参数只能在页面中只读查看。首版支持标量、`StringName`、`Color` 及 Resource 引用；数组、字典等只读显示。更换参数类型会重建参数，整个更换操作可以撤销。`configure()` 接收独立参数副本，若重写此方法，应调用 `super.configure(value)` 后读取 `params`。

引用独立文件的外部参数在此页只读；“复制为内嵌参数”会创建配置自己的可编辑副本，支持撤销与保存，并保留嵌套外部资源引用。保存配置不会改写原来的外部参数文件。

模块条目的脚本字段名为 `module_script`，因为 `Resource.script` 已被 Godot 用于资源自身的类型脚本。保存时另存 `script_path_hint`；模块脚本丢失后，编辑器保留条目和路径提示，允许重新指定脚本及保存修复。

在启动场景加入 `GDGameModeBootstrap` 节点，把 `config_path` 指向保存的 `.tres`。它会预检依赖并验证配置，再把常驻 `GDGameMode` 挂到场景树根部。再次进入启动场景不会重复创建。业务侧使用 `GDGameMode.current.switch_state(&"game")`，模块在每次进入状态时由工厂重新创建。全局模块只初始化一次，先于状态模块 Tick；暂停时默认停止 Tick，可在配置中开启 `tick_when_paused`。LateUpdate 在默认优先级节点之后执行。

通过 `systems.add()` 注册的子系统会在所属模块回调之后自动收到 Update、LateUpdate 和 FixedUpdate，并沿用模块的 Tick 开关和故障停止规则。业务模块不应再手动调用 `systems.tick_*()`，以免同一阶段重复执行。

依赖预检覆盖 `ResourceLoader.get_dependencies()` 能枚举的资源引用。Godot 不通过该 API 枚举 GDScript 源码内部的 `preload()`；源码内的缺失依赖由 Godot 脚本加载错误和后续校验拒绝，不能保证在资源预检阶段全部列出。

`listen()` 和 `provide_service()` 在 Dispose 时自动清理；直接调用事件总线订阅仍由业务自己清理。调用 `report_fault(phase, message)` 会停止该实例的 Tick，保留故障阶段、消息和帧号。Construct 故障跳过 BeginPlay，但退出时仍 Dispose。GDScript 自身的运行错误仍交给 Godot 调试器。

运行游戏后，页面自动握手并补齐最多 500 条启动与运行事件。可选不同会话；断线保留最后快照，断点暂停及协议不兼容时禁用修改命令。调试切换会跳过业务前置条件，只用于调试。重启状态保留全局模块，重启模块要求声明 `DEBUG_RESTARTABLE = true`。10 秒未收到命令回执会显示“无回执”，不会自动重试。

保存配置不会改变正在运行的游戏。使用“应用配置并重启 GameMode”会先保存并校验，再由运行端核对摘要后重建；原状态仍存在则恢复，否则进入默认状态。应用只允许本工程的编辑器运行环境（`editor_runtime`），导出包可以监控、切换和重启，运行端会拒绝应用配置命令。图节点位置不计入运行摘要，因此拖动布局不会显示为“已保存，未应用”。有校验错误的配置可保存，不能启动或应用。

点击页面的示例入口，或调用 `GDSampleFactory.ensure_game_mode_assets()`，生成 `res://game_res/sample/game_mode/GameMode_Sample.tres` 及 `GameMode_Sample.tscn`。示例包含 login / game、全局会话服务、可重启的游戏模块和可编辑登录参数；打开该场景后用“运行当前场景”（F6）体验。生成器不覆盖已有示例，也不修改工程主场景。

### 手动 GameStateMachine API 的迁移

| 行为 | 1.2 起的约定 |
|------|------------|
| 未登记状态 | 切换返回 `false`；空状态先显式 `register_state_binding(id, [])` |
| 切换到 `-1` | 返回 `false`；关闭改用 `shutdown()` |
| 生命周期或 Tick 内切换 | 入队，`true` 表示已受理；通过状态变更事件观察完成，不立即读取 `current_state_id` 判断完成 |
| 全局模块顺序 | 按 Scene → Player → Misc 初始化，同分类保持注册顺序 |
| 状态切换后的全局故障 | 保留故障标记，重建实例后才清除 |
| GameStateChangedEvent | 保留 old/new ID，新增 old/new key 和 `reason`；重启会发同状态事件，业务按 `reason` 过滤 |

工厂注册使用 `register_state_factories()` / `register_global_factories()`。手动注册实例仍在重新进入时复用，不支持调试重启；快照以 `manual:<state>:<index>` 标识。释放始终按实际初始化顺序逆序进行；关闭先释放状态模块，再释放全局模块。一次队列最多连续完成 8 次切换，剩余请求会丢弃并记录 `reentry_overflow`。

## 结构

```
plugin.gd                       插件入口：窗口、工具菜单、视口拖放、未保存提示
gdesigner_tools_window.gd       非模态窗口
gdesigner_tools_main_dock.gd    外壳：页签、状态栏、控制台抽屉
gdesigner_tools_cli.gd          统一命令行入口（各模块的命令表汇总）

core/                           运行时基础：原子、属性集、事件总线、音频、GDDataCodec
core/editor/                    编辑器基础，所有页面共用
    gd_editor_ui.gd             设计令牌（tone 跟随编辑器主题）和控件工厂
    gd_page.gd                  页面骨架：工具栏 + 三栏 + 文档
    gd_document.gd              撤销栈、脏标记、保存
    gd_form.gd                  声明式属性表单
    gd_library_list.gd          可搜索、可分组的资产列表
    gd_dialogs.gd               一次性对话框
level_editor/  actor_editor/  skill_editor/  guide_editor/  game_mode_editor/
    runtime/                    数据与运行时，游戏里也能用
    editor/                     页面、视图、命令行
tests/                          headless 测试
```

### 数据流

页面只做两件事：改模型，然后 `doc.commit("动作名")`。`GDDocument` 记录快照并发出 `changed`，页面在 `_refresh()` 里刷新视图。撤销把快照里的字段写回原对象，所以对象身份不变，选中项和外部引用都不会失效。

### 存盘

Godot 不能把脚本是内部类的 Resource 写进 `.tres`。技能的片段、引导图的节点、关卡的路径和相机都是内部类，因此由 `GDDataCodec` 统一编码成普通数据，存在一个 `@export_storage` 属性里。保存、加载、`duplicate()` 都不需要额外步骤；新增一个片段或节点类型，不用改编解码代码。

## 测试

```bash
GODOT="D:/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"
"$GODOT" --headless --path . --editor --import
for t in test_gdesigner_tools test_level_page test_level_libraries test_type_colors test_level_workflow test_actor_spawn test_skill_page test_guide_page test_asset_safety test_level_safety test_skill_runtime_safety test_game_mode_framework test_game_mode_runtime test_game_mode_debugger test_game_mode_page; do
  "$GODOT" --headless --path . -s "res://addons/gdesigner_tools/tests/$t.gd"
done
```

首次导入会建立全局类缓存。测试请在临时工程中执行，综合测试会在 `res://game_res/sample/_cli_tmp` 下生成并清理资源。安全回归测试使用各自的 `user://` 目录。

模块新建流程的回归测试为 `tests/test_game_module_creation.gd`，需在名称包含 `Validation` 的独立临时工程中运行。它验证右键目标、默认与自定义代码目录、取消及重名保护，并清理自己生成的脚本。

普通 `--headless -s` 测试不会启用编辑器对非 `@tool` 脚本的执行限制。新建模块的编辑器回归位于 `tests/editor_module_creation_smoke/`：在独立工程中设 `config/name="GdesignerTools Module Creation Validation"`，隔离 `APPDATA`，导入后仅启用该目录的 `plugin.cfg`，以 `godot --headless --editor --path <临时工程>` 运行。成功输出 `MODULE_EDITOR_SMOKE: SUCCESS`，覆盖非工具脚本的新建与添加、构造函数不执行、撤销重做和配置保存重载；不要在业务工程中启用。

真实编辑器与游戏调试通道的集成验收位于 `tests/editor_game_mode_smoke/`，默认不启用。先把插件复制到一个独立临时工程，工程名必须为 `GdesignerTools Validation`，并将 `APPDATA` 指向临时目录以隔离编辑器设置。在该临时工程的 `project.godot` 中启用：

```ini
[editor_plugins]
enabled=PackedStringArray("res://addons/gdesigner_tools/plugin.cfg", "res://addons/gdesigner_tools/tests/editor_game_mode_smoke/plugin.cfg")
```

然后运行 `godot --editor --path <临时工程>`（可加 `--headless`）。脚本会生成样例，检查缺失模块的可修复加载、真实握手及启动事件、四类调试命令、暂停/继续、断线重连和双进程隔离，完成后打印 `GM_EDITOR_SMOKE: SUCCESS failures=0` 并退出。运行环境需允许本地调试 TCP 端口；第二个进程默认使用编辑器 `network/debug/remote_port`，可用 `GM_SMOKE_DEBUG_URI` 指定实际地址。正常渲染模式还会在临时工程保存 `game-mode-monitor.png`。

验收会暂时改写临时工程中的示例配置，结束时恢复原示例及插件启用设置，停止自行启动的游戏进程。缺失脚本用例会产生预期的 Godot 加载错误日志；断言失败会以 `FAIL` 标明并返回非零退出码。不要在业务工程中启用这个验收插件。

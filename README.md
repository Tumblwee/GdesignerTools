# GdesignerTools — Godot 4 通用游戏策划工具套件 (v1.0)

`GdesignerTools` 是从 Unity 原项目五大核心包（`com.timiminigame.core`、`com.timiminigame.scene-editor`、`com.timi.ioplatform.actor-editor`、`com.timi.ioplatform.skill`、`com.timi.ioplatform.guide`）完整还原至 **Godot 4.x** 的通用策划工具链插件。

## 目录结构与双路径说明

- **`res://addons/gdesigner_tools/`（`D:\GodotTemplate\addons\gdesigner_tools`）**：Godot 4 标准 EditorPlugin 插件启用目录（在 `project.godot` 中自动挂载启用）。插件打开的是非模态独立窗口，不占用 2D/3D 主屏，关卡页可以把原型拖进当前视口。
- **`D:\GodotTemplate\GdesignerTools\`**：与 `addons/gdesigner_tools` 完全同步的独立源码目录镜像（内含 `.gdignore` 以避免 Godot 重复扫描同名 `class_name`）。

```text
addons/gdesigner_tools/ (及 GdesignerTools/)
├── sample/
│   └── gd_sample_factory.gd                    # 通用示例实例（演员库 / 关卡 / 实体预制）
├── plugin.cfg                                  # Godot 插件配置清单
├── plugin.gd / gdesigner_tools_plugin.gd       # EditorPlugin 主入口（独立窗口 + 视口拖拽落点）
├── gdesigner_tools_window.gd                   # 非模态独立窗口
├── gdesigner_tools_main_dock.gd                # 主工作台（集成四大编辑器 Tab + 原子创建器 + CLI 控制台）
├── core/                                       # 1. Core 基础层 (com.timiminigame.core)
│   ├── gd_core_types.gd                        # KeywordValueType / AtomType / ModuleCategory 等枚举与解析
│   ├── gd_logger.gd                            # GameLogger (Verbose/Debug/Info/Warning/ErrorP/ErrorD/Assert)
│   ├── gd_event_bus.gd                         # EventBus / ServiceLocator / CoreServices / UndoRedo
│   ├── gd_attribute_set.gd                     # GAS AttributeSet: Current = Override ?? ((Base+Add)*(1+Mul))
│   ├── gd_custom_attribute_def.gd              # CustomAttributeDef 自定义属性定义
│   ├── gd_archetype_res.gd                     # ArchetypeRes 原型基类（StableId 1000+、复写链、自定义 ID 段）
│   ├── gd_atom_base.gd                         # EntityNode / AtomBase / InteractableAtom / VisualAtom / UIAnchor3DAtom / AtomVarTagRegistry / FurnitureSlotGroupBehavior
│   ├── gd_game_framework.gd                    # GameMode / GameStateMachine / ModuleTickDriver / GameModuleBase / BaseSystem / SystemContainer
│   ├── gd_audio_engine.gd                      # 纯逻辑 AudioEngine / AudioBusMixer / AudioContainerSelector / VoiceSlot 抢占池
│   ├── gd_hybrid_prefs.gd                      # HybridPrefs 跨会话偏好存储
│   ├── gd_cli_root.gd                          # CliRoot / AtomCreator (atom.create / atom.list-templates)
│   └── editor/
│       ├── gd_atom_block_drawer.gd             # AtomPickerPopup / AtomCreatorWindow / 原子区块与自定义属性检视器
│       ├── gd_preview_panel.gd                 # ArchetypePreviewPanel（环绕/平移/缩放/包围框/棋盘格）
│       └── gd_cli_console_window.gd            # 统一可视化 CLI 控制台面板
├── level_editor/                               # 2. 关卡编辑器 (com.timiminigame.scene-editor)
│   ├── runtime/
│   │   ├── gd_keyword_catalog.gd               # KeywordCatalogRes（单调 StableId、软删复活、枚举脚本生成与哈希校验）
│   │   ├── gd_placement_instance.gd            # PlacementInstance (10000+) / Override / Extra / ID 段分配与两阶段标准化
│   │   ├── gd_path_instance.gd                 # PathInstance (20000+) / SplineData (Curve3D) / RuntimePath / PathRuntimeRegistry
│   │   ├── gd_camera_pose.gd                   # CameraPose（透视 XZ / 正交 XY 边界、缩放区间、初始 Zoom）
│   │   ├── gd_level_scene_res.gd               # LevelSceneRes 关卡场景主资产
│   │   └── gd_scene_editor_runtime.gd          # SceneEditorRuntime.load_session 一行装配与 5 大标准事件
│   └── editor/
│       ├── gd_level_editor_window.gd           # 关卡编辑器三栏主窗口 + 交互画布 + 自定义 ID 段检视器
│       ├── gd_path_editor_window.gd            # PathEditorWindow 路径编辑工作台（含采样 t 滑条预览）
│       ├── gd_camera_pose_window.gd            # CameraPoseEditorWindow 相机机位配置窗口
│       ├── gd_level_popups.gd                  # 类型编辑弹窗 / 原型创建器 / 模块向导 / 重设实例 ID 弹窗
│       ├── gd_level_csv_exporter.gd            # UTF-8 BOM CSV 导出器
│       ├── gd_layout_migration.gd              # LayoutIdMigrationTool + 原型复写/复制/防环通用服务
│       ├── gd_scene_editor_cli.gd              # 13 条标准 CLI (keywords.* / layout.* / scaffold.* / sceneeditor.*)
│       └── gd_level_editor_l10n.gd             # 中英双语切换与偏好持久化
├── actor_editor/                               # 3. 演员编辑器 (com.timi.ioplatform.actor-editor)
│   ├── runtime/
│   │   └── gd_actor_library_res.gd             # ActorLibraryRes / ActorArchetypeRes (StableId 1000+)
│   └── editor/
│       ├── gd_actor_services.gd                # 路径规范 / 重命名 / 复制(Name_N) / Override 复写防环与重绑服务
│       └── gd_actor_editor_window.gd           # 演员编辑器双栏主窗口 + 库创建向导 + 原型创建器 + 原子宿主装配
├── skill_editor/                               # 4. 技能编辑器 (com.timi.ioplatform.skill)
│   ├── runtime/
│   │   ├── gd_skill_types.gd                   # SkillIdentity / GameplayTagRes / GameplayEffectRes / SkillClock
│   │   ├── gd_skill_clips.gd                   # 15 种内置 SkillClip + 4 种投射物轨迹 (Linear/Parabola/Homing/Bezier)
│   │   ├── gd_skill_res.gd                     # 单资产 GDSkillRes (Header + Group + Track + Clip)
│   │   ├── gd_skill_data.gd                    # 技能全量数据结构镜像
│   │   └── gd_skill_runtime.gd                 # SkillRunner (同刻逻辑先于表现排序) / SkillRuntimeService / GameplayEffectApplier
│   └── editor/
│       ├── gd_skill_math_and_validator.gd      # SkillTimelineEditorMath / SkillAssetValidator / SkillLinter / SkillDoctor
│       ├── gd_skill_forge_and_cli.gd           # SkillForge 确定性装配器 + 8 条 SkillCli 命令
│       └── gd_skill_editor_window.gd           # 技能编辑器四区主窗口（技能库 + 时间轴 + 4 态 Inspector + 校验面板）
├── guide_editor/                               # 5. 新手引导编辑器 (com.timi.ioplatform.guide)
│   ├── runtime/
│   │   ├── gd_guide_data.gd                    # 端口/信号/条件表达式/TargetRef/EventRef/Blackboard/Trace/Phase
│   │   ├── gd_guide_atoms.gd                   # 15 种内置原子 + MissingAtom 兜底
│   │   ├── gd_guide_host.gd                    # GuideConditionRegistry / GuideConditionEvaluator / GuideMemoryProgressStore / GuideHost
│   │   ├── gd_guide_graph_and_validator.gd     # GuideGraphRes / GuideLibraryRes / GuideGraphValidator / GuideSchemaMigrator (v1->v2)
│   │   └── gd_guide_runner.gd                  # GuideRunner (帧水位线/断点/单步/超时/Stall/子图栈) / GuideTriggerSystem
│   └── editor/
│       ├── gd_guide_editing_and_cli.gd         # GuideGraphLayout / GuideGraphEditing (强弱互转/点击录制) / GuideSampleGraphs / GuideCli
│       └── gd_guide_editor_window.gd           # 新手引导编辑器主窗口（画布/小地图/调试器/录制条/搜索弹窗/模拟器/迁移横幅）
└── tests/
    └── test_gdesigner_tools.gd                 # Headless 自动化全量验证脚本
```

## 运行自动化测试

```powershell
& "D:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:\GodotTemplate" -s "res://addons/gdesigner_tools/tests/test_gdesigner_tools.gd"
```

# GdesignerTools

Godot 4.7 的策划工具套件：关卡、演员、技能、新手引导，共用一套界面和撤销系统。

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

通用约定：

- 每一处改动都能撤销（Ctrl+Z / Ctrl+Y），所以删除不弹确认；只有会连带影响别的数据或写磁盘的操作才确认。
- 列表和画布都支持右键菜单，以及 Delete、F2 重命名、Ctrl+D 复制。
- 有未保存改动时，页签和文档名后面显示 ●；关闭编辑器时会提示保存。编辑器的“保存全部”和运行游戏也会一起保存。
- Ctrl+\` 打开控制台。Tab 补全命令，↑↓ 翻历史；当前页面的资产路径会自动带上。

默认保存位置：`res://game_res/level`、`res://game_res/actors`、`res://game_res/skill`、`res://game_res/guide`。

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
level_editor/  actor_editor/  skill_editor/  guide_editor/
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
for t in test_gdesigner_tools test_level_page test_skill_page test_guide_page; do
  "$GODOT" --headless --path . -s "res://addons/gdesigner_tools/tests/$t.gd"
done
```

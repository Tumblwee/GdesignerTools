@tool
class_name GDGuideLibraryRes
extends Resource

## 引导库（对应 GuideLibrarySO）：一组引导图资产的引用。

@export var graphs: Array[GDGuideGraphRes] = []

func find_graph(p_graph_id: int) -> GDGuideGraphRes:
	for g in graphs:
		if g != null and g.graph_id == p_graph_id:
			return g
	return null

func contains(graph: GDGuideGraphRes) -> bool:
	return graph != null and graphs.has(graph)

func add_graph(graph: GDGuideGraphRes) -> bool:
	if graph == null or graphs.has(graph):
		return false
	graphs.append(graph)
	emit_changed()
	return true

func remove_graph(graph: GDGuideGraphRes) -> bool:
	if not contains(graph):
		return false
	graphs.erase(graph)
	emit_changed()
	return true

## M0 主场景健全性用例：防"渲染黑屏"类回归（headless 可跑，覆盖相机朝向/灯光/环境/网格/摆位）。
## 背景：曾因手写 .tscn 旋转变换按列主序序列化（Godot 文本格式为行主序）导致相机转置、
## 视口全黑而 HUD 正常——headless 冒烟测不出纯视觉故障，本套件用几何断言兜底。
extends GdUnitTestSuite

## 主场景路径
const SCENE_PATH: String = "res://scenes/m0/m0_forge_test.tscn"

## 刀坯网格长度合理区间（米）
const BLADE_LENGTH_MIN: float = 0.1
const BLADE_LENGTH_MAX: float = 1.0

var _root: Node3D


func before_test() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	assert_object(scene).is_not_null()
	_root = scene.instantiate()
	add_child(_root)


func after_test() -> void:
	if _root != null and is_instance_valid(_root):
		if _root.is_inside_tree():
			remove_child(_root)

		_root.free()
		_root = null


func test_camera_topdown_and_all_elements_in_frame() -> void:
	# 俯视角语义：俯角 ≥70°（前向 y ≤ -sin70°）；砧/刀坯/炉/锤四要素同框（均在视锥内）
	var camera := _find_first(_root, "Camera3D") as Camera3D

	assert_object(camera).is_not_null()
	assert_bool(camera.current).is_true()
	assert_vector(camera.global_position).is_not_equal(Vector3.ZERO)

	var forward := -camera.global_transform.basis.z
	assert_float(forward.y).is_less(-sin(deg_to_rad(70.0)))

	var blade_mesh := _root.find_child("BladeMesh", true, false) as MeshInstance3D
	var blade_aabb: AABB = blade_mesh.global_transform * blade_mesh.get_aabb()

	var hammer := _root.find_child("HammerRig", true, false) as Node3D
	var hammer_head := hammer.get_node_or_null("HammerPivot/HeadMain") as MeshInstance3D

	assert_bool(camera.is_position_in_frustum(blade_aabb.get_center())).is_true()
	assert_bool(camera.is_position_in_frustum(_root.find_child("AnvilRig", true, false).global_position)).is_true()
	assert_bool(camera.is_position_in_frustum(_root.find_child("ForgeRig", true, false).global_position)).is_true()
	assert_object(hammer_head).is_not_null()
	assert_bool(camera.is_position_in_frustum(hammer_head.global_position)).is_true()


func test_lights_present_with_positive_energy() -> void:
	# 至少 1 盏常亮灯且 energy > 0；平行光方向必须朝下（曾因转置朝上导致无光照）
	# 注：BladeGlow 为温度联动灯（冷态 energy=0 属设计行为），豁免常亮断言
	var light_count: int = 0
	var lit_count: int = 0

	for node: Node in _root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		light_count += 1

		if light.name != "BladeGlow":
			assert_float(light.light_energy).is_greater(0.0)
			lit_count += 1

	assert_int(light_count).is_greater_equal(1)
	assert_int(lit_count).is_greater_equal(1)

	var sun := _find_first(_root, "DirectionalLight3D") as DirectionalLight3D
	assert_object(sun).is_not_null()

	var sun_forward := -sun.global_transform.basis.z
	assert_float(sun_forward.y).is_less(0.0)


func test_environment_configured_not_black() -> void:
	# WorldEnvironment 的 environment 非 null，且环境光 / 背景非全黑
	var world_env := _root.find_child("WorldEnvironment", true, false) as WorldEnvironment

	assert_object(world_env).is_not_null()
	assert_object(world_env.environment).is_not_null()

	var env := world_env.environment
	var ambient_ok: bool = (
		env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
		and env.ambient_light_energy > 0.0
		and (env.ambient_light_color.r + env.ambient_light_color.g + env.ambient_light_color.b) > 0.03
	)
	var background_ok: bool = (
		env.background_mode == Environment.BG_COLOR
		and not env.background_color.is_equal_approx(Color.BLACK)
	)

	assert_bool(ambient_ok or background_ok).is_true()


func test_blade_mesh_built_in_meter_scale() -> void:
	# 刀坯网格非空、有面、AABB 尺寸在合理米级范围
	var mesh_instance := _root.find_child("BladeMesh", true, false) as MeshInstance3D

	assert_object(mesh_instance).is_not_null()
	assert_object(mesh_instance.mesh).is_not_null()
	assert_int(mesh_instance.mesh.get_surface_count()).is_greater(0)

	var aabb: AABB = mesh_instance.mesh.get_aabb()
	assert_float(aabb.size.x).is_between(BLADE_LENGTH_MIN, BLADE_LENGTH_MAX)
	assert_float(aabb.size.y).is_less(BLADE_LENGTH_MAX)
	assert_float(aabb.size.z).is_less(BLADE_LENGTH_MAX)


func test_hammer_head_and_handle_visible_in_frame() -> void:
	# 锤头与锤柄必须在画内且可见（第三轮复审事故：相机重构后锤整体丢失）
	var camera := _find_first(_root, "Camera3D") as Camera3D
	assert_object(camera).is_not_null()

	var hammer := _root.find_child("HammerRig", true, false) as Node3D
	assert_object(hammer).is_not_null()
	assert_bool(hammer.visible).is_true()

	for part_path: String in ["HammerPivot/HeadMain", "HammerPivot/Handle"]:
		var part := hammer.get_node_or_null(NodePath(part_path)) as MeshInstance3D
		assert_object(part).is_not_null()
		assert_bool(part.visible).is_true()
		assert_bool(camera.is_position_in_frustum(part.global_position)).is_true()


func test_rigs_visible_and_in_front_of_camera() -> void:
	# 锻炉 / 铁砧可见且位于相机前方
	var camera := _find_first(_root, "Camera3D") as Camera3D
	assert_object(camera).is_not_null()

	var forward := -camera.global_transform.basis.z

	for rig_name: String in ["ForgeRig", "AnvilRig"]:
		var rig := _root.find_child(rig_name, true, false) as Node3D
		assert_object(rig).is_not_null()
		assert_bool(rig.visible).is_true()

		var to_rig := rig.global_position - camera.global_position
		assert_float(forward.dot(to_rig)).is_greater(0.0)


## 深度优先找第一个指定类名的节点
func _find_first(from: Node, class_name_str: String) -> Node:
	var queue: Array[Node] = [from]

	while not queue.is_empty():
		var node := queue.pop_front() as Node

		if node.is_class(class_name_str):
			return node

		queue.append_array(node.get_children())

	return null


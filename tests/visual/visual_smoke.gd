## 真实渲染视觉冒烟：非 headless 短暂开窗，验证主场景真的"画得出来"（黑屏类故障兜底）。
## ⚠ 此步骤需要显示环境与 GPU（本机 Windows 流程满足；无头 CI 环境需跳过或接虚拟显示，当前不做）。
##
## 三步断言（实例化真实主场景 m0_forge_test.tscn，不用替身——主场景自身的装配错误必须被暴露）：
##   S1 冷态：全图非全黑（均值下限）、非纯色（标准差下限）、刀坯区域与背景角部有亮度差
##   S2 热态：全部段设 900°C → 刀坯区域出现足量热像素（r>g>b 且 r>0.5）、亮度显著上升
##   S3 炉光：刀坯推入炉口 → 炉口区域亮度高于环境基准
##
## 截图存 res://reports/visual_smoke/ 供人工复核；任一步失败打印统计值并以退出码 1 结束。
extends Node3D

# ---- 断言阈值（2026-10-15 第四轮终稿标定：取最终画面实测值约 40~45% 作回归下限）----
## S1 全图平均亮度下限（终稿实测 0.2927；纯背景≈0.21；渲染完全失效≈0。
## 本判据拦"整帧漆黑"，相机/灯光回归由 std 与采样区差值判据拦截）
const S1_MIN_MEAN: float = 0.12

## S1 全图亮度标准差下限，防"纯色屏"（终稿实测 0.1312，回归时≈0）
const S1_MIN_STD: float = 0.06

## S1 刀坯区与背景角部的平均亮度差下限（终稿实测 0.1452，回归时≈0）
const S1_BLADE_DIFF_MIN: float = 0.07

## S1 铁砧采样区与背景角部的平均亮度差下限（终稿实测 0.0807，回归时≈0）
const S1_ANVIL_DIFF_MIN: float = 0.04

## S2 刀坯区热像素数下限（俯视机位实测 619，刀坯投影 47×15px @640×360，取 40%）
const S2_HOT_PIXELS_MIN: int = 250

## S2 热态刀坯区均值相对冷态的抬升下限（终稿实测 0.3849）
const S2_BLADE_HEATUP_MIN: float = 0.15

## S3 炉口区与背景角部的平均亮度差下限（终稿实测 0.1374）
const S3_FORGE_DIFF_MIN: float = 0.06

# ---- 流程参数 ----
## 被验证的真实主场景
const MAIN_SCENE_PATH: String = "res://scenes/m0/m0_forge_test.tscn"

## 开场稳定等待帧数（灯光/粒子稳定）
const WARMUP_FRAMES: int = 30

## 热态/炉光阶段额外等待帧数
const SETTLE_FRAMES: int = 10

## S2 注入温度（°C）
const HOT_TEMP: float = 900.0

## 截图输出目录
const CAPTURE_DIR: String = "res://reports/visual_smoke"

## 看门狗超时（秒）：窗口被遮挡等异常情况下强制失败退出，防 selfcheck 挂死
const WATCHDOG_SECONDS: float = 25.0

## 背景基准采样区（视口左上角，远离场景主体）
const CORNER_RECT := Rect2i(4, 4, 24, 24)

## 炉光采样区边长（px）
const FORGE_RECT_SIZE := Vector2i(90, 90)

## 刀坯屏幕矩形外扩（px，含投影取整余量）
const BLADE_RECT_PAD: int = 2

var _camera: Camera3D
var _blade_mesh: MeshInstance3D
var _blade_rig: Node3D
var _forge_light: OmniLight3D
var _hud: CanvasLayer
var _glue: Node
var _scene_root: Node3D
var _finished: bool = false


func _ready() -> void:
	# 看门狗：任何一步挂起（如窗口被遮挡导致信号不触发）都在超时后以失败退出，防 selfcheck 卡死
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	await _run()


## 看门狗回调：超时仍未完成则判失败
func _on_watchdog() -> void:
	if not _finished:
		_fail("watchdog", "总耗时超过 %.0fs（疑似渲染/信号挂起）" % WATCHDOG_SECONDS)


## 冒烟主流程
func _run() -> void:
	# 无显示环境直接报错退出（退出码 2 区别于断言失败）
	if DisplayServer.get_name() == "headless":
		push_error("visual_smoke: 需要 GUI 显示环境与 GPU，勿在 --headless 下运行")
		get_tree().quit(2)
		return

	DirAccess.open("res://").make_dir_recursive("reports/visual_smoke")

	# 实例化真实主场景
	var packed := load(MAIN_SCENE_PATH) as PackedScene

	if packed == null:
		_fail("setup", "主场景加载失败: " + MAIN_SCENE_PATH)
		return

	var m0_root := packed.instantiate()
	add_child(m0_root)

	_scene_root = m0_root
	_glue = m0_root
	_camera = m0_root.get_node("MainCamera") as Camera3D
	_blade_mesh = m0_root.get_node("BladeRig/BladeMesh") as MeshInstance3D
	_blade_rig = m0_root.get_node("BladeRig") as Node3D
	_forge_light = m0_root.get_node("ForgeRig/ForgeLight") as OmniLight3D
	_hud = m0_root.get_node("DebugHUD") as CanvasLayer

	await _wait_frames(WARMUP_FRAMES)
	_hud.visible = false

	# --- S1 冷态 ---
	var cold_image := await _capture()
	_save_png(cold_image, "s1_cold")

	if not _check_s1(cold_image):
		return

	# --- S2 热态：注入温度 + 触发网格重建（等待胶水层 _physics_process 节流重建）---
	var blade: BladeData = _glue.get("_blade")

	for sec: BladeData.SectionData in blade.sections:
		sec.temp = HOT_TEMP

	_glue.set("_mesh_dirty", true)
	await _wait_frames(SETTLE_FRAMES)

	var hot_image := await _capture()
	_save_png(hot_image, "s2_hot")

	if not _check_s2(cold_image, hot_image):
		return

	# --- S3 炉光：刀坯推入炉口 ---
	var cfg_m0: M0Cfg = _glue.get("_cfg_m0")
	_blade_rig.position.x = cfg_m0.blade_x_max
	await _wait_frames(SETTLE_FRAMES)

	var forge_image := await _capture()
	_save_png(forge_image, "s3_forge")

	if not _check_s3(forge_image):
		return

	print("VISUAL SMOKE PASSED")
	_log("VISUAL SMOKE PASSED")
	_finished = true
	get_tree().quit(0)


## S1 冷态断言：非全黑、非纯色、刀坯/铁砧区与背景有差异
func _check_s1(image: Image) -> bool:
	var whole := _image_stats(image, Rect2i(Vector2i.ZERO, image.get_size()))
	var corner := _image_stats(image, CORNER_RECT)
	var blade := _image_stats(image, _blade_screen_rect(image))
	var blade_diff: float = absf(blade["mean"] - corner["mean"])
	var anvil := _image_stats(image, _node_screen_rect(image, "AnvilRig/Face"))
	var anvil_diff: float = absf(anvil["mean"] - corner["mean"])

	print("S1 whole: mean=%.4f std=%.4f | corner=%.4f | blade=%.4f diff=%.4f | anvil=%.4f diff=%.4f" % [
		whole["mean"], whole["std"], corner["mean"], blade["mean"], blade_diff, anvil["mean"], anvil_diff])
	_log("S1 whole: mean=%.4f std=%.4f | corner=%.4f | blade=%.4f diff=%.4f | anvil=%.4f diff=%.4f" % [
		whole["mean"], whole["std"], corner["mean"], blade["mean"], blade_diff, anvil["mean"], anvil_diff])

	if whole["mean"] <= S1_MIN_MEAN:
		_fail("S1", "全图平均亮度 %.4f <= %.4f（疑似全黑）" % [whole["mean"], S1_MIN_MEAN])
		return false

	if whole["std"] <= S1_MIN_STD:
		_fail("S1", "全图标准差 %.4f <= %.4f（疑似纯色屏）" % [whole["std"], S1_MIN_STD])
		return false

	if blade_diff <= S1_BLADE_DIFF_MIN:
		_fail("S1", "刀坯区与背景亮度差 %.4f <= %.4f（刀坯不可见）" % [blade_diff, S1_BLADE_DIFF_MIN])
		return false

	if anvil_diff <= S1_ANVIL_DIFF_MIN:
		_fail("S1", "铁砧区与背景亮度差 %.4f <= %.4f（铁砧不可见）" % [anvil_diff, S1_ANVIL_DIFF_MIN])
		return false

	return true


## S2 热态断言：刀坯区热像素 + 亮度抬升（火色发光链路）
func _check_s2(cold_image: Image, hot_image: Image) -> bool:
	var rect := _blade_screen_rect(hot_image)
	var hot_pixels: int = _count_hot_pixels(hot_image, rect)

	var cold_blade := _image_stats(cold_image, rect)
	var hot_blade := _image_stats(hot_image, rect)
	var heat_up: float = hot_blade["mean"] - cold_blade["mean"]

	print("S2 blade rect=%s hot_pixels=%d | cold=%.4f hot=%.4f heatup=%.4f" % [
		rect, hot_pixels, cold_blade["mean"], hot_blade["mean"], heat_up])
	_log("S2 blade rect=%s hot_pixels=%d | cold=%.4f hot=%.4f heatup=%.4f" % [
		rect, hot_pixels, cold_blade["mean"], hot_blade["mean"], heat_up])

	if hot_pixels < S2_HOT_PIXELS_MIN:
		_fail("S2", "热像素 %d < %d（火色未渲出）" % [hot_pixels, S2_HOT_PIXELS_MIN])
		return false

	if heat_up <= S2_BLADE_HEATUP_MIN:
		_fail("S2", "刀坯热态亮度抬升 %.4f <= %.4f" % [heat_up, S2_BLADE_HEATUP_MIN])
		return false

	return true


## S3 炉光断言：炉口区域亮度高于环境基准
func _check_s3(image: Image) -> bool:
	var corner := _image_stats(image, CORNER_RECT)
	var forge_rect := _forge_screen_rect(image)
	var forge := _image_stats(image, forge_rect)
	var forge_diff: float = forge["mean"] - corner["mean"]

	print("S3 forge rect=%s mean=%.4f | corner=%.4f diff=%.4f" % [
		forge_rect, forge["mean"], corner["mean"], forge_diff])
	_log("S3 forge rect=%s mean=%.4f | corner=%.4f diff=%.4f" % [
		forge_rect, forge["mean"], corner["mean"], forge_diff])

	if forge_diff <= S3_FORGE_DIFF_MIN:
		_fail("S3", "炉口区与背景亮度差 %.4f <= %.4f（炉光未渲出）" % [forge_diff, S3_FORGE_DIFF_MIN])
		return false

	return true


## 统一失败出口：打印、落盘并退出码 1
func _fail(step: String, message: String) -> void:
	if _finished:
		return

	print("VISUAL SMOKE FAILED [%s] %s" % [step, message])
	_log("VISUAL SMOKE FAILED [%s] %s" % [step, message])
	_finished = true
	get_tree().quit(1)


## 等待 n 个渲染帧 + 一次物理帧（保证物理步进至少发生一次）
func _wait_frames(frame_count: int) -> void:
	for i: int in frame_count:
		await get_tree().process_frame

	await get_tree().physics_frame


## 截取当前视口。
## 注意：不用 RenderingServer.frame_post_draw——窗口被遮挡/最小化时引擎可能跳过绘制，
## 该信号永不发出会挂死流程；读最后一次呈现帧即可满足冒烟需求。
func _capture() -> Image:
	await get_tree().process_frame
	await get_tree().process_frame
	return get_viewport().get_texture().get_image()


## 保存截图供人工复核
func _save_png(image: Image, step_name: String) -> void:
	var err := image.save_png("%s/%s.png" % [CAPTURE_DIR, step_name])

	if err != OK:
		push_warning("visual_smoke: 截图保存失败 %s (%d)" % [step_name, err])


## 统计值落盘（stdout 可能被管道缓冲，落盘保证 selfcheck 日志可查；整份重写保留全部行）
var _log_lines: Array[String] = []


func _log(line: String) -> void:
	_log_lines.append(line)
	var file := FileAccess.open("%s/stats.txt" % CAPTURE_DIR, FileAccess.WRITE)

	if file != null:
		file.store_string("\n".join(_log_lines) + "\n")
		file.close()


## 区域亮度统计（亮度 = Rec.609 luma，0~1）
func _image_stats(image: Image, rect: Rect2i) -> Dictionary:
	var clamped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var data := image.get_data()
	var width: int = image.get_width()
	var bpp: int = _bytes_per_pixel(image)

	var total: float = 0.0
	var total_sq: float = 0.0
	var count: int = 0

	for y: int in range(clamped.position.y, clamped.end.y):
		var row_start: int = y * width * bpp

		for x: int in range(clamped.position.x, clamped.end.x):
			var index: int = row_start + x * bpp
			var r: float = data[index] / 255.0
			var g: float = data[index + 1] / 255.0
			var b: float = data[index + 2] / 255.0
			var luma: float = 0.299 * r + 0.587 * g + 0.114 * b

			total += luma
			total_sq += luma * luma
			count += 1

	if count == 0:
		return {"mean": 0.0, "std": 0.0}

	var mean: float = total / count
	var variance: float = maxf(total_sq / count - mean * mean, 0.0)

	return {"mean": mean, "std": sqrt(variance)}


## 每像素字节数（视口截图为 RGB8 或 RGBA8，按数据长度求，不做格式假设）
func _bytes_per_pixel(image: Image) -> int:
	return image.get_data().size() / maxi(image.get_width() * image.get_height(), 1)


## 统计区域内热像素（r>g>b 且 r>0.5）
func _count_hot_pixels(image: Image, rect: Rect2i) -> int:
	var clamped := rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var data := image.get_data()
	var width: int = image.get_width()
	var bpp: int = _bytes_per_pixel(image)
	var hot_count: int = 0

	for y: int in range(clamped.position.y, clamped.end.y):
		var row_start: int = y * width * bpp

		for x: int in range(clamped.position.x, clamped.end.x):
			var index: int = row_start + x * bpp
			var r: float = data[index] / 255.0
			var g: float = data[index + 1] / 255.0
			var b: float = data[index + 2] / 255.0

			if r > 0.5 and r > g and g > b:
				hot_count += 1

	return hot_count


## 刀坯世界 AABB 投影到屏幕的采样矩形（不写死屏幕坐标，布局可变）
func _blade_screen_rect(image: Image) -> Rect2i:
	return _aabb_screen_rect(_blade_mesh.global_transform * _blade_mesh.get_aabb(), image)


## 按节点路径取 MeshInstance3D 的世界 AABB 投影采样矩形
func _node_screen_rect(image: Image, node_path: String) -> Rect2i:
	var mesh_instance := _scene_root.get_node_or_null(NodePath(node_path)) as MeshInstance3D

	if mesh_instance == null:
		_fail("S1", "找不到采样节点 " + node_path)
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)

	return _aabb_screen_rect(mesh_instance.global_transform * mesh_instance.get_aabb(), image)


## 世界 AABB 投影到屏幕矩形（8 角点 unproject 取包络 + 外扩）
func _aabb_screen_rect(world_aabb: AABB, image: Image) -> Rect2i:
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)

	for i: int in 8:
		var corner := Vector3(
			world_aabb.position.x + (1 if i & 1 else 0) * world_aabb.size.x,
			world_aabb.position.y + (1 if i & 2 else 0) * world_aabb.size.y,
			world_aabb.position.z + (1 if i & 4 else 0) * world_aabb.size.z)
		var screen := _camera.unproject_position(corner)
		min_point = min_point.min(screen)
		max_point = max_point.max(screen)

	var rect := Rect2i(
		Vector2i(min_point) - Vector2i(BLADE_RECT_PAD, BLADE_RECT_PAD),
		Vector2i(max_point - min_point) + Vector2i(BLADE_RECT_PAD * 2, BLADE_RECT_PAD * 2))

	return rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))


## 炉口点光投影到屏幕的采样矩形
func _forge_screen_rect(image: Image) -> Rect2i:
	var center := Vector2i(_camera.unproject_position(_forge_light.global_position))
	var rect := Rect2i(center - FORGE_RECT_SIZE / 2, FORGE_RECT_SIZE)

	return rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))

## 自动试玩（真实渲染，非 headless）：程序化驱动完整玩法序列并逐步截图/状态落盘。
## ⚠ 需要显示环境与 GPU（无头 CI 需跳过或接虚拟显示，当前不做）。
## 运行：godot --path . --resolution 960x540 res://tests/visual/auto_play.tscn
##
## 强制流程（用户指令，永久）：凡渲染/场景/材质/灯光/玩法改动，本试玩 + Team Lead 视觉复核为收尾关卡。
## 输入一律走 Input.parse_input_event 真实事件（与玩家输入同链路进 _input / Input.get_axis），不绕过输入层直调函数。
##
## 序列：a 冷态 → b 按住 D 推刀入炉 → c 等待 15s 加热 → d 按住 A 拉回砧上 → e 对最热段连点 3 锤
##（每锤：击发后 0.08s 火花帧截图 + 0.5s 形变帧截图）→ f 末态玩法校验（升温/形变/应力真实发生）。
## 截图与状态 dump 存 res://reports/playtest/ 供 Team Lead 视觉复核；失败退出码 1。
extends Node3D

## 被驱动的真实主场景
const MAIN_SCENE_PATH: String = "res://scenes/m0/m0_forge_test.tscn"

## 输出目录
const OUT_DIR: String = "res://reports/playtest"

## 看门狗超时（秒）
const WATCHDOG_SECONDS: float = 90.0

## 炉内加热等待（秒）
const HEAT_WAIT_SECONDS: float = 15.0

## 连打锤数
const STRIKE_COUNT: int = 3

## 移动键保持单步超时（秒）
const MOVE_TIMEOUT_SECONDS: float = 12.0

## 末态校验：加热后最热段温度下限（°C，经真实输入链路完成）
const HEATED_TEMP_MIN: float = 600.0

var _glue: Node
var _scene_root: Node3D
var _camera: Camera3D
var _blade_rig: Node3D
var _log_lines: Array[String] = []
var _finished: bool = false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_SECONDS).timeout.connect(_on_watchdog)
	await _run()


## 看门狗：超时仍未完成则失败退出，防挂死
func _on_watchdog() -> void:
	if not _finished:
		_fail("watchdog", "总耗时超过 %.0fs（疑似输入/渲染挂起）" % WATCHDOG_SECONDS)


## 试玩主流程
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("auto_play: 需要 GUI 显示环境与 GPU，勿在 --headless 下运行")
		get_tree().quit(2)
		return

	DirAccess.open("res://").make_dir_recursive("reports/playtest")

	var packed := load(MAIN_SCENE_PATH) as PackedScene

	if packed == null:
		_fail("setup", "主场景加载失败: " + MAIN_SCENE_PATH)
		return

	var m0_root := packed.instantiate()
	add_child(m0_root)

	_scene_root = m0_root
	_glue = m0_root
	_camera = m0_root.get_node("MainCamera") as Camera3D
	_blade_rig = m0_root.get_node("BladeRig") as Node3D

	await _wait_frames(20)

	# --- a 冷态 ---
	_shot("a_cold")
	_dump("a_cold")

	# --- b 按住 D 推入煤床，等 5s 截图（初始升温可见、刀坯微红），dump 附位姿证明零倾斜 ---
	var cfg_m0: M0Cfg = _glue.get("_cfg_m0")
	var reached_forge := await _hold_move_key(KEY_D, cfg_m0.blade_x_max - 0.005, MOVE_TIMEOUT_SECONDS)
	await _wait_seconds(5.0)
	_shot("b_in_forge")
	_dump("b_in_forge")

	if not reached_forge:
		_fail("b", "刀坯未能推到炉口（rig_x=%.3f）" % _blade_rig.position.x)
		return

	# --- c 炉内加热 15s 后拉回"半入炉口"截图（口部朝玩家：外露段大面入画 + 分界可见）---
	await _wait_seconds(HEAT_WAIT_SECONDS)
	var half_in_x: float = cfg_m0.forge_mouth_x_min - 0.17
	await _hold_move_key(KEY_A, half_in_x, MOVE_TIMEOUT_SECONDS)
	_shot("c_heated_half_out")
	_dump("c_heated_half_out")

	# --- d 按住 A 拉回砧上（真实键盘事件）---
	var reached_anvil := await _hold_move_key(KEY_A, -0.085, MOVE_TIMEOUT_SECONDS)
	_shot("d_back_anvil")

	if not reached_anvil:
		_fail("d", "刀坯未能拉回砧上（rig_x=%.3f）" % _blade_rig.position.x)
		return

	# --- e 切锻锤（真实按键）后对最热段连打 3 锤（真实鼠标点击事件）---
	_send_key(KEY_2, true)
	await get_tree().process_frame
	_send_key(KEY_2, false)
	_log("switch to forge hammer (hammer_index=%s)" % str(_glue.get("_hammer_index")))

	var strike_seg := _hottest_segment()
	_log("strike target seg=%d T=%.0f°C" % [strike_seg, _get_blade().sections[strike_seg].temp])

	for i: int in STRIKE_COUNT:
		await _aim_and_click(strike_seg)
		await _wait_seconds(0.05)
		_shot("e_strike%d_spark" % (i + 1))

		await _wait_seconds(0.5)
		_shot("e_strike%d_after" % (i + 1))
		_dump("e_strike%d" % (i + 1))
		await _wait_seconds(0.4)

	# --- f 末态玩法校验（真实输入链路驱动出的结果）---
	if not _check_final_state(strike_seg):
		return

	_log("AUTO PLAY DONE")
	_log("AUTO PLAY DONE（截图与 dump 见 " + OUT_DIR + "，等待 Team Lead 视觉复核）")
	_finished = true
	get_tree().quit(0)


## 末态校验：升温 / 形变 / 应力确实经真实输入链路发生
func _check_final_state(strike_seg: int) -> bool:
	var blade := _get_blade()
	var cfg_m0: M0Cfg = _glue.get("_cfg_m0")
	var max_temp: float = 0.0

	for sec: BladeData.SectionData in blade.sections:
		max_temp = maxf(max_temp, sec.temp)

	var struck := blade.sections[strike_seg]
	# 远邻段（|Δ|=2）：右越界则向左取，保证不是打点段自身
	var neighbor_index: int = strike_seg + 2 if strike_seg + 2 < blade.sections.size() else strike_seg - 2
	var neighbor: BladeData.SectionData = blade.sections[neighbor_index]
	var deformed: bool = struck.thickness < cfg_m0.blank_thickness - 1.0 or struck.width > cfg_m0.blank_width + 1.0
	# 打点段与远邻段的形变差必须可辨（单锤 ≥8% 厚度的手感标定）
	var deform_gap: float = neighbor.thickness - struck.thickness
	var stressed: bool = struck.stress > 0.0

	_log("final: max_temp=%.1f°C struck(th=%.2f w=%.2f stress=%.1f) neighbor(th=%.2f) gap=%.2fmm" % [
		max_temp, struck.thickness, struck.width, struck.stress, neighbor.thickness, deform_gap])

	if deform_gap < cfg_m0.blank_thickness * 0.08:
		_fail("f", "形变量不足：打点段与邻段厚度差 %.2fmm < 单锤 8%% 标定" % deform_gap)
		return false

	if max_temp < HEATED_TEMP_MIN:
		_fail("f", "加热链路未生效：最热段 %.1f°C < %.1f°C" % [max_temp, HEATED_TEMP_MIN])
		return false

	if not deformed:
		_fail("f", "锤击未产生形变：th=%.2f w=%.2f" % [struck.thickness, struck.width])
		return false

	if not stressed:
		_fail("f", "锤击未积累应力：stress=%.1f" % struck.stress)
		return false

	return true


## 按住方向键直到刀坯 x 到达目标（或超时）；返回是否到达
func _hold_move_key(key: Key, target_x: float, timeout_seconds: float) -> bool:
	var is_right: bool = key == KEY_D

	_send_key(key, true)

	var elapsed: float = 0.0

	while elapsed < timeout_seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

		var x: float = _blade_rig.position.x

		if is_right and x >= target_x:
			break

		if not is_right and x <= target_x:
			break

	_send_key(key, false)

	if is_right:
		return _blade_rig.position.x >= target_x
	return _blade_rig.position.x <= target_x


## 鼠标移动到目标段上方（warp_mouse 真实移动指针驱动锤跟随），待收敛后左键挥击。
## 命中段=锤头位置（胶水层新链路），无斜射补偿需求。
func _aim_and_click(seg_index: int) -> void:
	var sec: BladeData.SectionData = _get_blade().sections[seg_index]
	var world := Vector3(_blade_rig.position.x + sec.x * 0.001, 0.447, 0.0)
	var screen: Vector2 = _camera.unproject_position(world)

	# 真实移动鼠标（合成 motion 事件不驱动 get_mouse_position，warp 才是正路）
	get_viewport().warp_mouse(screen)
	await get_tree().process_frame

	# 等锤子 lerp 跟随收敛（12/s → 0.6s 后残差 <0.1%）
	await _wait_seconds(0.6)
	_log("aim: seg=%d world_x=%.4f hammer_target_x=%.4f" % [
		seg_index, world.x, float(_glue.get("_hammer_target_x"))])

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen
	press.pressed = true
	Input.parse_input_event(press)

	await get_tree().process_frame

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = screen
	release.pressed = false
	Input.parse_input_event(release)


## 发送键盘按下/抬起真实事件
func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


## 最热段号
func _hottest_segment() -> int:
	var blade := _get_blade()
	var best: int = 0

	for i: int in blade.sections.size():
		if blade.sections[i].temp > blade.sections[best].temp:
			best = i

	return best


func _get_blade() -> BladeData:
	return _glue.get("_blade") as BladeData


## 截图（等 2 帧后取最后呈现帧，不依赖 frame_post_draw 信号）
func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("%s/%s.png" % [OUT_DIR, name])

	if err != OK:
		push_warning("auto_play: 截图保存失败 %s (%d)" % [name, err])

	_log("shot: %s.png" % name)


## 分段状态 dump（温度/宽/厚/偏移/应力 + 刀坯位姿）落盘并打印
func _dump(tag: String) -> void:
	var blade := _get_blade()
	var lines: Array[String] = []
	# 位姿数值：y 恒定 0.447、z 恒定 0、零旋转——证明刀坯仅沿 x 平移，无倾斜（回应视觉误读）
	lines.append("[%s] rig=(x=%.3f y=%.3f z=%.3f) rot_deg=(%.2f, %.2f, %.2f) hammer=%s" % [
		tag, _blade_rig.position.x, _blade_rig.position.y, _blade_rig.position.z,
		_blade_rig.rotation_degrees.x, _blade_rig.rotation_degrees.y, _blade_rig.rotation_degrees.z,
		str(_glue.get("_hammer_index"))])

	for i: int in blade.sections.size():
		var sec: BladeData.SectionData = blade.sections[i]
		lines.append("  seg%02d T=%6.1f w=%5.2f th=%5.2f off=%+.2f stress=%5.1f" % [
			i, sec.temp, sec.width, sec.thickness, sec.offset_y, sec.stress])

	var text := "\n".join(lines)
	print(text)
	_log_block(text)


## 统一失败出口：打印、落盘并退出码 1
func _fail(step: String, message: String) -> void:
	if _finished:
		return

	var text := "AUTO PLAY FAILED [%s] %s" % [step, message]
	print(text)
	_log_block(text)
	_finished = true
	get_tree().quit(1)


## 单行落盘
func _log(line: String) -> void:
	_log_lines.append(line)
	_write_log()


## 多行落盘
func _log_block(text: String) -> void:
	for line: String in text.split("\n"):
		_log_lines.append(line)

	_write_log()


## 整份重写（stdout 可能被管道缓冲，落盘保证可查）
func _write_log() -> void:
	var file := FileAccess.open("%s/dump.txt" % OUT_DIR, FileAccess.WRITE)

	if file != null:
		file.store_string("\n".join(_log_lines) + "\n")
		file.close()


## 等待指定秒数（按帧推进）
func _wait_seconds(seconds: float) -> void:
	var elapsed: float = 0.0

	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


## 等待渲染帧 + 一次物理帧
func _wait_frames(frame_count: int) -> void:
	for i: int in frame_count:
		await get_tree().process_frame

	await get_tree().physics_frame

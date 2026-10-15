## M0 锻打原型主场景胶水层：装配表 → 驱动 sim 固定步长 → 呈现网格与五件套反馈。
## 本文件零玩法公式：形变/热学全部在 sim/，参数全部在 data/ 表。
extends Node3D

# --- 数据表路径（M0 直接路径加载，表注册中心 M1 建立）---
const PATH_CFG_SIM: String = "res://data/cfg/cfg_sim.tres"
const PATH_CFG_M0: String = "res://data/cfg/cfg_m0.tres"
const PATH_STEEL: String = "res://data/steels/steel_1084.tres"
const PATH_HAMMER_HAND: String = "res://data/props/prop_hammer_hand.tres"
const PATH_HAMMER_FORGE: String = "res://data/props/prop_hammer_forge.tres"
const PATH_FORGE_COAL: String = "res://data/props/prop_forge_coal.tres"

# --- 表现层常量（手感/视觉，非玩法数值）---
## 刀坯平移速度（m/s）
const BLADE_MOVE_SPEED: float = 0.35

## 网格重建最小间隔（ms，约 30fps 呈现节流）
const MESH_REBUILD_INTERVAL_MS: float = 33.0

## HUD 刷新间隔（秒）
const HUD_UPDATE_INTERVAL: float = 0.2

## 炉口点光基础强度（实际 = 基础 × flux_factor）
const FORGE_LIGHT_BASE_ENERGY: float = 3.0

## 热钢点光最大强度（平均温度到 LUT 上限时，冷态为 0）
const BLADE_GLOW_MAX_ENERGY: float = 2.6

## 受击段高亮闪光时长（秒，纯感知层强化，不动模拟数值）
const STRIKE_FLASH_SECONDS: float = 0.15

## 炉口覆盖边缘渐变宽度（m，方案定 20mm）
const COVERAGE_EDGE_FADE: float = 0.02

## 锤子鼠标跟随平滑系数（越大跟得越紧）
const HAMMER_FOLLOW_LERP: float = 12.0

## 摆角 ±33° 下支点到锤头的水平投影（瞄准位 = 锤支点 x − 此值）
const HAMMER_ARM_REACH: float = 0.4195

## 锤支点固定高度（摆角 33° 时锤底正好触刀面 0.454）
const HAMMER_PIVOT_Y: float = 0.751

## 锤击火花/闪光参考高度（刀面上方一点）
const STRIKE_FX_Y: float = 0.46

## 鼠标瞄准投影平面高度（刀坯中心面）
const AIM_PLANE_Y: float = 0.447

var _cfg: SimCfg
var _cfg_m0: M0Cfg
var _steel: SteelDef
var _forge_def: ForgeDef
var _hammers: Array[HammerDef] = []
var _hammer_index: int = 0

var _blade: BladeData
var _forge_state: HeatSim.ForgeState
var _rng: SimRng

var _accumulator: float = 0.0
var _strike_cooldown: float = 0.0
var _mesh_dirty: bool = true
var _last_rebuild_ms: float = -10000.0
var _hud_timer: float = 0.0
var _flash_seg: int = -1
var _flash_timer: float = 0.0
var _hammer_target_x: float = 0.0

@onready var _hammer_rig: Node3D = $HammerRig
@onready var _blade_rig: Node3D = $BladeRig
@onready var _blade_mesh: MeshInstance3D = $BladeRig/BladeMesh
@onready var _hammer_anim: Node3D = $HammerRig
@onready var _spark: GPUParticles3D = $SparkBurst
@onready var _sfx: Node = $SfxStriker
@onready var _camera_shake: Camera3D = $MainCamera
@onready var _forge_light: OmniLight3D = $ForgeRig/ForgeLight
@onready var _blade_glow: OmniLight3D = $BladeRig/BladeGlow
@onready var _hud: CanvasLayer = $DebugHUD
@onready var _hud_label: Label = $DebugHUD/Label


func _ready() -> void:
	_cfg = load(PATH_CFG_SIM) as SimCfg
	_cfg_m0 = load(PATH_CFG_M0) as M0Cfg
	_steel = load(PATH_STEEL) as SteelDef
	_forge_def = load(PATH_FORGE_COAL) as ForgeDef

	_hammers.append(load(PATH_HAMMER_HAND) as HammerDef)
	_hammers.append(load(PATH_HAMMER_FORGE) as HammerDef)

	_reset_simulation()


func _reset_simulation() -> void:
	# 重建种子与随机源（R 重置可复现）
	_rng = SimRng.new()
	_rng.setup(_cfg_m0.sim_seed)

	_blade = BladeData.create_bar(_steel.id, _cfg_m0)

	_forge_state = HeatSim.ForgeState.new()
	_forge_state.flux_factor = 1.0
	_forge_state.timer = 0.0
	_forge_state.ref_volume = _blade.ref_volume(_cfg_m0)

	# 静息位：刀坯中心对准砧面中心（世界原点）
	_blade_rig.position.x = -_cfg_m0.blank_length * 0.5 * 0.001

	# 锤瞄准位归中（刀坯中点）
	_hammer_target_x = 0.0
	_hammer_rig.position = Vector3(_hammer_target_x + HAMMER_ARM_REACH, HAMMER_PIVOT_Y, 0.0)

	_accumulator = 0.0
	_strike_cooldown = 0.0
	_rebuild_mesh()


func _physics_process(delta: float) -> void:
	# A/D 平移刀坯（范围 clamp 自表）
	var move: float = Input.get_axis("blade_left", "blade_right")

	if absf(move) > 0.001:
		_blade_rig.position.x = clampf(
			_blade_rig.position.x + move * BLADE_MOVE_SPEED * delta,
			_cfg_m0.blade_x_min, _cfg_m0.blade_x_max)

	# 锤子沿刀坯轴向平滑跟随鼠标（瞄准即所见：锤头悬于将击打位置上方）
	_update_hammer_follow(delta)

	# 固定步长累加器：coverage → heat.tick
	_accumulator += delta

	while _accumulator >= _cfg.dt:
		var coverage := _compute_coverage()
		HeatSim.tick(_blade, _steel, _cfg, _forge_def, _forge_state, coverage, _rng)
		_accumulator -= _cfg.dt
		_mesh_dirty = true

	# 炉口点光强度随炉温波动
	_forge_light.light_energy = FORGE_LIGHT_BASE_ENERGY * _forge_state.flux_factor

	# 热钢点光：强度 ∝ 平均温度（冷态 0，热钢必须照亮砧面）
	var avg_temp: float = 0.0

	for sec: BladeData.SectionData in _blade.sections:
		avg_temp += sec.temp

	avg_temp /= float(_blade.sections.size())

	var glow_ratio: float = clampf(
		(avg_temp - _cfg.heat_lut_temp_min) / (_cfg.heat_lut_temp_max - _cfg.heat_lut_temp_min),
		0.0, 1.0)
	_blade_glow.light_energy = glow_ratio * BLADE_GLOW_MAX_ENERGY

	# 锤击冷却递减
	_strike_cooldown = maxf(_strike_cooldown - delta, 0.0)

	# 受击段高亮闪光衰减（期间保持网格重建以呈现渐灭）
	if _flash_timer > 0.0:
		_flash_timer = maxf(_flash_timer - delta, 0.0)
		_mesh_dirty = true

		if _flash_timer <= 0.0:
			_flash_seg = -1

	# 网格重建节流（形变/火色随下帧呈现）
	if _mesh_dirty:
		var now_ms: float = Time.get_ticks_msec()

		if now_ms - _last_rebuild_ms >= MESH_REBUILD_INTERVAL_MS:
			_rebuild_mesh()

	# HUD 节流刷新
	_hud_timer += delta

	if _hud_timer >= HUD_UPDATE_INTERVAL:
		_hud_timer = 0.0
		_update_hud()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("forge_strike"):
		# input_to_impact_delay 表值恒为 0（即打即中）；>0 的延迟落锤留 M1 手感迭代
		if _strike_cooldown <= 0.0 and _cfg_m0.input_to_impact_delay <= 0.0:
			_try_strike()

	elif event.is_action_pressed("switch_hammer_1"):
		_hammer_index = 0
	elif event.is_action_pressed("switch_hammer_2"):
		_hammer_index = 1
	elif event.is_action_pressed("reset_blade"):
		_reset_simulation()
	elif event.is_action_pressed("toggle_debug_hud"):
		_hud.visible = not _hud.visible
	elif event.is_action_pressed("quit_m0"):
		get_tree().quit()


## 锤子沿刀坯轴向平滑跟随鼠标：鼠标射线投到刀坯高度平面取 x，clamp 到刀坯范围，
## 锤支点 x = 瞄准位 + HAMMER_ARM_REACH（±33° 对称摆角保证静息/落锤锤头同 x，瞄准即所见）
func _update_hammer_follow(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_normal := camera.project_ray_normal(mouse_pos)

	# 与刀坯中心水平面求交（俯视角下 |n.y| 接近 1）
	if absf(ray_normal.y) > 0.1:
		var t := (AIM_PLANE_Y - ray_origin.y) / ray_normal.y

		if t > 0.0:
			var aim_x: float = ray_origin.x + ray_normal.x * t
			var blade_left: float = _blade_rig.position.x + 0.002
			var blade_right: float = _blade_rig.position.x + _cfg_m0.blank_length * 0.001 - 0.002

			# 刀坯在画面外（远处）时钳到最近端，保证锤始终有定义
			aim_x = clampf(aim_x, blade_left, blade_right)
			_hammer_target_x = lerpf(_hammer_target_x, aim_x,
				minf(1.0, delta * HAMMER_FOLLOW_LERP))
			_hammer_rig.position.x = _hammer_target_x + HAMMER_ARM_REACH
			_hammer_rig.position.y = HAMMER_PIVOT_Y


## 尝试一次锤击：命中段 = 锤头当前瞄准位（不再是斜射线拾取），顶面锻打
func _try_strike() -> void:
	_strike_cooldown = _cfg_m0.strike_cooldown
	_hammer_anim.play_impact()

	var local_mm: float = (_hammer_target_x - _blade_rig.position.x) * 1000.0
	var seg: int = clampi(
		int(round(local_mm / _blade.segment_length - 0.5)),
		0, _blade.sections.size() - 1)

	var hit_pos := Vector3(_hammer_target_x, STRIKE_FX_Y, 0.0)
	var hit_normal := Vector3.UP

	var result := ForgeSim.strike(_blade, seg, 0, _hammers[_hammer_index],
		_cfg, _cfg_m0.anvil_face_width)

	_mesh_dirty = true
	_play_feedback(result, hit_pos, hit_normal)


## 锤击五件套反馈：火花 / 音效 / 震屏 / 动画已播 / 受击闪光 + 形变随下帧网格重建
func _play_feedback(result: ForgeSim.StrikeResult, hit_pos: Vector3, hit_normal: Vector3) -> void:
	var temp: float = _blade.sections[result.seg].temp
	_spark.burst(hit_pos, hit_normal, temp, _cfg_m0.spark_curve)
	_sfx.play_strike(temp)
	_camera_shake.add_trauma(_hammers[_hammer_index].shake_trauma)
	_flash_seg = result.seg
	_flash_timer = STRIKE_FLASH_SECONDS


## 炉口覆盖系数：段中心世界 x 落炉口区间为 1，边缘 20mm 线性渐变
func _compute_coverage() -> Array[float]:
	var coverage: Array[float] = []
	coverage.resize(_blade.sections.size())
	coverage.fill(0.0)

	var mouth_min: float = _cfg_m0.forge_mouth_x_min
	var mouth_max: float = _cfg_m0.forge_mouth_x_max
	var fade: float = COVERAGE_EDGE_FADE

	for i: int in _blade.sections.size():
		var world_x: float = _blade_rig.position.x + _blade.sections[i].x * 0.001

		if world_x <= mouth_min - fade or world_x >= mouth_max + fade:
			continue

		if world_x < mouth_min:
			coverage[i] = (world_x - (mouth_min - fade)) / fade
		elif world_x > mouth_max:
			coverage[i] = ((mouth_max + fade) - world_x) / fade
		else:
			coverage[i] = 1.0

	return coverage


## 重建刀坯网格（火色顶点色 + 截面形变 + 受击闪光）
func _rebuild_mesh() -> void:
	_last_rebuild_ms = Time.get_ticks_msec()
	_mesh_dirty = false

	var flash_strength: float = 0.0
	if _flash_seg >= 0:
		flash_strength = _flash_timer / STRIKE_FLASH_SECONDS

	_blade_mesh.mesh = BladeMeshBuilder.build(_blade, _cfg, _flash_seg, flash_strength,
		_cfg_m0.blank_width * _cfg_m0.blank_thickness)


## 刷新调试 HUD：分段温度/应力/尺寸 + 锤型 + 种子 + 帧率
func _update_hud() -> void:
	var lines: Array[String] = []
	lines.append("M0 锻刀原型 | 锤型: %s | seed: %d | fps: %d" % [
		_hammers[_hammer_index].display_name,
		_cfg_m0.sim_seed,
		Engine.get_frames_per_second()])
	lines.append("段  温度°C  应力  厚mm  宽mm")

	for i: int in _blade.sections.size():
		var sec: BladeData.SectionData = _blade.sections[i]
		lines.append("%2d  %6.0f  %4.0f  %4.1f  %4.1f" % [
			i, sec.temp, sec.stress, sec.thickness, sec.width])

	_hud_label.text = "\n".join(lines)

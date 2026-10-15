## 火花爆发组件：挂在 GPUParticles3D 上，单击触发一次定量爆发。
## 火花量随温度走 cfg_m0.spark_curve；视觉为加色混合的亮黄白流光 sprite
##（白心透明边径向渐变贴图 + 生命周期白热→橙→暗红 HDR 色带 + 短拖尾）。
extends GPUParticles3D

## 火花寿命（秒）
const SPARK_LIFETIME: float = 0.4

## 拖尾参数（流光感）
const TRAIL_LIFETIME: float = 0.1

## 火花尺寸（m，粒子缩放，加色混合下小而亮）
const SPARK_SCALE_MIN: float = 0.006
const SPARK_SCALE_MAX: float = 0.014

## 出生球半径（m）：避免全部挤在同一点成团
const SPAWN_RADIUS: float = 0.006

## 径向渐变贴图边长（px）
const SPRITE_SIZE: int = 32

## 火色温度区间（与 cfg_sim.heat_lut 一致，用于速度/数量随温度调节）
const HEAT_TEMP_MIN: float = 480.0
const HEAT_TEMP_MAX: float = 1350.0

var _process_mat: ParticleProcessMaterial
var _draw_mat: StandardMaterial3D


func _ready() -> void:
	one_shot = true
	emitting = false
	explosiveness = 1.0
	lifetime = SPARK_LIFETIME
	trail_enabled = true
	trail_lifetime = TRAIL_LIFETIME

	# 独享资源实例，避免同场景多实例互相污染
	_process_mat = ParticleProcessMaterial.new()
	_process_mat.direction = Vector3.UP
	_process_mat.spread = 85.0
	_process_mat.initial_velocity_min = 1.4
	_process_mat.initial_velocity_max = 3.2
	_process_mat.gravity = Vector3(0.0, -9.8, 0.0)
	_process_mat.scale_min = SPARK_SCALE_MIN
	_process_mat.scale_max = SPARK_SCALE_MAX
	_process_mat.damping_min = 0.6
	_process_mat.damping_max = 1.4
	_process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_process_mat.emission_sphere_radius = SPAWN_RADIUS
	_process_mat.color_ramp = _make_life_ramp()
	process_material = _process_mat

	# 加色混合亮 sprite：程序生成白心透明边径向渐变贴图
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	_draw_mat = StandardMaterial3D.new()
	_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_draw_mat.albedo_texture = _make_sprite_texture()
	_draw_mat.vertex_color_use_as_albedo = true
	quad.material = _draw_mat
	draw_pass_1 = quad


## 触发一次火花爆发。
## [param pos] 命中点（世界坐标）
## [param normal] 命中面法线（世界坐标，火花飞出方向）
## [param temp] 命中段温度（°C）
## [param curve] 火花量曲线（温度 → 粒子数）
func burst(pos: Vector3, normal: Vector3, temp: float, curve: PackedFloat32Array) -> void:
	global_position = pos

	var spark_count: int = int(round(CurveUtil.eval_curve(curve, temp)))

	if spark_count <= 0:
		return

	amount = spark_count
	var heat_ratio: float = clampf(
		(temp - HEAT_TEMP_MIN) / (HEAT_TEMP_MAX - HEAT_TEMP_MIN), 0.0, 1.0)

	# 温度越高喷得越猛（发射方向绑定受击面法线，与击点零空隙）
	_process_mat.direction = normal.normalized()
	_process_mat.initial_velocity_min = 1.2 + heat_ratio * 1.6
	_process_mat.initial_velocity_max = 2.4 + heat_ratio * 3.4

	restart()


## 生命周期色带：白热(HDR 触发 bloom) → 橙 → 暗红淡出（火花冷却的物理观感）
func _make_life_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(4.0, 3.6, 2.6, 1.0))
	gradient.add_point(0.35, Color(2.5, 1.2, 0.3, 1.0))
	gradient.add_point(1.0, Color(0.5, 0.1, 0.02, 0.0))

	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## 程序生成径向渐变贴图：白心 → 透明边
func _make_sprite_texture() -> ImageTexture:
	var image := Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	var half: float = SPRITE_SIZE * 0.5

	for y: int in SPRITE_SIZE:
		for x: int in SPRITE_SIZE:
			var dx: float = float(x) + 0.5 - half
			var dy: float = float(y) + 0.5 - half
			var radius: float = sqrt(dx * dx + dy * dy) / half
			# 中心亮核 + 平方衰减拖尾
			var alpha: float = pow(clampf(1.0 - radius, 0.0, 1.0), 2.2)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(image)

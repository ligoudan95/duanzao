## ForgeSim 锻打形变 / 应力用例（含守恒律、clamp、邻段衰减）。
extends GdUnitTestSuite

var _cfg: SimCfg
var _cfg_m0: M0Cfg
var _hammer_hand: HammerDef
var _hammer_forge: HammerDef


func before_test() -> void:
	_cfg = load("res://data/cfg/cfg_sim.tres") as SimCfg
	_cfg_m0 = load("res://data/cfg/cfg_m0.tres") as M0Cfg
	_hammer_hand = load("res://data/props/prop_hammer_hand.tres") as HammerDef
	_hammer_forge = load("res://data/props/prop_hammer_forge.tres") as HammerDef


## 构建指定温度的均匀刀坯
func _make_blade(temp: float) -> BladeData:
	var blade := BladeData.create_bar("steel_1084", _cfg_m0)

	for sec: BladeData.SectionData in blade.sections:
		sec.temp = temp

	return blade


func test_malleability_curve() -> void:
	# ① m 曲线：700°C → m=0；900°C → m=1；600°C → cold_hit 且不变形
	var blade_cold_edge := _make_blade(700.0)
	var result_edge := ForgeSim.strike(blade_cold_edge, 8, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)
	assert_float(result_edge.m).is_equal(0.0)

	var blade_hot := _make_blade(900.0)
	var result_hot := ForgeSim.strike(blade_hot, 8, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)
	assert_float(result_hot.m).is_equal(1.0)

	var blade_cold := _make_blade(600.0)
	var sec_before: float = blade_cold.sections[8].thickness
	var result_cold := ForgeSim.strike(blade_cold, 8, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)
	assert_bool(result_cold.cold_hit).is_true()
	assert_float(result_cold.d_thickness).is_equal(0.0)
	assert_float(blade_cold.sections[8].thickness).is_equal(sec_before)


func test_volume_conservation_on_flatten() -> void:
	# ② 平面锻打体积近似守恒：w'·th' ∈ [0.87·A, A]
	var blade := _make_blade(1100.0)
	var sec := blade.sections[8]
	var area_before: float = sec.width * sec.thickness

	ForgeSim.strike(blade, 8, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)

	var area_after: float = sec.width * sec.thickness
	assert_float(area_after).is_greater_equal(0.87 * area_before)
	assert_float(area_after).is_less_equal(area_before)


func test_neighbor_falloff() -> void:
	# ③ 邻段击深衰减：|Δ|=1 → 0.35；|Δ|=2 → 0.1225
	var blade := _make_blade(1100.0)
	var seg := 8
	var th_before: float = blade.sections[seg].thickness

	ForgeSim.strike(blade, seg, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)

	var d_main: float = blade.sections[seg].thickness - th_before
	var d_n1: float = blade.sections[seg + 1].thickness - th_before
	var d_n2: float = blade.sections[seg + 2].thickness - th_before

	assert_float(d_n1 / d_main).is_equal_approx(0.35, 1e-5)
	assert_float(d_n2 / d_main).is_equal_approx(0.1225, 1e-5)


func test_min_thickness_clamp() -> void:
	# ④ 连续热打：厚度不破 min_thickness，且触底时置位 clamped_thickness
	var blade := _make_blade(1100.0)
	var seg := 8
	var clamp_seen := false

	for i: int in 20:
		var result := ForgeSim.strike(blade, seg, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)
		clamp_seen = clamp_seen or result.clamped_thickness

	assert_float(blade.sections[seg].thickness).is_greater_equal(_cfg.min_thickness - 1e-9)
	assert_float(blade.sections[seg].thickness).is_equal_approx(_cfg.min_thickness, 1e-6)
	assert_bool(clamp_seen).is_true()


func test_anvil_width_clamp() -> void:
	# ⑤ 连续热打：宽度不超砧宽上限（anvil_width·1.3），且触顶时置位 clamped_width
	var blade := _make_blade(1100.0)
	var seg := 8
	var width_max: float = _cfg_m0.anvil_face_width * _cfg.width_max_factor
	var clamp_seen := false

	for i: int in 60:
		var result := ForgeSim.strike(blade, seg, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)
		clamp_seen = clamp_seen or result.clamped_width

	assert_float(blade.sections[seg].width).is_less_equal(width_max + 1e-9)
	assert_bool(clamp_seen).is_true()


func test_stress_rules() -> void:
	# ⑥ 冷打应力 > 热打；手锤应力减半；线性累积封顶 100
	var blade_cold := _make_blade(600.0)
	var stress_cold: float = ForgeSim.strike(blade_cold, 8, 0, _hammer_hand, _cfg, _cfg_m0.anvil_face_width).stress_added

	var blade_hot := _make_blade(1100.0)
	var stress_hot: float = ForgeSim.strike(blade_hot, 8, 0, _hammer_hand, _cfg, _cfg_m0.anvil_face_width).stress_added

	assert_float(stress_cold).is_greater(stress_hot)

	var blade_hand := _make_blade(600.0)
	var stress_hand: float = ForgeSim.strike(blade_hand, 8, 0, _hammer_hand, _cfg, _cfg_m0.anvil_face_width).stress_added

	var blade_forge := _make_blade(600.0)
	var stress_forge: float = ForgeSim.strike(blade_forge, 8, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width).stress_added

	# 表内手锤 power=0.4·mult=0.5，锻锤 1.0·1.0 → 应力 5 倍
	assert_float(stress_forge).is_equal_approx(stress_hand * 5.0, 1e-5)

	# 隔离验证 stress_mult 减半：同 power 仅 mult 不同 → 应力严格减半
	var hammer_full := HammerDef.new()
	hammer_full.id = "prop_test_full"
	hammer_full.power = 0.4
	hammer_full.stress_mult = 1.0

	var blade_synthetic := _make_blade(600.0)
	var stress_full: float = ForgeSim.strike(blade_synthetic, 8, 0, hammer_full, _cfg, _cfg_m0.anvil_face_width).stress_added

	assert_float(stress_hand).is_equal_approx(stress_full * 0.5, 1e-5)

	# 线性累积 ≤ 100：热打 200 锤后封顶
	var blade_many := _make_blade(1100.0)

	for i: int in 200:
		ForgeSim.strike(blade_many, 3, 0, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)

	assert_float(blade_many.sections[3].stress).is_greater_equal(100.0 - 1e-6)
	assert_float(blade_many.sections[3].stress).is_less_equal(100.0)


func test_side_strike_only_changes_offset() -> void:
	# ⑦ 侧面打：仅改 offset_y（±strike_k·power·m·side_ratio），宽 / 厚 / 应力不变
	var blade := _make_blade(1100.0)
	var seg := 8
	var sec := blade.sections[seg]

	var width_before: float = sec.width
	var thickness_before: float = sec.thickness

	var result_left := ForgeSim.strike(blade, seg, 1, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)
	var expect_offset: float = _cfg.strike_k * _hammer_forge.power * 1.0 * _cfg.side_ratio

	assert_float(result_left.d_thickness).is_equal(0.0)
	assert_float(sec.offset_y).is_equal_approx(expect_offset, 1e-6)
	assert_float(sec.width).is_equal(width_before)
	assert_float(sec.thickness).is_equal(thickness_before)
	assert_float(sec.stress).is_equal(0.0)

	ForgeSim.strike(blade, seg, 2, _hammer_forge, _cfg, _cfg_m0.anvil_face_width)
	assert_float(sec.offset_y).is_equal_approx(0.0, 1e-6)

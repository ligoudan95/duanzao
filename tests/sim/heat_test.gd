## HeatSim 热传导 / 散热 / 炉口加热用例（含守恒律与确定性）。
extends GdUnitTestSuite

var _cfg: SimCfg
var _cfg_m0: M0Cfg
var _steel: SteelDef
var _forge: ForgeDef


func before_test() -> void:
	_cfg = load("res://data/cfg/cfg_sim.tres") as SimCfg
	_cfg_m0 = load("res://data/cfg/cfg_m0.tres") as M0Cfg
	_steel = load("res://data/steels/steel_1084.tres") as SteelDef
	_forge = load("res://data/props/prop_forge_coal.tres") as ForgeDef


## 构建指定温度 / 厚度的均匀刀坯
func _make_blade(temp: float, thickness: float = 8.0) -> BladeData:
	var blade := BladeData.create_bar("steel_1084", _cfg_m0)

	for sec: BladeData.SectionData in blade.sections:
		sec.temp = temp
		sec.thickness = thickness

	return blade


## 构建指定散热系数的钢材（beta_base=0 用于隔离散热项）
func _make_steel(beta_base: float, alpha: float) -> SteelDef:
	var steel := SteelDef.new()
	steel.id = "steel_1084"
	steel.display_name = "1084"
	steel.alpha = alpha
	steel.beta_base = beta_base
	steel.th_ref = _steel.th_ref
	return steel


## 构建 ForgeState（参考体积按初始坯料段体积）
func _make_state(blade: BladeData) -> HeatSim.ForgeState:
	var state := HeatSim.ForgeState.new()
	state.flux_factor = 1.0
	state.timer = 0.0
	state.ref_volume = blade.ref_volume(_cfg_m0)
	return state


## 推进指定 tick 数并返回温度快照
func _run(blade: BladeData, steel: SteelDef, state: HeatSim.ForgeState,
		coverage: Array[float], seed: int, ticks: int) -> Array[float]:
	var rng := SimRng.new()
	rng.setup(seed)

	for i: int in ticks:
		HeatSim.tick(blade, steel, _cfg, _forge, state, coverage, rng)

	var temps: Array[float] = []
	for sec: BladeData.SectionData in blade.sections:
		temps.append(sec.temp)
	return temps


func _zero_coverage() -> Array[float]:
	var coverage: Array[float] = []
	coverage.resize(_cfg_m0.segment_count)
	coverage.fill(0.0)
	return coverage


func test_uniform_field_no_cooling_no_coverage_unchanged() -> void:
	# ① 均匀场 + β=0 + coverage=0：温度不变
	var blade := _make_blade(850.0)
	var steel := _make_steel(0.0, _steel.alpha)
	var state := _make_state(blade)

	var temps := _run(blade, steel, state, _zero_coverage(), 1, 50)

	for t: float in temps:
		assert_float(t).is_equal(850.0)


func test_nonuniform_field_conduction_conserves_sum() -> void:
	# ② 非均匀场 β=0 绝热端：ΣT 守恒（传导只在段间搬运热量）
	var blade := _make_blade(850.0)

	for i: int in blade.sections.size():
		blade.sections[i].temp = 500.0 if i % 2 == 0 else 900.0

	var steel := _make_steel(0.0, _steel.alpha)
	var state := _make_state(blade)

	var sum_before: float = 0.0
	for sec: BladeData.SectionData in blade.sections:
		sum_before += sec.temp

	var temps := _run(blade, steel, state, _zero_coverage(), 1, 50)

	var sum_after: float = 0.0
	for t: float in temps:
		sum_after += t

	assert_float(sum_after).is_equal_approx(sum_before, 1e-6)


func test_cooling_monotone_decrease_and_floor() -> void:
	# ③ 纯冷却（coverage=0）：逐 tick 单调下降且 ≥ 环境温度
	var blade := _make_blade(900.0)
	var state := _make_state(blade)
	var rng := SimRng.new()
	rng.setup(1)

	var coverage := _zero_coverage()
	var mid_index: int = blade.sections.size() / 2
	var prev_temp: float = blade.sections[mid_index].temp

	for i: int in 100:
		HeatSim.tick(blade, _steel, _cfg, _forge, state, coverage, rng)
		var now_temp: float = blade.sections[mid_index].temp
		assert_float(now_temp).is_less(prev_temp)
		prev_temp = now_temp

	assert_float(prev_temp).is_greater_equal(_cfg.t_ambient)


func test_ends_cool_faster_than_middle() -> void:
	# ④ 端段散热倍率 1.6：100 tick 后端段 < 中段
	var blade := _make_blade(1000.0)
	var state := _make_state(blade)
	_run(blade, _steel, state, _zero_coverage(), 1, 100)

	var mid_index: int = blade.sections.size() / 2
	assert_float(blade.sections[0].temp).is_less(blade.sections[mid_index].temp)
	assert_float(blade.sections[blade.sections.size() - 1].temp).is_less(blade.sections[mid_index].temp)


func test_coverage_heats_segment_and_neighbors() -> void:
	# ⑤ 炉口覆盖中段：覆盖段显著升温，200 tick 后邻段也升高（传导）
	var blade := _make_blade(850.0)
	var steel := _make_steel(0.0, _steel.alpha)
	var state := _make_state(blade)

	var coverage := _zero_coverage()
	coverage[7] = 1.0
	coverage[8] = 1.0

	_run(blade, steel, state, coverage, 1, 200)

	assert_float(blade.sections[7].temp).is_greater(950.0)
	assert_float(blade.sections[9].temp).is_greater(851.0)


func test_thinner_segment_heats_faster() -> void:
	# ⑥ 体积比加热：厚度减半的段升温更快
	var blade := _make_blade(850.0)
	blade.sections[3].thickness = 4.0
	var steel := _make_steel(0.0, 0.0)
	var state := _make_state(blade)

	var coverage := _zero_coverage()
	coverage[3] = 1.0
	coverage[5] = 1.0

	_run(blade, steel, state, coverage, 1, 10)

	assert_float(blade.sections[3].temp).is_greater(blade.sections[5].temp)


func test_same_seed_bit_exact_and_different_seed_differs() -> void:
	# ⑦ 同 seed 两次 1000 tick 逐值 bit-exact；异 seed 在瞬态（tick 50）出现差异
	var run_a := _run_coverage_scenario(20261015, 1000)
	var run_b := _run_coverage_scenario(20261015, 1000)
	var run_c := _run_coverage_scenario(20261016, 50)
	var run_d := _run_coverage_scenario(20261015, 50)

	for i: int in run_a.size():
		assert_float(run_a[i]).is_equal(run_b[i])

	var has_difference := false
	for i: int in run_c.size():
		if not is_equal_approx(run_c[i], run_d[i]):
			has_difference = true
			break

	assert_bool(has_difference).is_true()


## 带 coverage 的场景（flux 波动参与，随机序列影响结果）
func _run_coverage_scenario(seed_val: int, ticks: int) -> Array[float]:
	var blade := _make_blade(850.0)
	var state := _make_state(blade)
	var coverage := _zero_coverage()
	coverage[7] = 1.0
	coverage[8] = 1.0

	return _run(blade, _steel, state, coverage, seed_val, ticks)

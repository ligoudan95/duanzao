## BladeData.create_bar 初始坯料用例。
extends GdUnitTestSuite

var _cfg_m0: M0Cfg


func before_test() -> void:
	_cfg_m0 = load("res://data/cfg/cfg_m0.tres") as M0Cfg


func test_create_bar_segment_count() -> void:
	var blade := BladeData.create_bar("steel_1084", _cfg_m0)
	assert_int(blade.sections.size()).is_equal(_cfg_m0.segment_count)


func test_create_bar_uniform_dimensions() -> void:
	var blade := BladeData.create_bar("steel_1084", _cfg_m0)

	for sec: BladeData.SectionData in blade.sections:
		assert_float(sec.width).is_equal(_cfg_m0.blank_width)
		assert_float(sec.thickness).is_equal(_cfg_m0.blank_thickness)


func test_create_bar_section_positions() -> void:
	var blade := BladeData.create_bar("steel_1084", _cfg_m0)
	var seg_len: float = _cfg_m0.blank_length / float(_cfg_m0.segment_count)

	for i: int in blade.sections.size():
		var expect_x: float = (float(i) + 0.5) * seg_len
		assert_float(blade.sections[i].x).is_equal_approx(expect_x, 1e-6)

	assert_float(blade.segment_length).is_equal(seg_len)


func test_create_bar_initial_state() -> void:
	var blade := BladeData.create_bar("steel_1084", _cfg_m0)

	assert_str(blade.steel_id).is_equal("steel_1084")

	for sec: BladeData.SectionData in blade.sections:
		assert_float(sec.temp).is_equal(_cfg_m0.initial_temp)
		assert_float(sec.stress).is_equal(0.0)
		assert_float(sec.offset_y).is_equal(0.0)


func test_create_bar_total_volume() -> void:
	var blade := BladeData.create_bar("steel_1084", _cfg_m0)

	var total: float = 0.0
	for i: int in blade.sections.size():
		total += blade.volume_at(i)

	var expect: float = _cfg_m0.blank_length * _cfg_m0.blank_width * _cfg_m0.blank_thickness
	assert_float(total).is_equal_approx(expect, 1e-4)

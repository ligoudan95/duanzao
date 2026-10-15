## SimRng 确定性随机源用例。
extends GdUnitTestSuite


func test_same_seed_produces_identical_sequence() -> void:
	var rng_a := SimRng.new()
	rng_a.setup(20261015)

	var rng_b := SimRng.new()
	rng_b.setup(20261015)

	for i: int in 1000:
		var a: float = rng_a.randf_range(-5.0, 5.0)
		var b: float = rng_b.randf_range(-5.0, 5.0)
		assert_float(a).is_equal(b)


func test_different_seed_produces_different_sequence() -> void:
	var rng_a := SimRng.new()
	rng_a.setup(20261015)

	var rng_b := SimRng.new()
	rng_b.setup(20261016)

	var has_difference := false

	for i: int in 100:
		if not is_equal_approx(rng_a.randf_range(-5.0, 5.0), rng_b.randf_range(-5.0, 5.0)):
			has_difference = true
			break

	assert_bool(has_difference).is_true()


func test_randf_range_stays_in_bounds() -> void:
	var rng := SimRng.new()
	rng.setup(42)

	for i: int in 10000:
		var value: float = rng.randf_range(-3.5, 7.25)
		assert_float(value).is_greater_equal(-3.5)
		assert_float(value).is_less(7.25)


func test_chance_stays_probabilistic_bounds() -> void:
	var rng := SimRng.new()
	rng.setup(7)

	var true_count: int = 0

	for i: int in 10000:
		if rng.chance(0.25):
			true_count += 1

	# 10000 次伯努利(0.25)：期望 2500，99.9% 置信区间约 ±80
	assert_int(true_count).is_between(2300, 2700)

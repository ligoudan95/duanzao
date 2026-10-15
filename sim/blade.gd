## 刀坯数据：模拟层核心状态载体（纯 RefCounted，零 Node 依赖）。
## SectionData 为单段截面；BladeData 为整坯（N 段）。
class_name BladeData
extends RefCounted


## 单段截面状态。M0 裁掉 bevel/grain/carbon/hardness/soak/hairline/burned（M1+ 回归）。
class SectionData extends RefCounted:
	## 段中心弧长（mm，0 起点沿刀身）
	var x: float = 0.0
	## 段宽度（mm）
	var width: float = 0.0
	## 段厚度（mm）
	var thickness: float = 0.0
	## 截面中心垂直偏移（mm，侧面打击产生）
	var offset_y: float = 0.0
	## 段温度（°C）
	var temp: float = 20.0
	## 段应力（0~100）
	var stress: float = 0.0


## 钢材 id（steel_ 前缀，表内只存 id）
var steel_id: String = ""
## 单段弧长（mm）
var segment_length: float = 0.0
## 截面段列表（长度 = segment_count）
var sections: Array[SectionData] = []


## 按初始坯料参数创建等宽等厚直刀坯：N 段均匀分布、温度 = 初始温度、应力清零。
## [param steel_id] 钢材记录 id
## [param cfg_m0] M0 参数表（坯料尺寸 / 段数 / 初始温度）
static func create_bar(bar_steel_id: String, cfg_m0: M0Cfg) -> BladeData:
	var blade := BladeData.new()
	blade.steel_id = bar_steel_id
	blade.segment_length = cfg_m0.blank_length / float(cfg_m0.segment_count)

	for i: int in cfg_m0.segment_count:
		var sec := SectionData.new()
		sec.x = (float(i) + 0.5) * blade.segment_length
		sec.width = cfg_m0.blank_width
		sec.thickness = cfg_m0.blank_thickness
		sec.temp = cfg_m0.initial_temp
		sec.stress = 0.0
		blade.sections.append(sec)

	return blade


## 单段体积（mm³）：宽 × 厚 × 段长。
func volume_at(index: int) -> float:
	var sec := sections[index]
	return sec.width * sec.thickness * segment_length


## 初始单段体积（按 M0 坯料尺寸），作为加热项的参考体积。
func ref_volume(cfg_m0: M0Cfg) -> float:
	return cfg_m0.blank_width * cfg_m0.blank_thickness * (cfg_m0.blank_length / float(cfg_m0.segment_count))

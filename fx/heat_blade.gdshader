// 刀坯火色 shader：顶点色 R = 归一化温度（LUT 火色），G = 锻打氧化皮量（按段累计形变映射）。
// 冷态 = 亮银灰钢条；未锻热段 = 亮火色自发光；锻过段 = emissive 归零 + 深哑光铁灰/暗褐
//（"锤一下黑一块"的节奏感，关 HUD 也能读出锻打区）。
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D heat_lut : source_color, filter_linear, repeat_disable;
uniform vec3 steel_albedo : source_color = vec3(0.6, 0.6, 0.64);
uniform float steel_metallic : hint_range(0.0, 1.0) = 0.9;
uniform float steel_roughness : hint_range(0.0, 1.0) = 0.4;
uniform float emission_strength : hint_range(0.0, 16.0) = 3.0;
uniform vec3 oxide_albedo : source_color = vec3(0.13, 0.105, 0.09);

void fragment() {
	float heat_ratio = clamp(COLOR.r, 0.0, 1.0);
	float oxide = clamp(COLOR.g, 0.0, 1.0);
	vec3 heat = texture(heat_lut, vec2(heat_ratio, 0.5)).rgb;

	// 锻过段：emissive 直接归零（一锤即大幅压暗，两锤以上无火光）
	float glow_alive = clamp(1.0 - oxide * 2.0, 0.0, 1.0);
	float oxide_skin = clamp(oxide * 1.4, 0.0, 1.0);

	// 冷态银灰 → 氧化暗褐；热态火色 → 氧化哑光铁灰（vs 未锻段亮橙强对比）
	vec3 cold_base = mix(steel_albedo, oxide_albedo, oxide_skin);
	vec3 hot_base = mix(heat, oxide_albedo, oxide_skin);

	ALBEDO = mix(cold_base, hot_base, clamp(heat_ratio * 1.6, 0.0, 1.0));
	METALLIC = steel_metallic * (1.0 - heat_ratio) * (1.0 - oxide_skin * 0.8);
	ROUGHNESS = mix(mix(steel_roughness, 0.95, oxide_skin), 0.75, heat_ratio);
	EMISSION = heat * glow_alive * emission_strength;
	SPECULAR = 0.5;
}

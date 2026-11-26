shader_type canvas_item;

// Dims everything except a rounded rectangle (the "spotlight"), with a soft glowing edge.
// Used by the tutorial to point at what it is talking about.

// Spotlight rectangles in the node's local pixels: x, y, width, height. Zero size = no hole.
uniform vec4 hole_rect = vec4(0.0);
uniform vec4 hole_rect_2 = vec4(0.0);
uniform float corner_radius = 24.0;
uniform float feather = 10.0;
uniform vec4 dim_color : source_color = vec4(0.0, 0.0, 0.0, 0.6);
uniform vec4 glow_color : source_color = vec4(0.86, 0.66, 0.92, 0.9);
uniform float glow_width = 3.0;

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

// Signed distance to a rounded rectangle: negative inside, positive outside
float rounded_rect_distance(vec2 point, vec2 center, vec2 half_size, float radius) {
	vec2 q = abs(point - center) - half_size + vec2(radius);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Distance from a point to a spotlight rectangle; very far when the rectangle is empty
float hole_distance(vec2 point, vec4 rect) {
	if (rect.z <= 0.0 || rect.w <= 0.0) {
		return 1e6;
	}
	vec2 half_size = rect.zw * 0.5;
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	return rounded_rect_distance(point, rect.xy + half_size, half_size, radius);
}

void fragment() {
	float d = min(hole_distance(local_position, hole_rect), hole_distance(local_position, hole_rect_2));
	float dim = smoothstep(0.0, feather, d);
	float glow = (1.0 - smoothstep(0.0, glow_width, abs(d - glow_width))) * glow_color.a;
	vec4 dimmed = vec4(dim_color.rgb, dim_color.a * dim);
	COLOR = mix(dimmed, vec4(glow_color.rgb, 1.0), glow);
}

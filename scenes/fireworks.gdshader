shader_type canvas_item;

// Basic settings
uniform vec2 resolution = vec2(600.0, 400.0);
uniform float quality: hint_range(0.0, 1.0, 0.1) = 1.0; // Quality multiplier (lower for mobile)
uniform float size: hint_range(1.0, 10.0, 0.1) = 2.0;
uniform float sharpen: hint_range(1.0, 10.0, 0.1) = 1.5;
uniform float speed: hint_range(1.0, 10.0, 0.1) = 2.0;
uniform float gravity: hint_range(0.1, 2.0, 0.1) = 0.9;
uniform float lifetime: hint_range(1.0, 10.0, 0.1) = 7.0;

// Derived settings - dynamically scaled based on quality
const float MAX_FIREWORK_COUNT = 10.0;
const float MAX_PARTICLE_COUNT = 30.0;

// Simple but effective pseudo-random function (cheaper than sin)
vec2 fast_noise(vec2 uv) {
    uv = fract(uv * vec2(233.34, 851.73));
    uv += dot(uv, uv + 23.45);
    return fract(vec2(uv.x * uv.y * 896.34, uv.y * uv.x * 269.91)) * 0.5;
}

vec3 spark(vec2 uv, vec2 position, float index, float cycle) {
    vec2 direction = fast_noise(vec2(0.1, 0.3) * index);
    if (mod(index, 2.0) == 0.0) {
        direction.x = -direction.x;
    }
    direction.y -= cycle * gravity * 0.1;

    // Optimized distance calculation
    float dist = length(uv + position + direction * cycle);
    // Early exit if too far away (optimization)
    if (dist > 0.4) return vec3(0.0);

    float shape = 1.0 / dist * size * 0.01;
    vec2 noise_val = fast_noise(vec2(0.3, 0.4) * index);
    return pow(vec3(
        shape * noise_val.x,
        shape * noise_val.y,
        shape * fast_noise(vec2(0.5, 0.6) * index).x
    ), vec3(sharpen));
}

vec3 firework(vec2 uv, float index) {
    vec3 color = vec3(0.0);
    vec2 position = fast_noise(vec2(0.2, 0.4) * index);
    if (mod(index, 2.0) == 0.0) {
        position.x = -position.x;
    }

    float cycle = mod(TIME * speed, lifetime * (1.0 + fast_noise(vec2(0.1, 0.9) * index).x));

    // Calculate actual particle count based on quality
    float actual_particle_count = max(5.0, floor(MAX_PARTICLE_COUNT * quality));

    // Simplified loop with early exit to avoid expensive calculations
    for (float i = 1.0; i <= actual_particle_count; i += 1.0) {
        color += spark(uv, position, i, cycle);
    }
    return color;
}

void fragment() {
    vec2 uv = UV - 0.5;
    uv.x *= resolution.x / resolution.y;
    vec3 color = vec3(0.0);

    // Calculate actual firework count based on quality
    float actual_firework_count = max(3.0, floor(MAX_FIREWORK_COUNT * quality));

    for (float i = 0.0; i < actual_firework_count; i += 1.0) {
        color += firework(uv, i);
    }

    COLOR = vec4(color, 1.0);
}
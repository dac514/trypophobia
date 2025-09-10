shader_type canvas_item;

// Basic settings
uniform vec2 resolution = vec2(600.0, 400.0);
uniform float quality: hint_range(0.0, 1.0, 0.1) = 1.0; // Quality multiplier (lower for mobile)
uniform float size: hint_range(1.0, 10.0, 0.1) = 2.0;
uniform float sharpen: hint_range(1.0, 10.0, 0.1) = 1.5;
uniform float speed: hint_range(1.0, 10.0, 0.1) = 2.0;
uniform float gravity: hint_range(0.1, 2.0, 0.1) = 0.9;
uniform float lifetime: hint_range(1.0, 10.0, 0.1) = 7.0;

// Desired desktop settings dynamically scaled down based on quality
const float MAX_FIREWORK_COUNT = 10.0;
const float MAX_PARTICLE_COUNT = 30.0;

// Optimized noise function with fewer operations
vec2 fast_noise(vec2 uv) {
    uv = fract(uv * vec2(233.34, 851.73));
    uv += dot(uv, uv + 23.45);
    vec2 result = uv * vec2(896.34, 269.91);
    return fract(result) * 0.5;
}

vec3 spark(vec2 uv, vec2 position, float index, float cycle) {
    vec2 direction = fast_noise(vec2(0.1, 0.3) * index);
    if (mod(index, 2.0) == 0.0) {
        direction.x = -direction.x;
    }
    direction.y -= cycle * gravity * 0.1;

    float dist = length(uv + position + direction * cycle);
    if (dist > 0.4) return vec3(0.0); // Early exit if too far away

    float shape = 1.0 / dist * size * 0.01;
    vec2 noise_val = fast_noise(vec2(0.3, 0.4) * index);
    return pow(vec3(
        shape * noise_val.x,
        shape * noise_val.y,
        shape * fast_noise(vec2(0.5, 0.6) * index).x
    ), vec3(sharpen));
}

vec3 firework(vec2 uv, float index) {
    // Early exit if pixel is too far from potential firework center
    vec2 position = fast_noise(vec2(0.2, 0.4) * index);
    if (floor(mod(index, 2.0)) == 0.0) {
        position.x = -position.x;
    }

    // Rough distance check to firework center
    float center_dist = dot(uv + position, uv + position);
    if (center_dist > 2.0) return vec3(0.0); // Skip if too far from any possible particles

    float cycle = mod(TIME * speed, lifetime * (1.0 + fast_noise(vec2(0.1, 0.9) * index).x));

    vec3 color = vec3(0.0);

    // Calculate actual particle count based on quality with minimum threshold
    float actual_particle_count = max(3.0, floor(MAX_PARTICLE_COUNT * quality));

    // Optimized loop with step size based on quality
    float step_size = 1.0 + (1.0 - quality) * 2.0; // Larger steps for lower quality
    for (float i = 1.0; i <= actual_particle_count; i += step_size) {
        color += spark(uv, position, i, cycle);

        // Early exit if color is already saturated
        if (color.r > 3.0 || color.g > 3.0 || color.b > 3.0) break;
    }
    return color;
}

void fragment() {
    vec2 uv = UV - 0.5;
    uv.x *= resolution.x / resolution.y;

    vec3 color = vec3(0.0);

    // Check if we're not at edge pixels before processing
    if (!(abs(uv.x) > 1.0 || abs(uv.y) > 0.8)) {
        // Calculate actual firework count based on quality
        float actual_firework_count = max(2.0, floor(MAX_FIREWORK_COUNT * quality));

        for (float i = 0.0; i < actual_firework_count; i += 1.0) {
            color += firework(uv, i);

            // Early exit if color is saturated
            if (dot(color, color) > 9.0) break;
        }

        // Clamp to prevent over-bright values
        color = min(color, vec3(1.0));
    }

    COLOR = vec4(color, 1.0);
}
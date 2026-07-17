/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Pixel-sort approximation: luma-driven horizontal smears on hashed rows, with an accent-colored edge lift. Density/Span shapes how many rows smear and how far.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Glitch", "Stylize"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0.0, "MAX": 1.0},
    {"NAME": "knob", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Density / Span"},
    {"NAME": "boost", "TYPE": "bool", "DEFAULT": false, "LABEL": "Boost"},
    {"NAME": "accentColor", "TYPE": "color", "DEFAULT": [1.0, 0.0, 0.235, 1.0]}
  ]
}*/

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
vec2 safeUv(vec2 uv) { return clamp(uv, vec2(0.001), vec2(0.999)); }

vec3 sampleSort(vec2 uv, float amt, float k, float button) {
    vec2 px = 1.0 / RENDERSIZE;
    vec3 base = IMG_NORM_PIXEL(inputImage, uv).rgb;
    float rowHash = hash(vec2(floor(uv.y * RENDERSIZE.y * mix(0.12, 0.55, k)),
                              floor(TIME * (3.0 + button * 12.0))));
    float density = mix(0.18, 0.72, k) + button * 0.25;
    if (rowHash > density) return base;
    float l = dot(base, vec3(0.299, 0.587, 0.114));
    float span = mix(8.0, 96.0, amt * (0.45 + k * 0.75 + button * 0.55));
    float dir = 1.0;
    if (rowHash <= 0.5) dir = -1.0;
    vec2 offset = vec2(dir * span * px.x * smoothstep(0.12, 0.96, l), 0.0);
    vec3 a = IMG_NORM_PIXEL(inputImage, safeUv(uv + offset)).rgb;
    vec3 b = IMG_NORM_PIXEL(inputImage, safeUv(uv - offset * 0.45)).rgb;
    float edge = abs(l - dot(a, vec3(0.299, 0.587, 0.114)));
    vec3 sorted = mix(min(a, b), max(a, b), step(0.5, fract(k * 2.0 + rowHash)));
    return mix(base, sorted + edge * accentColor.rgb * (0.25 + button), amt * (0.55 + edge * 1.4));
}

void main() {
    float button = 0.0;
    if (boost) button = 1.0;
    vec2 uv = isf_FragNormCoord;
    float alpha = IMG_NORM_PIXEL(inputImage, uv).a;
    gl_FragColor = vec4(sampleSort(uv, amount, knob, button), alpha);
}

/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Ordered Bayer dither blended with animated noise, luma two-tone at high strength, and an edge-aware accent lift. Knob trades cell size against quantization depth.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Stylize", "Retro"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0.0, "MAX": 1.0},
    {"NAME": "knob", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Cell / Depth"},
    {"NAME": "boost", "TYPE": "bool", "DEFAULT": false, "LABEL": "Boost"},
    {"NAME": "accentColor", "TYPE": "color", "DEFAULT": [1.0, 0.0, 0.235, 1.0]}
  ]
}*/

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }

float bayer4(vec2 p) {
    vec2 q = mod(floor(p), 4.0);
    float x = q.x;
    float y = q.y;
    float v = 0.0;
    if (y < 0.5) {
        if (x < 0.5) v = 0.0;
        else if (x < 1.5) v = 8.0;
        else if (x < 2.5) v = 2.0;
        else v = 10.0;
    } else if (y < 1.5) {
        if (x < 0.5) v = 12.0;
        else if (x < 1.5) v = 4.0;
        else if (x < 2.5) v = 14.0;
        else v = 6.0;
    } else if (y < 2.5) {
        if (x < 0.5) v = 3.0;
        else if (x < 1.5) v = 11.0;
        else if (x < 2.5) v = 1.0;
        else v = 9.0;
    } else {
        if (x < 0.5) v = 15.0;
        else if (x < 1.5) v = 7.0;
        else if (x < 2.5) v = 13.0;
        else v = 5.0;
    }
    return (v + 0.5) / 16.0;
}

vec3 applyDither(vec3 color, vec2 uv, float amt, float k, float button) {
    vec3 accent = accentColor.rgb;
    float cell = mix(0.75, 5.5, amt * (0.45 + k * 0.9 + button * 0.45));
    vec2 grid = floor(uv * RENDERSIZE / cell);
    float ordered = bayer4(grid);
    float blueish = hash(grid + vec2(TIME * 13.0, TIME * 7.0));
    float threshold = mix(ordered, blueish, 0.12 + k * 0.45 + button * 0.3);
    float levels = mix(48.0, 2.5, amt * (0.5 + k * 0.8 + button * 0.45));
    vec3 shifted = color + (threshold - 0.5) / levels * (1.0 + amt * (1.0 + k * 3.0 + button * 2.0));
    vec3 quant = floor(clamp(shifted, 0.0, 1.0) * levels) / max(levels - 1.0, 1.0);
    float luma = dot(color, vec3(0.299, 0.587, 0.114));
    float mono = step(threshold, luma);
    vec3 twoTone = mix(accent * 0.18, mix(vec3(1.0), accent, 0.35), mono);
    float neighborX = dot(IMG_NORM_PIXEL(inputImage, uv + vec2(1.0 / RENDERSIZE.x, 0.0)).rgb,
                          vec3(0.299, 0.587, 0.114));
    float neighborY = dot(IMG_NORM_PIXEL(inputImage, uv + vec2(0.0, 1.0 / RENDERSIZE.y)).rgb,
                          vec3(0.299, 0.587, 0.114));
    float edge = min(abs(luma - neighborX) + abs(luma - neighborY), 1.0);
    vec3 edged = mix(quant, twoTone, smoothstep(0.08, 0.8, amt) * (0.35 + edge * 1.2));
    return mix(color, edged, amt);
}

void main() {
    float button = 0.0;
    if (boost) button = 1.0;
    vec2 uv = isf_FragNormCoord;
    vec4 base = IMG_NORM_PIXEL(inputImage, uv);
    vec3 color = base.rgb;
    if (amount > 0.001) color = applyDither(color, uv, amount, knob, button);
    gl_FragColor = vec4(color, base.a);
}

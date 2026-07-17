/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "24 mirror and kaleidoscope systems on one preset knob — half-frame mirrors, diagonal folds, 4/6/8/10-segment kaleidoscopes, radial folds, and grids. Glitch adds animated slice displacement.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Stylize"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "preset", "TYPE": "float", "DEFAULT": 0.55, "MIN": 0.0, "MAX": 1.0, "LABEL": "Preset (24 systems)"},
    {"NAME": "glitch", "TYPE": "bool", "DEFAULT": false, "LABEL": "Glitch Slices"}
  ]
}*/

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float mirrorFold(float v) { return 1.0 - abs(fract(v) * 2.0 - 1.0); }
// Half-frame mirror preserves source scale: v < 0.5 ? v : 1.0 - v, branch-free.
float halfMirror(float v) { return min(v, 1.0 - v); }
vec2 safeUv(vec2 uv) { return clamp(uv, vec2(0.001), vec2(0.999)); }

vec2 kaleido(float a, float r, float seg, float aspect) {
    float aa = abs(mod(a + 3.14159265 / seg, 6.2831853 / seg) - 3.14159265 / seg);
    vec2 q = vec2(cos(aa), sin(aa)) * r;
    q.x /= aspect;
    return q + 0.5;
}

vec2 mirrorUvPreset(vec2 uv, float presetK, float button) {
    vec2 c = uv - 0.5;
    float aspect = RENDERSIZE.x / max(RENDERSIZE.y, 1.0);
    c.x *= aspect;
    float a = atan(c.y, c.x);
    float r = length(c);
    vec2 outUv = uv;
    float p = floor(presetK * 23.999);
    float drift = button * 0.06 * sin(TIME * 9.0 + floor(uv.y * 12.0));

    if (p < 0.5) outUv.x = halfMirror(uv.x + drift);
    else if (p < 1.5) outUv.y = halfMirror(uv.y + drift);
    else if (p < 2.5) outUv = vec2(halfMirror(uv.x), halfMirror(uv.y));
    else if (p < 3.5) {
        if (uv.x > uv.y) outUv = vec2(uv.y, uv.x);
        else outUv = uv;
    }
    else if (p < 4.5) {
        if (uv.x + uv.y > 1.0) outUv = vec2(1.0 - uv.y, 1.0 - uv.x);
        else outUv = uv;
    }
    else if (p < 5.5) outUv = vec2(halfMirror(fract(uv.x * 2.0)) * 0.5, uv.y);
    else if (p < 6.5) outUv = vec2(uv.x, halfMirror(fract(uv.y * 2.0)) * 0.5);
    else if (p < 7.5) outUv = vec2(halfMirror(fract(uv.x * 2.0)) * 0.5, halfMirror(fract(uv.y * 2.0)) * 0.5);
    else if (p < 8.5) outUv = vec2(halfMirror(fract(uv.x * 2.0 + drift)) * 0.5, uv.y);
    else if (p < 9.5) outUv = vec2(uv.x, halfMirror(fract(uv.y * 2.0 + drift)) * 0.5);
    else if (p < 10.5) outUv = vec2(halfMirror(fract(uv.x * 2.0)) * 0.5, halfMirror(uv.y));
    else if (p < 11.5) outUv = vec2(halfMirror(uv.x), halfMirror(fract(uv.y * 2.0)) * 0.5);
    else if (p < 12.5) outUv = kaleido(a, r, 4.0, aspect);
    else if (p < 13.5) outUv = kaleido(a, r, 6.0, aspect);
    else if (p < 14.5) outUv = kaleido(a, r, 8.0, aspect);
    else if (p < 15.5) outUv = kaleido(a, r, 10.0, aspect);
    else if (p < 16.5) outUv = vec2(halfMirror(fract((uv.x + uv.y) * 1.0)) * 0.7,
                                    halfMirror(fract((uv.x - uv.y) * 1.0)) * 0.7 + 0.15);
    else if (p < 17.5) outUv = vec2(halfMirror(fract((uv.x + uv.y) * 1.35 + drift)) * 0.65,
                                    halfMirror(fract((uv.x - uv.y) * 1.35)) * 0.65 + 0.17);
    else if (p < 18.5) outUv = vec2(halfMirror(fract(uv.x * 2.0 + floor(uv.y * 2.0) * 0.5)) * 0.5,
                                    halfMirror(fract(uv.y * 2.0)) * 0.5);
    else if (p < 19.5) outUv = vec2(halfMirror(fract(uv.x * 3.0)) * 0.5,
                                    halfMirror(fract(uv.y * 2.0 + floor(uv.x * 3.0) * 0.5)) * 0.5);
    else if (p < 20.5) {
        float rr = mirrorFold(r * 2.4 + button * sin(TIME * 2.0) * 0.22);
        vec2 q = vec2(cos(a), sin(a)) * rr * 0.55;
        q.x /= aspect;
        outUv = q + 0.5;
    }
    else if (p < 21.5) {
        float aa = mirrorFold((a / 6.2831853) * 7.0 + drift) * 6.2831853;
        vec2 q = vec2(cos(aa), sin(aa)) * mirrorFold(r * 2.1) * 0.55;
        q.x /= aspect;
        outUv = q + 0.5;
    }
    else if (p < 22.5) {
        vec2 grid = floor(uv * 3.0);
        outUv = vec2(halfMirror(fract(uv.x * 3.0 + mod(grid.y, 2.0) * 0.5)) * 0.55,
                     halfMirror(fract(uv.y * 3.0 + mod(grid.x, 2.0) * 0.5)) * 0.55);
    }
    else {
        vec2 grid = floor(uv * 4.0);
        float h = hash(grid + floor(TIME * (1.2 + button * 7.0)));
        outUv = vec2(halfMirror(fract(uv.x * (2.0 + floor(h * 3.0)))) * 0.6,
                     halfMirror(fract(uv.y * (2.0 + floor(h * 3.0)))) * 0.6);
    }

    if (button > 0.001) {
        float slice = floor(uv.y * mix(4.0, 28.0, presetK));
        outUv.x += (hash(vec2(slice, floor(TIME * 12.0))) - 0.5) * button * 0.08;
    }
    return safeUv(outUv);
}

void main() {
    float button = 0.0;
    if (glitch) button = 1.0;
    // Coordinates are remapped, never interpolated: halfway coordinate blends collapse the
    // image toward the mirror seam (the null_signal lesson baked into the source comment).
    gl_FragColor = IMG_NORM_PIXEL(inputImage, mirrorUvPreset(isf_FragNormCoord, preset, button));
}

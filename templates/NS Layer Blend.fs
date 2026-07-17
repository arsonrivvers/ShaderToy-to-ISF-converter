/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Blend a second layer over the input: 13 blend modes with alpha-weighted opacity. Blend math written for cross-GPU consistency (dodge/burn divide guards included).",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Blending"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "blendImage", "TYPE": "image", "LABEL": "Blend Layer"},
    {"NAME": "blendMode", "TYPE": "long", "LABEL": "Mode",
     "VALUES": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
     "LABELS": ["Add", "Screen", "Multiply", "Difference", "Normal", "Lighten", "Darken",
                "Exclusion", "Overlay", "Hard Light", "Soft Light", "Dodge", "Burn"],
     "DEFAULT": 4},
    {"NAME": "opacity", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.0, "MAX": 1.0}
  ]
}*/

vec3 blendScreen(vec3 b, vec3 s) { return 1.0 - (1.0 - b) * (1.0 - s); }
vec3 blendOverlay(vec3 b, vec3 s) {
    return mix(2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s), step(0.5, b));
}
vec3 blendHardLight(vec3 b, vec3 s) {
    return mix(2.0 * b * s, 1.0 - 2.0 * (1.0 - b) * (1.0 - s), step(0.5, s));
}
vec3 blendSoftLight(vec3 b, vec3 s) { return (1.0 - 2.0 * s) * b * b + 2.0 * s * b; }
vec3 blendDodge(vec3 b, vec3 s) { return min(b / max(vec3(0.001), 1.0 - s), 1.0); }
vec3 blendBurn(vec3 b, vec3 s) { return 1.0 - min((1.0 - b) / max(vec3(0.001), s), 1.0); }

vec3 applyBlend(vec3 b, vec3 s, int mode) {
    if (mode == 0) return min(b + s, 1.0);
    if (mode == 1) return blendScreen(b, s);
    if (mode == 2) return b * s;
    if (mode == 3) return abs(b - s);
    if (mode == 4) return s;
    if (mode == 5) return max(b, s);
    if (mode == 6) return min(b, s);
    if (mode == 7) return b + s - 2.0 * b * s;
    if (mode == 8) return blendOverlay(b, s);
    if (mode == 9) return blendHardLight(b, s);
    if (mode == 10) return blendSoftLight(b, s);
    if (mode == 11) return blendDodge(b, s);
    return blendBurn(b, s);
}

void main() {
    vec2 uv = isf_FragNormCoord;
    vec4 base = IMG_NORM_PIXEL(inputImage, uv);
    vec4 src = IMG_NORM_PIXEL(blendImage, uv);
    // Blend weight is source alpha x opacity: transparent blend-layer regions leave the
    // base untouched regardless of mode (the null_signal compositeOne formula).
    float a = clamp(src.a * opacity, 0.0, 1.0);
    vec3 blended = applyBlend(base.rgb, src.rgb, blendMode);
    gl_FragColor = vec4(mix(base.rgb, blended, a), base.a);
}

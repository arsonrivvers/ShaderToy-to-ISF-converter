/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Directional RGB channel separation: R/G/B sample along a radial or tangential axis with a scanline-modulated spread. Knob selects axis character and spread; Boost widens and speeds the scan.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Glitch", "Color Effect"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "amount", "TYPE": "float", "DEFAULT": 0.6, "MIN": 0.0, "MAX": 1.0},
    {"NAME": "knob", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Axis / Spread"},
    {"NAME": "boost", "TYPE": "bool", "DEFAULT": false, "LABEL": "Boost"}
  ]
}*/

vec2 safeUv(vec2 uv) { return clamp(uv, vec2(0.001), vec2(0.999)); }

vec3 sampleChromaLeak(vec2 uv, float amt, float k, float button) {
    vec2 centered = uv - 0.5;
    vec2 dir = normalize(centered + vec2(0.0001));
    float scan = sin(uv.y * RENDERSIZE.y * mix(0.018, 0.09, k) + TIME * (2.0 + button * 18.0));
    vec2 tangent = normalize(vec2(-dir.y, dir.x) + vec2(0.0001));
    vec2 axis = mix(dir, tangent, step(0.5, fract(k * 3.0)));
    float spread = amt * (1.5 + k * 26.0 + button * 18.0) / min(RENDERSIZE.x, RENDERSIZE.y);
    spread *= 0.65 + 0.35 * scan;
    float r = IMG_NORM_PIXEL(inputImage, safeUv(uv + axis * spread * 1.2)).r;
    float g = IMG_NORM_PIXEL(inputImage, safeUv(uv - axis * spread * 0.35)).g;
    float b = IMG_NORM_PIXEL(inputImage, safeUv(uv - axis * spread * 1.35)).b;
    return mix(IMG_NORM_PIXEL(inputImage, uv).rgb, vec3(r, g, b), amt);
}

void main() {
    float button = 0.0;
    if (boost) button = 1.0;
    vec2 uv = isf_FragNormCoord;
    float alpha = IMG_NORM_PIXEL(inputImage, uv).a;
    gl_FragColor = vec4(sampleChromaLeak(uv, amount, knob, button), alpha);
}

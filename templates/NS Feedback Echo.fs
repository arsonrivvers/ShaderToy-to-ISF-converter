/*{
  "ISFVSN": "2.0",
  "DESCRIPTION": "Classic video-feedback echo: last frame is zoomed, drifted, and rotated back under the live input. Persistence uses max() so bright trails survive dark input; the upper half of the drift knob adds a darkening wash so long echoes decay instead of saturating.",
  "CREDIT": "Adapted from null_signal by VJ CYBERPATROLUNIT (MIT)",
  "CATEGORIES": ["Filter", "Feedback"],
  "INPUTS": [
    {"NAME": "inputImage", "TYPE": "image"},
    {"NAME": "amount", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Feedback"},
    {"NAME": "knob", "TYPE": "float", "DEFAULT": 0.5, "MIN": 0.0, "MAX": 1.0, "LABEL": "Drift / Persist"},
    {"NAME": "boost", "TYPE": "bool", "DEFAULT": false, "LABEL": "Boost"},
    {"NAME": "resetBuffer", "TYPE": "event", "LABEL": "Reset"}
  ],
  "PASSES": [
    {"TARGET": "echoBuf", "PERSISTENT": true, "FLOAT": true},
    {}
  ]
}*/

vec4 accumulate(vec2 uv) {
    vec4 live = IMG_NORM_PIXEL(inputImage, uv);
    if (FRAMEINDEX < 2 || resetBuffer) return live;

    float button = 0.0;
    if (boost) button = 1.0;

    // drawClassicFeedback transform, normalized-UV domain (audio terms dropped).
    float zoom = 1.0 + amount * (0.018 + knob * 0.042 + button * 0.025);
    vec2 drift = vec2(sin(TIME * (0.36 + knob * 1.1)), cos(TIME * (0.42 + knob * 1.15)))
               * amount * (0.004 + knob * 0.014 + button * 0.014);
    float rot = sin(TIME * (0.24 + knob * 0.6)) * amount * (0.002 + knob * 0.012 + button * 0.01);

    // Inverse-map: sample where this pixel came from last frame.
    vec2 c = uv - 0.5;
    float cs = cos(-rot);
    float sn = sin(-rot);
    vec2 p = vec2(c.x * cs - c.y * sn, c.x * sn + c.y * cs) / zoom + 0.5 - drift;

    vec4 prev = vec4(0.0);
    if (p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0) {
        prev = IMG_NORM_PIXEL(echoBuf, p);
    }

    float persist = mix(0.46, 0.965, amount);
    // Upper-half knob: translucent darkening wash (the null_signal "SOMETHING" persistence
    // style) so long echo tails decay toward black instead of saturating.
    float washStyle = clamp((knob - 0.48) / 0.52, 0.0, 1.0);
    float wash = mix(0.27, 0.10, knob) * amount * washStyle;
    vec3 tail = prev.rgb * (1.0 - wash);

    // max() not mix(): trails must survive dark input regions.
    return vec4(max(tail * persist, live.rgb), 1.0);
}

void main() {
    if (PASSINDEX == 0) {
        gl_FragColor = accumulate(isf_FragNormCoord);
        return;
    }
    gl_FragColor = IMG_NORM_PIXEL(echoBuf, isf_FragNormCoord);
}

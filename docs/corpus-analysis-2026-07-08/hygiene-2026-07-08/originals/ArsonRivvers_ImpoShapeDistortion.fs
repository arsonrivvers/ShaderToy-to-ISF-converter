/*{
    "DESCRIPTION": "Combines wave propagation using a figure-eight knot with a torus pattern warp, introduces self-intersection through a feedback loop, and starts the effect from the center expanding outward.",
    "CREDIT": "Generated with help from OpenAI's ChatGPT",
    "ISFVSN": "2",
    "CATEGORIES": [
        "Distortion"
    ],
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "waveAmplitude",
            "TYPE": "float",
            "DEFAULT": 0.1,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "waveFrequency",
            "TYPE": "float",
            "DEFAULT": 2.0,
            "MIN": 0.1,
            "MAX": 10.0
        },
        {
            "NAME": "warpIntensity",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "torusRadius",
            "TYPE": "float",
            "DEFAULT": 0.3,
            "MIN": 0.1,
            "MAX": 1.0
        },
        {
            "NAME": "torusTubeRadius",
            "TYPE": "float",
            "DEFAULT": 0.1,
            "MIN": 0.01,
            "MAX": 0.5
        },
        {
            "NAME": "knotIntensity",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "torusIntensity",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "selfIntersectionIntensity",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": 0.0,
            "MAX": 1.0
        }
    ],
    "PERSISTENT_BUFFERS": [
        "feedbackBuffer"
    ],
    "PASSES": [
        {
            "TARGET": "feedbackBuffer"
        },
        {}
    ]
}*/
#define PI 3.141592654

float sinh(float x) {
    return (exp(x) - exp(-x)) * 0.5;
}

float cosh(float x) {
    return (exp(x) + exp(-x)) * 0.5;
}

mat2 rotate(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, s, -s, c);
}

vec3 rotate3D(vec3 p, float angleX, float angleY) {
    mat2 rotX = rotate(angleX);
    mat2 rotY = rotate(angleY);
    p.xz = rotY * p.xz;
    p.xy = rotX * p.xy;
    return p;
}

const int MAX_ITERATIONS = 20;

vec3 fractalKaleidoscope(vec3 p, int iterations, float symmetry, float time, float distortionMix, int shape) {
    for (int i = 0; i < MAX_ITERATIONS; ++i) {
        if (i >= iterations) break;

        p = mix(p, abs(p), distortionMix);
        float angle = PI / symmetry;

        if (shape == 1) {
            p.xy = mix(p.xy, rotate(angle) * p.xy, distortionMix);
            p.xz = mix(p.xz, rotate(angle) * p.xz, distortionMix);
            p = mix(p, rotate3D(p, 0.1 * sin(time * 0.5), 0.1 * cos(time * 0.5)), distortionMix);
            p = mix(p, 2.0 * p - 1.0, distortionMix);
        } else if (shape == 2) {
            p.xy = mix(p.xy, rotate(-angle) * p.xy, distortionMix);
            p.xz = mix(p.xz, rotate(angle * 0.5) * p.xz, distortionMix);
            p = mix(p, rotate3D(p, 0.1 * cos(time * 0.3), 0.1 * sin(time * 0.3)), distortionMix);
            p = mix(p, p * 1.5 - 0.5, distortionMix);
        } else if (shape == 3) {
            float radius = length(p.xy);
            float theta = atan(p.y, p.x) + angle * distortionMix;
            p.xy = radius * vec2(cos(theta), sin(theta));
            p = mix(p, p * cos(time * 0.2), distortionMix);
        } else if (shape == 4) {
            p.xy = mix(p.xy, rotate(angle + time * 0.2) * p.xy, distortionMix);
            p.xz = mix(p.xz, rotate(angle - time * 0.2) * p.xz, distortionMix);
            float scale = 1.2 + 0.2 * sin(time * 0.5);
            p = mix(p, p * scale - vec3(0.1), distortionMix);
        } else if (shape == 5) {
            p.xy = mix(p.xy, rotate(angle * sin(time * 0.5)) * p.xy, distortionMix);
            p.xz = mix(p.xz, rotate(angle * cos(time * 0.5)) * p.xz, distortionMix);
            p = mix(p, p * p - 1.0, distortionMix);
        } else if (shape == 6) {
            p = mix(p, p * p * p - 1.0, distortionMix);
            p.xy = mix(p.xy, rotate(angle * sin(time * 0.3)) * p.xy, distortionMix);
            p.yz = mix(p.yz, rotate(angle * cos(time * 0.3)) * p.yz, distortionMix);
        } else if (shape == 7) {
            p = mix(p, sin(p * symmetry), distortionMix);
            p.xy = mix(p.xy, rotate(angle * time * 0.2) * p.xy, distortionMix);
            p.xz = mix(p.xz, rotate(-angle * time * 0.2) * p.xz, distortionMix);
            p = mix(p, p * 1.1, distortionMix);
        } else if (shape == 8) {
            float a = 1.0;
            float b = time * 0.1;
            vec3 num = p * cosh(b) + cross(vec3(0.0, 1.0, 0.0), p) * sinh(b);
            float denom = dot(p, p) * sinh(b) + cosh(b);
            p = mix(p, num / denom, distortionMix);
            p.xy = mix(p.xy, rotate(angle) * p.xy, distortionMix);
        } else if (shape == 9) {
            float twist = angle * sin(time * 0.3);
            p.xy = mix(p.xy, rotate(angle + twist) * p.xy, distortionMix);
            p.xz = mix(p.xz, rotate(angle - twist) * p.xz, distortionMix);
            p = mix(p, p * 1.2, distortionMix);
        } else if (shape == 10) {
            p += distortionMix * sin(p * symmetry + time) * 0.1;
            p.xy = mix(p.xy, rotate(angle) * p.xy, distortionMix);
            p.yz = mix(p.yz, rotate(-angle) * p.yz, distortionMix);
            p = mix(p, p * 1.05, distortionMix);
        }
    }
    return p;
}

void main() {
    vec2 uv_original = isf_FragNormCoord;
    vec2 uv_effect = uv_original * 2.0 - 1.0;
    float aspectRatio = RENDERSIZE.x / RENDERSIZE.y;
    uv_effect.x *= aspectRatio;
    vec2 uv = mix(uv_original, uv_effect, distortionMix);
    float time = TIME * rotationSpeed;
    float zoom = 1.0 + zoomSpeed * time;
    float adjustedZoom = mix(1.0, zoom, distortionMix);
    vec3 rd = normalize(vec3(uv, adjustedZoom));
    float complexityClamped = clamp(complexity, 1.0, 20.0);
    int iter_floor = int(floor(complexityClamped));
    int iter_ceil = int(ceil(complexityClamped));
    float frac = fract(complexityClamped);
    vec3 transformedCoordFloor = fractalKaleidoscope(rd, iter_floor, symmetry, time, distortionMix, int(shape));
    vec3 transformedCoordCeil = fractalKaleidoscope(rd, iter_ceil, symmetry, time, distortionMix, int(shape));
    vec3 transformedCoord = mix(transformedCoordFloor, transformedCoordCeil, frac);
    vec3 finalCoord = mix(rd, transformedCoord, distortionMix);
    vec2 videoUV_effect = finalCoord.xy / finalCoord.z * 0.5 + 0.5;
    videoUV_effect = fract(videoUV_effect);
    vec2 videoUV = mix(uv_original, videoUV_effect, distortionMix);
    vec4 videoColor = IMG_NORM_PIXEL(inputImage, videoUV);
    gl_FragColor = vec4(videoColor.rgb, 1.0);
}
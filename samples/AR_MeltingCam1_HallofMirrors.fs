/*
{
    "CATEGORIES": ["Fluid Simulation", "Converted", "Shadertoy"],
    "DESCRIPTION": "Fluid dynamics effect converted from Shadertoy.",
    "INPUTS": [
        { "NAME": "Webcam", "TYPE": "image" },
        { "NAME": "blendStrength", "TYPE": "float", "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.7 },
        { "NAME": "fluidIntensity", "TYPE": "float", "MIN": 0.1, "MAX": 2.0, "DEFAULT": 1.0 },
        { "NAME": "pressureScale", "TYPE": "float", "MIN": 0.1, "MAX": 2.0, "DEFAULT": 1.0 }
    ],
    "PASSES": [
        { "TARGET": "BufferA", "FLOAT": true, "PERSISTENT": true },
        { "TARGET": "BufferB", "FLOAT": true, "PERSISTENT": true },
        { "FLOAT": true }
    ]
}
*/

#define brightness 3.99
#define count 20
#define radius 0.943
#define emitSize 0.950
#define force 0.99
#define constraint 0.91
#define effect 0.99
#define tex(g) IMG_NORM_PIXEL(BufferA, mod((g)/RENDERSIZE.xy, 1.0))
#define melting(g) IMG_NORM_PIXEL(BufferB, mod((g)/RENDERSIZE.xy, 1.0))
#define camchan(g) IMG_NORM_PIXEL(Webcam, mod((g)/RENDERSIZE.xy, 1.0))
#define wallCircle(v,d) if (length(g-(v)) < (d)) gl_FragColor.w = gl_FragColor.z / (length(gl_FragColor.xy) + 0.0001), gl_FragColor.xy *= 0.0;
#define emit(v,s) if (length(g-(v)) < emitSize) gl_FragColor.xy = gl_FragColor.xy * (1.0 - force) + force * (s), gl_FragColor.w = 1.0;

void main() {
    vec2 xy = gl_FragCoord.xy;
    vec4 webcam = camchan(xy);
    vec2 s = RENDERSIZE.xy;
    vec2 g = xy;
    
    vec4 a = tex(g + vec2(1,0));
    vec4 b = tex(g + vec2(0,1));
    vec4 c = tex(g + vec2(-1,0));
    vec4 d = tex(g + vec2(0,-1));
    float lumens = (webcam.r + webcam.g + webcam.b) * 0.333;
    float presh = abs(tex(xy).z);
    float ink = abs(tex(xy).w);
    
    vec4 lastState = tex(g - tex(g).xy);
    vec4 tomachi = vec4(1.0001,1.0002,1.0003,0.0);
    gl_FragColor = lastState * tomachi;
    
    vec2 gp = vec2(a.z - c.z, b.z - d.z);
    float magic = 0.25;
    
    if (lumens > 2.5 || webcam.r > 0.7 || webcam.g > 0.57) {
        emit(xy, vec2(0.8995 + (webcam.r * -0.76), 0.4 + (webcam.g * -0.95) + (webcam.b * -0.5)));
        magic = 0.251;
    }
    
    float pressure = magic * (a.z + b.z + c.z + d.z) * pressureScale - 0.05 * (c.x - a.x + d.y - b.y);
    
    if (lumens < 0.6594) {
        gl_FragColor.z *= 0.9;
        gl_FragColor.w *= 0.9;
        pressure *= (lumens < 0.1) ? 0.1 : 1.00069;
    } else if (lumens > 0.99) {
        pressure *= 1.069;
    }
    
    if (abs(presh) < 1.1 && lumens > brightness * 0.3159) {
        emit(xy, 0.991);
    }
    
    if (d.b > 0.95 && a.r > 0.95) {
        pressure = 0.0;
    }
    
    if (g.x < 1.0 || g.y < 1.0 || g.x > s.x - 1.0 || g.y > s.y - 1.0) {
        gl_FragColor.xy *= 0.0;
    }
    
    if (abs(pressure) > 4.9931 || lumens > 0.8) {
        pressure *= 0.8;
        gl_FragColor.w = abs(gl_FragColor.z) - 0.05;
    }
    
    // Apply adjustable blending
    vec3 fluidColor = vec3(pressure * fluidIntensity, gl_FragColor.y * fluidIntensity, gl_FragColor.z * fluidIntensity);
    gl_FragColor.xyz = mix(webcam.rgb, fluidColor, blendStrength);
}

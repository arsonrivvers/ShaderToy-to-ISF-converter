/*{
    "DESCRIPTION": "Enhanced depth-aware neon outline effect with improved edge detection and glow",
    "CREDIT": "Arson Rivvers",
    "CATEGORIES": [
        "Stylize",
        "Depth"
    ],
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image",
            "LABEL": "Input"
        },
        {
            "NAME": "depthMap",
            "TYPE": "image",
            "LABEL": "Depth Map (Black=Near, White=Far)"
        },
        {
            "NAME": "neonIntensity",
            "LABEL": "Neon Intensity",
            "TYPE": "float",
            "MIN": 0.0,
            "MAX": 1.0,
            "DEFAULT": 0.0
        }
    ],
    "PERSISTENT_BUFFERS": [
        "effectBuffer",
        "trailBuffer"
    ],
    "PASSES": [
        {
            "TARGET": "effectBuffer",
            "PERSISTENT": true,
            "FLOAT": true
        },
         {
            "TARGET": "trailBuffer",
            "PERSISTENT": true,
            "FLOAT": true
        },
        {
            "TARGET": "outputBuffer"
        }
    ]
}*/

////////////////////////////////////////////////////////////
// CONSTANTS & CONFIGURATION
////////////////////////////////////////////////////////////
#define PI 3.14159265359
#define OUTLINE_THICKNESS 2.0
#define OUTLINE_INTENSITY 1.8
#define TRAIL_DECAY 0.95
#define PUNCH_FACTOR 5.0
#define EDGE_THRESHOLD 0.1
#define GLOW_RADIUS 3.0
#define MOTION_THRESHOLD 0.1
#define COLOR_CYCLE_SPEED 0.2
#define GRAIN_OCTAVES 4
#define GRAIN_PERSISTENCE 0.5
#define GRAIN_SCALE 1.2
#define PULSE_SPEED 2.0
#define ABERRATION_AMOUNT 0.002
#define FLOW_STRENGTH 0.005
#define AFTERGLOW_STRENGTH 0.3
#define MOTION_BLUR_SAMPLES 4
#define RIPPLE_STRENGTH 0.005
#define RIPPLE_DECAY 0.98
#define AFTERGLOW_DECAY 0.95
#define TRAIL_PERSISTENCE 0.85
#define MOTION_FADE_SPEED 0.2
#define RIPPLE_DISSIPATION 0.98
#define TURBULENCE_SCALE 2.0
#define TURBULENCE_SPEED 0.5
#define BLEED_RATE 0.15
#define FRAGMENT_SPEED 0.8
#define QUICK_FADE_THRESHOLD 0.2
#define LAYER_COUNT 3
#define FAST_DECAY 0.75
#define GHOST_PERSISTENCE 0.85
#define GHOST_FADE_SPEED 0.95
#define MIN_ALPHA_THRESHOLD 0.01

// Enhanced color controls - individual colors instead of array
#define COLOR_1 vec3(1.0, 0.2, 0.8)  // magenta
#define COLOR_2 vec3(0.8, 0.3, 1.0)  // purple
#define COLOR_3 vec3(0.0, 1.0, 1.0)  // cyan
#define COLOR_4 vec3(0.2, 1.0, 0.5)  // neon green
#define COLOR_5 vec3(1.0, 0.6, 0.0)  // orange
#define COLOR_6 vec3(0.7, 0.2, 1.0)  // violet

////////////////////////////////////////////////////////////
// UTILITY FUNCTIONS
////////////////////////////////////////////////////////////

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx+p3.yz)*p3.zy);
}

float smoothPunch(float x) {
    return pow(smoothstep(0.0, 0.1, x), 1.2) * (1.0 + PUNCH_FACTOR * exp(-TIME * 4.0));
}

vec2 getGradient(vec2 uv, float eps) {
    float dx = length(IMG_NORM_PIXEL(inputImage, uv + vec2(eps,0)).rgb) 
             - length(IMG_NORM_PIXEL(inputImage, uv - vec2(eps,0)).rgb);
    float dy = length(IMG_NORM_PIXEL(inputImage, uv + vec2(0,eps)).rgb) 
             - length(IMG_NORM_PIXEL(inputImage, uv - vec2(0,eps)).rgb);
    return vec2(dx, dy);
}
vec2 getGradientBuffer(vec2 uv, float eps) {
    float dx = length(IMG_PIXEL(effectBuffer, uv + vec2(eps,0)).rgb) 
             - length(IMG_PIXEL(effectBuffer, uv - vec2(eps,0)).rgb);
    float dy = length(IMG_PIXEL(effectBuffer, uv + vec2(0,eps)).rgb) 
             - length(IMG_PIXEL(effectBuffer, uv - vec2(0,eps)).rgb);
    return vec2(dx, dy);
}

float getDepthEdge(vec2 uv, float eps) {
    float d0 = IMG_NORM_PIXEL(depthMap, uv).r;
    float d1 = IMG_NORM_PIXEL(depthMap, uv + vec2(eps,0)).r;
    float d2 = IMG_NORM_PIXEL(depthMap, uv - vec2(eps,0)).r;
    float d3 = IMG_NORM_PIXEL(depthMap, uv + vec2(0,eps)).r;
    float d4 = IMG_NORM_PIXEL(depthMap, uv - vec2(0,eps)).r;
    
    return max(max(abs(d0-d1), abs(d0-d2)), max(abs(d0-d3), abs(d0-d4)));
}

float voronoiNoise(vec2 x) {
    vec2 n = floor(x);
    vec2 f = fract(x);

    float m = 8.0;
    for(int j = -1; j <= 1; j++) {
        for(int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i),float(j));
            vec2 o = hash22(n + g);
            o = 0.5 + 0.5 * sin(TIME * 0.5 + 6.2831 * o);
            float d = length(g - f + o);
            m = min(m, d);
        }
    }
    return m;
}

float advancedGrain(vec2 uv, float time) {
    float noise = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    
    for(int i = 0; i < GRAIN_OCTAVES; i++) {
        noise += voronoiNoise(uv * frequency + time) * amplitude;
        amplitude *= GRAIN_PERSISTENCE;
        frequency *= GRAIN_SCALE;
        
        float angle = time * 0.1 + float(i) * PI / 4.0;
        mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
        uv *= rot;
    }
    
    return noise / float(GRAIN_OCTAVES);
}

vec3 cycleNeonColors(float depth, float time) {
    float cycleTime = time * COLOR_CYCLE_SPEED;
    float phase = mod(cycleTime, 6.0);
    int index = int(phase);
    float blend = fract(phase);
    
    vec3 currentColor, nextColor;
    
    if (index == 0) { currentColor = COLOR_1; nextColor = COLOR_2; }
    else if (index == 1) { currentColor = COLOR_2; nextColor = COLOR_3; }
    else if (index == 2) { currentColor = COLOR_3; nextColor = COLOR_4; }
    else if (index == 3) { currentColor = COLOR_4; nextColor = COLOR_5; }
    else if (index == 4) { currentColor = COLOR_5; nextColor = COLOR_6; }
    else { currentColor = COLOR_6; nextColor = COLOR_1; }
    
    vec3 blendedColor = mix(currentColor, nextColor, blend);
    
    vec3 farColor;
    int farIndex = int(mod(float(index + 3), 6.0));
    
    if (farIndex == 0) farColor = COLOR_1;
    else if (farIndex == 1) farColor = COLOR_2;
    else if (farIndex == 2) farColor = COLOR_3;
    else if (farIndex == 3) farColor = COLOR_4;
    else if (farIndex == 4) farColor = COLOR_5;
    else farColor = COLOR_6;
    
    return mix(farColor, blendedColor, 1.0 - depth);
}

float getMotionFactor(vec2 uv) {
    vec4 current = IMG_NORM_PIXEL(inputImage, uv);
    vec4 previous = IMG_PIXEL(effectBuffer, gl_FragCoord.xy);
    return smoothstep(0.0, MOTION_THRESHOLD, length(current - previous));
}

vec4 enhanceColor(vec4 color, float intensity) {
    vec3 luminance = vec3(0.2126, 0.7152, 0.0722);
    float lum = dot(color.rgb, luminance);
    
    vec3 brightColor = mix(
        color.rgb,
        color.rgb * (1.0 + intensity * 0.5),
        smoothstep(0.0, 0.5, intensity)
    );
    
    vec2 sparkleUV = gl_FragCoord.xy;
    float sparkle = hash21(sparkleUV + TIME * 20.0)
                  * hash21(sparkleUV * 1.4 - TIME * 15.0);
    sparkle = pow(sparkle, 4.0) * 3.0;
    float sparkleAmt = intensity * 0.4 * (0.8 + lum * 0.6);
    
    vec3 warmTint = vec3(1.05, 1.02, 0.98);
    vec3 coldTint = vec3(0.98, 1.02, 1.05);
    vec3 tint = mix(coldTint, warmTint, intensity);
    
    vec3 result = brightColor * tint + vec3(sparkle * sparkleAmt);
    result = result / (1.0 + length(result) * 0.2);
    
    return vec4(clamp(result, 0.0, 1.0), color.a);
}

vec2 aberrate(vec2 uv, float channel, float intensity) {
    float amount = ABERRATION_AMOUNT * intensity;
    return uv + vec2(
        cos(TIME + channel * 2.0 * PI/3.0), 
        sin(TIME + channel * 2.0 * PI/3.0)
    ) * amount;
}

vec4 generateNeonOutlines(vec2 uv, float depth, float intensity) {
    vec2 px = 1.0/RENDERSIZE.xy;
    float outline = 0.0;
    float depthEdge = getDepthEdge(uv, px.x * OUTLINE_THICKNESS);
    vec2 gradient = getGradient(uv, px.x);
    
    vec4 center = IMG_NORM_PIXEL(inputImage, uv);
    float centerDepth = IMG_NORM_PIXEL(depthMap, uv).r;
    
    float radius = mix(1.0, OUTLINE_THICKNESS * 2.0, intensity) * (1.0 - depth * 0.5);
    
    for(int x = -1; x <= 1; x++) {
        for(int y = -1; y <= 1; y++) {
            if(x == 0 && y == 0) continue;
            
            vec2 offset = vec2(float(x), float(y)) * px * radius;
            vec4 neighbor = IMG_NORM_PIXEL(inputImage, uv + offset);
            float neighborDepth = IMG_NORM_PIXEL(depthMap, uv + offset).r;
            
            outline += length(center - neighbor) + 
                      abs(centerDepth - neighborDepth) * 2.0 +
                      length(gradient) * 0.5;
        }
    }
    
    float pulse = 0.5 + 0.5 * sin(TIME * PULSE_SPEED + outline * 10.0);
    outline = smoothstep(EDGE_THRESHOLD, 0.3, outline) * pulse * smoothPunch(intensity);
    outline += depthEdge * intensity * 2.0;
    
    vec2 uvRed = aberrate(uv, 0.0, intensity);
    vec2 uvGreen = aberrate(uv, 1.0, intensity);
    vec2 uvBlue = aberrate(uv, 2.0, intensity);
    
    vec3 neonColorR = cycleNeonColors(depth, TIME);
    vec3 neonColorG = cycleNeonColors(depth, TIME + 0.33);
    vec3 neonColorB = cycleNeonColors(depth, TIME + 0.66);
    
    float depthFactor = 1.0 - depth;
    
    vec2 flowOffset = normalize(gradient) * FLOW_STRENGTH * intensity;
    
    float glowIntensity = mix(0.5, 1.5, depthFactor);
    vec3 glow = vec3(0.0);
    
    for(int i = 0; i < int(GLOW_RADIUS); i++) {
        float angle = float(i) * PI * 2.0 / GLOW_RADIUS;
        vec2 baseOffset = vec2(cos(angle), sin(angle)) * px * float(i);
        
        vec2 glowOffset = baseOffset + flowOffset * float(i);
        
        float glowSample = outline * exp(-float(i) * (0.5 - depthFactor * 0.2));
        
        vec2 redOffset = aberrate(uv + glowOffset, 0.0, intensity);
        vec2 greenOffset = aberrate(uv + glowOffset, 1.0, intensity);
        vec2 blueOffset = aberrate(uv + glowOffset, 2.0, intensity);
        
        float grainR = advancedGrain(redOffset + TIME * 0.05, TIME);
        float grainG = advancedGrain(greenOffset + TIME * 0.05, TIME);
        float grainB = advancedGrain(blueOffset + TIME * 0.05, TIME);
        
        glow.r += glowSample * glowIntensity * (1.0 + grainR * 0.2);
        glow.g += glowSample * glowIntensity * (1.0 + grainG * 0.2);
        glow.b += glowSample * glowIntensity * (1.0 + grainB * 0.2);
    }
    
    vec4 result = vec4(0.0);
    
    // Combine all color channels, instead of grabbing individual channels of other results
    result.rgb = (neonColorR * (outline + glow.r * 0.5) +
                 neonColorG * (outline + glow.g * 0.5) +
                 neonColorB * (outline + glow.b * 0.5)) / 3.0;
     
    result.a = outline;
    
    vec3 colorGrain = vec3(
        advancedGrain(uvRed * 2.0 + TIME * 0.2, TIME),
        advancedGrain(uvGreen * 2.0 + TIME * 0.2, TIME),
        advancedGrain(uvBlue * 2.0 + TIME * 0.2, TIME)
    ) * 0.1;
    
    result.rgb += vec3(
        neonColorR.r * colorGrain.r,
        neonColorG.g * colorGrain.g,
        neonColorB.b * colorGrain.b
    ) * intensity;
    
    return result;
}

vec4 applyMotionBlur(vec2 uv, vec2 velocity, vec4 current, vec4 previous) {
    vec4 blurred = vec4(0.0);
    float totalWeight = 0.0;

    for(int i = 0; i < MOTION_BLUR_SAMPLES; i++) {
        float t = float(i) / float(MOTION_BLUR_SAMPLES - 1);
        vec2 offset = velocity * (t - 0.5);
        float weight = 1.0 - abs(t - 0.5) * 2.0;

        blurred += mix(current, previous,0.5) * weight;
        totalWeight += weight;
    }
    
    return blurred / totalWeight;
}

vec2 getTurbulenceOffset(vec2 uv, float time) {
    vec2 turbulence;
    turbulence.x = advancedGrain(uv * TURBULENCE_SCALE + vec2(time * 0.3, 0.0), time);
    turbulence.y = advancedGrain(uv * TURBULENCE_SCALE + vec2(0.0, time * 0.3), time);
    return (turbulence - 0.5) * 2.0;
}

vec2 getFragmentOffset(vec2 uv, float time, float seed, float alpha) {
    vec2 hash = hash22(uv + seed);
    float angle = hash.x * 2.0 * PI;
    float speed = hash.y * FRAGMENT_SPEED;
    return vec2(cos(angle), sin(angle)) * speed * time * (1.0 - alpha);
}

vec4 sampleTrail(vec2 uv, float time, vec2 motion, float alpha, vec4 previous, vec4 current)
{
    vec4 sample = vec4(0.0);

     // Multi-layered dissipation
        vec4 finalTrail = vec4(0.0);
        vec2 totalOffset;
        vec2 bleedOffset;
        vec4 layerSample;

     for(int i = 0; i < LAYER_COUNT; i++) {
          float layerTime = time * (1.0 + float(i) * 0.2);
         float layerWeight = 1.0 / float(LAYER_COUNT);
            
          // Turbulence offset
         vec2 turbOffset = getTurbulenceOffset(uv, layerTime) * 
                           (1.0 - alpha) * 0.01;
         
            // Fragment offset
            vec2 fragOffset = getFragmentOffset(uv, layerTime, float(i), alpha);
          // Combine offsets
          totalOffset = turbOffset + fragOffset;

         // Ink bleed effect
            float bleedFactor = advancedGrain(uv * 2.0 - layerTime, TIME) * BLEED_RATE;
         bleedOffset =   bleedFactor * motion;

         // Sample with offset
          vec2 sampleUV = uv + totalOffset;
          vec4 bleedSample = IMG_PIXEL(trailBuffer, gl_FragCoord.xy + bleedOffset * RENDERSIZE);
          layerSample = IMG_PIXEL(trailBuffer, gl_FragCoord.xy + totalOffset * RENDERSIZE);
          layerSample = mix(layerSample, bleedSample, 0.3);
           
           // Apply time-based decay and distance falloff
            layerSample *= exp(-length(totalOffset) * 2.0) * exp(-time * 3.0);
         
             finalTrail += layerSample * layerWeight;
        }

    sample = mix(previous, finalTrail, 0.5);
     return sample;
}

////////////////////////////////////////////////////////////
// MAIN
////////////////////////////////////////////////////////////

void main() {
    vec2 uv = gl_FragCoord.xy/RENDERSIZE.xy;
    float depth = IMG_NORM_PIXEL(depthMap, uv).r;
    vec4 source = IMG_NORM_PIXEL(inputImage, uv);
    
    if (PASSINDEX == 0) {  // Effect accumulation pass
        vec4 currentEffect = source;
        vec4 prevEffect = IMG_PIXEL(effectBuffer, gl_FragCoord.xy);
        
        if (neonIntensity > 0.0) {
            vec4 neonEffect = generateNeonOutlines(uv, depth, neonIntensity);
            float motionFactor = getMotionFactor(uv);
            float blendFactor = mix(0.3, 0.8, motionFactor);
            
            currentEffect = mix(
                currentEffect,
                currentEffect + neonEffect * OUTLINE_INTENSITY,
                smoothPunch(neonIntensity) * blendFactor
            );
            currentEffect.a = neonEffect.a; // Store alpha for ghosting
        } else {
            // Preserve ghosting when intensity drops to zero
            currentEffect = prevEffect;
            currentEffect *= GHOST_FADE_SPEED;
        }
        
        gl_FragColor = currentEffect;
    }
    else if (PASSINDEX == 1) {  // Motion trails pass
        vec4 currentFrame = IMG_PIXEL(effectBuffer, gl_FragCoord.xy);
        vec4 previousTrail = IMG_PIXEL(trailBuffer, gl_FragCoord.xy);
        
        // Quick initial fade for strong effects
        if (previousTrail.a > QUICK_FADE_THRESHOLD) {
            previousTrail *= FAST_DECAY;
        }
         
          // Motion from effect buffer
            vec2 motion = getGradientBuffer(uv, 1.0/RENDERSIZE.x);

           // Motion blur
          vec4 blurredCurrent = applyMotionBlur(uv, motion, currentFrame, previousTrail);

           // Apply motion-based decay
          float motionMagnitude = length(motion);
          float dynamicDecay = mix(RIPPLE_DISSIPATION, 0.2, smoothstep(0.0,0.5,motionMagnitude * 2.0));
           
         float trailAlpha = mix(0.2,0.4, 1.0 - neonIntensity);
         
          vec4 trailMixed =   sampleTrail(uv, TIME, motion,  1.0 - neonIntensity, previousTrail, blurredCurrent);

            // Voronoi-based fragmentation
            if(neonIntensity <= 0.0)
            {
              float fragPattern = voronoiNoise(uv * 4.0 + TIME);
             fragPattern = pow(fragPattern, 3.0);
            trailMixed *= mix(1.0, fragPattern, 0.8);
               // Additional decay for ghosting
                trailMixed *= GHOST_FADE_SPEED;
            }

          
           // Combine current and previous with dynamic decay
         
       
            // Quick fade for low alpha values
          if (trailMixed.a < QUICK_FADE_THRESHOLD) {
            trailMixed *= FAST_DECAY;
          }

        gl_FragColor = mix(blurredCurrent, trailMixed, trailAlpha) ;
        
        }
    else {  // Final output pass
        vec4 effect = IMG_PIXEL(effectBuffer, gl_FragCoord.xy);
        vec4 trail = IMG_PIXEL(trailBuffer, gl_FragCoord.xy);
        
        // Dynamic afterglow strength
        float afterglowStrength = AFTERGLOW_STRENGTH * (1.0 + advancedGrain(uv + TIME * 0.3, TIME) * 0.2);
        
        // Complex fade pattern
        float fadePattern = voronoiNoise(uv * 3.0 + TIME * 0.1);
        fadePattern = pow(fadePattern, 2.0);
        
        // Combine effect and trail with dynamic masking
        vec4 combined = mix(
            effect,
            trail,
            trail.a * afterglowStrength * fadePattern
        );
        
        // Enhanced color processing
        vec4 enhanced = enhanceColor(combined, max(neonIntensity, length(trail.rgb) * 0.5));
        
        // Smooth transition
        float transitionFactor = smoothstep(0.0, 0.3, neonIntensity);
        
        gl_FragColor = mix(source, enhanced, max(transitionFactor, length(trail.rgb)));
    }
}
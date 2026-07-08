/*{
  "CREDIT": "by thedantheman (modified)",
  "DESCRIPTION": "Separation Glitch with Effect Strength",
  "CATEGORIES": ["Glitch"],
  "INPUTS": [
    { "NAME":"inputImage",    "TYPE":"image" },
    { "NAME":"progress",      "TYPE":"float", "DEFAULT":0.5, "MIN":0, "MAX":1 },
    { "NAME":"depth",         "TYPE":"float", "DEFAULT":0.5, "MIN":0, "MAX":1 },
    { "NAME":"strength",      "TYPE":"float", "DEFAULT":0.5, "MIN":0, "MAX":1 },
    { "NAME":"effectStrength","TYPE":"float", "DEFAULT":0,   "MIN":0, "MAX":1 },
    { "NAME":"voronoiScale1", "TYPE":"float", "DEFAULT":0.003, "MIN":0.001, "MAX":0.1 },
    { "NAME":"voronoiScale2", "TYPE":"float", "DEFAULT":0.2, "MIN":0.01, "MAX":1.0 },
    { "NAME":"voronoiOffset1","TYPE":"float", "DEFAULT":2.0, "MIN":-5.0, "MAX":5.0 },
    { "NAME":"voronoiOffset2","TYPE":"float", "DEFAULT":-1.0, "MIN":-5.0, "MAX":5.0 },
    { "NAME":"grayR",         "TYPE":"float", "DEFAULT":0.299, "MIN":0.0, "MAX":1.0 },
    { "NAME":"grayG",         "TYPE":"float", "DEFAULT":0.587, "MIN":0.0, "MAX":1.0 },
    { "NAME":"grayB",         "TYPE":"float", "DEFAULT":0.114, "MIN":0.0, "MAX":1.0 },
    { "NAME":"easeExp1",      "TYPE":"float", "DEFAULT":20.0, "MIN":1.0, "MAX":40.0 },
    { "NAME":"easeExp2",      "TYPE":"float", "DEFAULT":10.0, "MIN":1.0, "MAX":20.0 },
    { "NAME":"smoothMin",     "TYPE":"float", "DEFAULT":0.0, "MIN":0.0, "MAX":0.5 },
    { "NAME":"smoothMid",     "TYPE":"float", "DEFAULT":0.5, "MIN":0.1, "MAX":0.9 },
    { "NAME":"smoothMax",     "TYPE":"float", "DEFAULT":1.0, "MIN":0.5, "MAX":1.0 },
    { "NAME":"grayIntensity", "TYPE":"float", "DEFAULT":2.0, "MIN":0.0, "MAX":5.0 }
  ]
}*/

#ifdef GL_ES
precision highp float;
#endif

// ISF auto-declares each INPUT as a uniform; explicit re-declaration collides on the Metal backend.

float random(vec2 co) {
    float a=12.9898, b=78.233, c=43758.5453;
    float dt=dot(co,vec2(a,b)), sn=mod(dt,3.14);
    return fract(sin(sn)*c);
}

float voronoi(in vec2 x) {
    vec2 p=floor(x), f=fract(x);
    float res=8.0;
    for(float j=-1.; j<=1.; j++)
    for(float i=-1.; i<=1.; i++){
        vec2 b=vec2(i,j), r=b-f+random(p+b);
        res=min(res,dot(r,r));
    }
    return sqrt(res);
}

vec2 displace(vec4 tex, vec2 uv, float dD, float tD, float str) {
    float b=voronoi(voronoiScale1*uv+voronoiOffset1);
    float g=voronoi(voronoiScale2*uv);
    float r=voronoi(uv+voronoiOffset2);
    vec4 dt=tex;
    vec4 d=dt*dD+vec4(1.0)-tex*tD;
    d.x=(d.x-1.0+tD*dD)*str;
    d.y=(d.y-1.0+tD*dD)*str;
    return uv+d.xy;
}

float ease1(float t) {
    return (t==0.||t==1.)?t:
           (t<0.5)?0.5*pow(2.0,easeExp1*t-(easeExp1/2.0)):
                    -0.5*pow(2.0,(easeExp1/2.0)-easeExp1*t)+1.;
}

float ease2(float t) {
    return (t==1.)?t:1.-pow(2.0,-easeExp2*t);
}

void main(){
    vec2 p = gl_FragCoord.xy / RENDERSIZE;     // normalized coordinates
    vec4 orig = IMG_NORM_PIXEL(inputImage, p);

    // ► combine user progress + effectStrength
    float gp = progress * effectStrength;

    // ► compute eased values
    float e1 = ease1(gp);
    float e2 = ease2(gp);

    // ► full displacements
    vec2 fD1 = displace(orig, p, depth,       1.0-depth,      strength - e1);
    vec2 fD2 = displace(orig, p, depth,       depth*0.5,      e2);

    // ► lerp UVs by same gp
    vec2 d1 = mix(p, fD1, gp);
    vec2 d2 = mix(p, fD2, gp);

    // ► sample displaced
    vec4 c1 = IMG_NORM_PIXEL(inputImage, d1);
    vec4 c2 = IMG_NORM_PIXEL(inputImage, d2);

    // ► grayscale blend
    vec3 gray = vec3(dot(min(c2.rgb, c1.rgb), vec3(grayR, grayG, grayB)));
    vec4 gC = vec4(gray,1.0)*grayIntensity;

    // ► generative mixing using gp
    vec4 b1 = mix(orig, gC,        smoothstep(smoothMin, smoothMid, gp));
    vec4 b2 = mix(orig, c1,        smoothstep(smoothMax, smoothMid, gp));

    // ► final blend between branches
    float t = smoothstep(smoothMin, smoothMax, e1);
    vec4 glitch = mix(b1, b2, t);

    gl_FragColor = glitch;
}
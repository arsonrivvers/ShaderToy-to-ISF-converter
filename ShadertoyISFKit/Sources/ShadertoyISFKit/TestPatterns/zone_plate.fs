/*{ "DESCRIPTION": "Animated zone plate", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    vec2 p = (isf_FragNormCoord - 0.5) * RENDERSIZE;
    float r2 = dot(p, p);
    float v = 0.5 + 0.5 * sin(r2 * 0.0015 + TIME * 2.0);
    gl_FragColor = vec4(vec3(v), 1.0);
}

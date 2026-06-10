/*{ "DESCRIPTION": "Crosshatch grid", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    vec2 px = isf_FragNormCoord * RENDERSIZE;
    vec2 g = mod(px, 32.0);
    float line = (g.x < 1.0 || g.y < 1.0) ? 1.0 : 0.15;
    gl_FragColor = vec4(vec3(line), 1.0);
}

/*{ "DESCRIPTION": "Scrolling checkerboard", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    vec2 uv = isf_FragNormCoord * 8.0;
    uv.x += TIME * 0.5;
    float c = mod(floor(uv.x) + floor(uv.y), 2.0);
    gl_FragColor = vec4(vec3(c), 1.0);
}

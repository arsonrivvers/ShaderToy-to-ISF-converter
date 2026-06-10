/*{ "DESCRIPTION": "Grayscale staircase (11 steps)", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    float v = floor(isf_FragNormCoord.x * 11.0) / 10.0;
    gl_FragColor = vec4(vec3(v), 1.0);
}

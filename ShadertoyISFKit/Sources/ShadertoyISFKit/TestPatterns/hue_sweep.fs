/*{ "DESCRIPTION": "Hue sweep gradient", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    float h = fract(isf_FragNormCoord.x + TIME * 0.1);
    vec3 c = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    gl_FragColor = vec4(c, 1.0);
}

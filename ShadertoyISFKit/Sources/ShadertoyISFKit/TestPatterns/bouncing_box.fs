/*{ "DESCRIPTION": "Bouncing box motion test", "CATEGORIES": ["Test Pattern"], "INPUTS": [] }*/
void main() {
    vec2 uv = isf_FragNormCoord;
    vec2 pos = vec2(0.5 + 0.4 * sin(TIME * 1.3), 0.5 + 0.4 * sin(TIME * 1.7));
    vec2 d = abs(uv - pos);
    float box = (d.x < 0.06 && d.y < 0.06) ? 1.0 : 0.0;
    vec3 c = mix(vec3(0.05), vec3(1.0, 0.6, 0.1), box);
    gl_FragColor = vec4(c, 1.0);
}

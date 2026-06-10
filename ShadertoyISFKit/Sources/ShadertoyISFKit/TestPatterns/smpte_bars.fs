/*{
    "DESCRIPTION": "SMPTE 75% color bars",
    "CATEGORIES": ["Test Pattern"],
    "INPUTS": []
}*/
void main() {
    float seg = floor(isf_FragNormCoord.x * 7.0);
    vec3 c = vec3(0.75);
    if      (seg < 0.5) c = vec3(0.75, 0.75, 0.75);
    else if (seg < 1.5) c = vec3(0.75, 0.75, 0.00);
    else if (seg < 2.5) c = vec3(0.00, 0.75, 0.75);
    else if (seg < 3.5) c = vec3(0.00, 0.75, 0.00);
    else if (seg < 4.5) c = vec3(0.75, 0.00, 0.75);
    else if (seg < 5.5) c = vec3(0.75, 0.00, 0.00);
    else                c = vec3(0.00, 0.00, 0.75);
    gl_FragColor = vec4(c, 1.0);
}

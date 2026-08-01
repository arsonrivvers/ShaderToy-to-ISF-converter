/*{
    "ISFVSN": "2.0",
    "DESCRIPTION": "Black at t=0, red past t=1 — proves a render actually sampled a later TIME rather than defaulting to zero.",
    "CREDIT": "ARShader test fixture",
    "CATEGORIES": ["Test"],
    "INPUTS": []
}*/

void main() {
    vec3 color = TIME > 1.0 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 0.0);
    gl_FragColor = vec4(color, 1.0);
}

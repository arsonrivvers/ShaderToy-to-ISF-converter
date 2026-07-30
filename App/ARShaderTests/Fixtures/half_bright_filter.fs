/*{
    "DESCRIPTION": "Test fixture: halves its input. Non-commutative with invert.",
    "CREDIT": "ARShader tests",
    "ISFVSN": "2.0",
    "CATEGORIES": ["Test"],
    "INPUTS": [ { "NAME": "inputImage", "TYPE": "image" } ]
}*/

void main() {
    vec4 c = IMG_THIS_PIXEL(inputImage);
    gl_FragColor = vec4(c.rgb * 0.5, c.a);
}

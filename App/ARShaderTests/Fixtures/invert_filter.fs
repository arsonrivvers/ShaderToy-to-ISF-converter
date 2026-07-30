/*{
    "DESCRIPTION": "Test fixture: inverts its input.",
    "CREDIT": "ARShader tests",
    "ISFVSN": "2.0",
    "CATEGORIES": ["Test"],
    "INPUTS": [ { "NAME": "inputImage", "TYPE": "image" } ]
}*/

void main() {
    vec4 c = IMG_THIS_PIXEL(inputImage);
    gl_FragColor = vec4(1.0 - c.rgb, c.a);
}

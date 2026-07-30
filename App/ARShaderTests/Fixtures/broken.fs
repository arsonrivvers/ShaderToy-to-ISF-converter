/*{
    "ISFVSN": "2.0",
    "DESCRIPTION": "Deliberately uncompilable — proves a failed compile never reaches the output.",
    "CATEGORIES": ["Test"],
    "INPUTS": []
}*/

void main() {
    gl_FragColor = this_symbol_does_not_exist(1.0);
}

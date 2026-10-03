// Shared "library" script. The LIB_ prefix prevents GlobalScript from
// auto-loading it - it's meant to be imported by other scripts.
function testAdd(a, b) return a + b;

var libValue = 42;

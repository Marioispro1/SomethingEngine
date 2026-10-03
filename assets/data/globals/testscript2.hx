// Second test script - imports the same LIB_ file as testscript.hx.
// Its import should hit the AST cache (no re-parse).
import data.globals.testlib;

function new() {
	trace("[TESTSCRIPT2] loaded, testAdd(10, 5) = " + testAdd(10, 5));
}

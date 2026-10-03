// SomethingEngine test script - verifies hscript loading + AST caching
import data.globals.testlib;

var stateSwitches:Int = 0;
var beats:Int = 0;

function new() {
	trace("[TESTSCRIPT] hello from " + engine.name + " v" + Flags.VERSION);
	trace("[TESTSCRIPT] testAdd(2, 3) = " + testAdd(2, 3) + ", libValue = " + libValue);
}

function postStateSwitch() {
	stateSwitches++;
	trace("[TESTSCRIPT] state switch #" + stateSwitches + " -> " + Type.getClassName(Type.getClass(FlxG.state)));
}

function destroy() {
	trace("[TESTSCRIPT] destroyed after " + stateSwitches + " state switches");
}

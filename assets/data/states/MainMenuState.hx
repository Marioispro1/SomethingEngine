function postCreate() {
	__sneEditorPatch();
}

// >>> STATE EDITOR PATCH - regenerated on export, do not edit below <<<
var __editor_1:Dynamic = null;
function __sneEditorPatch() {
__editor_1 = new funkin.backend.FunkinText(0, 0, 0, "TEST BUTTON", 40);
__editor_1.visible = true;
__editor_1.x = 0;
__editor_1.y = 0;
__editor_1.scrollFactor.set(1, 1);
__editor_1.scale.set(1, 1);
__editor_1.updateHitbox();
__editor_1.alpha = 1;
__editor_1.color = 0xFF5BCEFA;
__editor_1.antialiasing = false;
__editor_1.text = "TEST BUTTON";
__editor_1.size = 40;
__editor_1.fieldWidth = 257;
add(__editor_1);

}

function __sneEditorUpdate(elapsed) {
if (FlxG.mouse.justPressed && FlxG.mouse.overlaps(__editor_1)) {
var obj = __editor_1;
obj.text = "CLICKED!"; trace("[TESTSCRIPT] button clicked");
}
// update hook for __editor_1
{
var obj = __editor_1;
if (obj.x < 500) obj.x += 150 * elapsed;
}

}
// >>> END STATE EDITOR PATCH <<<
function update(elapsed) {
	__sneEditorUpdate(elapsed);
}

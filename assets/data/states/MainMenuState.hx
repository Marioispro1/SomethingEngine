// >>> STATE EDITOR PATCH - regenerated on export, do not edit below <<<
// SNE-META {"mov":[],"rem":["versionText","versionText"],"trk":{},"hooks":{},"anim":{},"edit":["bg"],"objs":[],"snip":[{"c":"trace(\"main menu was customized by the state editor\");","p":0},{"c":"trace(\"main menu was customized by the state editor\");","p":0}]}
function __sneEditorPatch() {
remove(versionText); // deleted via State Editor
remove(versionText); // deleted via State Editor
// edits to bg
bg.visible = true;
bg.x = -91.5972392638039;
bg.y = -44.7648662041624;
bg.scrollFactor.set(0, 0.18);
bg.scale.set(1.15, 1.15);
bg.updateHitbox();
bg.alpha = 1;
bg.color = 0xFFFFFFFF;
bg.offset.set(-96.4499999999999, -54.7499999999999);
bg.antialiasing = true;
bg.animation.play("idle");
// code runner snippet
trace("main menu was customized by the state editor");
// code runner snippet
trace("main menu was customized by the state editor");

}

function __sneEditorUpdate(elapsed) {

}
// >>> END STATE EDITOR PATCH <<<
function postCreate() {
	__sneEditorPatch();
}
function update(elapsed) {
	__sneEditorUpdate(elapsed);
}

// >>> STATE EDITOR PATCH - regenerated on export, do not edit below <<<
var logo:Dynamic = null;
var gf:Dynamic = null;
var titleText:Dynamic = null;
var demoButton:Dynamic = null;
function __sneEditorPatch() {
// edits to versionText
versionText.visible = true;
versionText.x = 20;
versionText.y = 20;
versionText.scrollFactor.set(0, 0);
versionText.scale.set(1, 1);
versionText.updateHitbox();
versionText.alpha = 1;
versionText.color = 0xFFFFFFFF;
versionText.antialiasing = false;
versionText.text = "edited live via the State Editor (F4)";
versionText.size = 16;
versionText.fieldWidth = 337;
versionText.borderStyle = Type.createEnumIndex(Type.resolveEnum("flixel.text.FlxTextBorderStyle"), 3);
versionText.borderColor = 0xFF000000;
versionText.borderSize = 1;
// edits to bg
bg.visible = true;
bg.x = -99.4499999999999;
bg.y = -59.7499999999999;
bg.scrollFactor.set(0, 0.18);
bg.scale.set(1.15, 1.15);
bg.updateHitbox();
bg.alpha = 1;
bg.color = 0xFF77D4FF;
bg.offset.set(-96.4499999999999, -54.7499999999999);
bg.antialiasing = true;
bg.animation.play("idle");
logo = ((function() { var s = new flixel.FlxSprite(20, 15); s.frames = Paths.getFrames("menus/titlescreen/logo"); s.animation.addByPrefix("bump", "logo bumpin", 24, false); s.animation.play("bump"); s.scale.set(0.35, 0.35); s.updateHitbox(); s.scrollFactor.set(); return s; })());
logo.visible = true;
logo.x = 20;
logo.y = 15;
logo.scrollFactor.set(0, 0);
logo.scale.set(0.35, 0.35);
logo.updateHitbox();
logo.alpha = 1;
logo.color = 0xFFFFFFFF;
logo.offset.set(305.175, 228.475);
logo.antialiasing = false;
logo.animation.play("bump");
add(logo);
gf = ((function() { var s = new flixel.FlxSprite(920, 60); s.frames = Paths.getFrames("menus/titlescreen/gf"); s.animation.addByPrefix("dance", "gfDance", 24, true); s.animation.play("dance"); s.scale.set(0.45, 0.45); s.updateHitbox(); s.scrollFactor.set(); return s; })());
gf.visible = true;
gf.x = 920;
gf.y = 60;
gf.scrollFactor.set(0, 0);
gf.scale.set(0.45, 0.45);
gf.updateHitbox();
gf.alpha = 1;
gf.color = 0xFFFFFFFF;
gf.offset.set(198.275, 182.05);
gf.antialiasing = false;
gf.animation.play("dance");
add(gf);
titleText = new funkin.backend.FunkinText(0, 0, 0, "SOMETHING ENGINE", 60);
titleText.visible = true;
titleText.x = 330;
titleText.y = 100;
titleText.scrollFactor.set(1, 1);
titleText.scale.set(1, 1);
titleText.updateHitbox();
titleText.alpha = 1;
titleText.color = 0xFFFFD319;
titleText.antialiasing = false;
titleText.text = "SOMETHING ENGINE";
titleText.size = 60;
titleText.fieldWidth = 564;
titleText.borderStyle = Type.createEnumIndex(Type.resolveEnum("flixel.text.FlxTextBorderStyle"), 3);
titleText.borderColor = 0xFF000000;
titleText.borderSize = 3;
add(titleText);
demoButton = new funkin.backend.FunkinText(0, 0, 0, "CLICK ME - EDITED LIVE", 32);
demoButton.visible = true;
demoButton.x = 30;
demoButton.y = 620;
demoButton.scrollFactor.set(1, 1);
demoButton.scale.set(1, 1);
demoButton.updateHitbox();
demoButton.alpha = 1;
demoButton.color = 0xFF5BCEFA;
demoButton.antialiasing = false;
demoButton.text = "CLICK ME - EDITED LIVE";
demoButton.size = 32;
demoButton.fieldWidth = 422;
demoButton.borderStyle = Type.createEnumIndex(Type.resolveEnum("flixel.text.FlxTextBorderStyle"), 3);
demoButton.borderColor = 0xFF000000;
demoButton.borderSize = 1;
add(demoButton);
// code runner snippet
trace("main menu was customized by the state editor");

}

function __sneEditorUpdate(elapsed) {
if (FlxG.mouse.justPressed && FlxG.mouse.overlaps(demoButton)) {
var obj = demoButton;
FlxG.camera.flash(0xFFFFFFFF, 0.4); obj.text = "CUSTOM FUNCTIONALITY!"; obj.color = 0xFF7FFF00;
}
// update hook for demoButton
{
var obj = demoButton;
var t = FlxG.game.ticks / 300;
var s = 1 + 0.06 * Math.sin(t);
obj.scale.set(s, s);
}

}
// >>> END STATE EDITOR PATCH <<<
function postCreate() {
	__sneEditorPatch();
}
function update(elapsed) {
	__sneEditorUpdate(elapsed);
}

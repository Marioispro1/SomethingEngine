// >>> STATE EDITOR PATCH - regenerated on export, do not edit below <<<
// SNE-META {"mov":[],"rem":[],"trk":{"versionText":{"k":[{"a":0,"e":"quadInOut","t":0,"x":20,"y":680,"al":1,"sx":1,"sy":1},{"a":0,"e":"quadInOut","t":1.5,"x":1000,"y":40,"al":1,"sx":1,"sy":1},{"a":0,"e":"quadInOut","t":3,"x":20,"y":680,"al":1,"sx":1,"sy":1}],"m":1}},"hooks":{"demoButton":{"c":"FlxG.camera.flash(0xFFFFFFFF, 0.4); obj.text = \"CUSTOM FUNCTIONALITY!\"; obj.color = 0xFF7FFF00;","u":"var t = FlxG.game.ticks / 300;\nvar s = 1 + 0.06 * Math.sin(t);\nobj.scale.set(s, s);"}},"anim":{},"edit":["versionText","bg"],"objs":[{"c":"((function() { var s = new flixel.FlxSprite(20, 15); s.frames = Paths.getFrames(\"menus/titlescreen/logo\"); s.animation.addByPrefix(\"bump\", \"logo bumpin\", 24, false); s.animation.play(\"bump\"); s.scale.set(0.35, 0.35); s.updateHitbox(); s.scrollFactor.set(); return s; })())","t":"Dynamic","v":"logo"},{"c":"((function() { var s = new flixel.FlxSprite(920, 60); s.frames = Paths.getFrames(\"menus/titlescreen/gf\"); s.animation.addByPrefix(\"dance\", \"gfDance\", 24, true); s.animation.play(\"dance\"); s.scale.set(0.45, 0.45); s.updateHitbox(); s.scrollFactor.set(); return s; })())","t":"Dynamic","v":"gf"},{"c":"new funkin.backend.FunkinText(0, 0, 0, \"SOMETHING ENGINE\", 60)","t":"funkin.backend.FunkinText","v":"titleText"},{"c":"new funkin.backend.FunkinText(0, 0, 0, \"CLICK ME - EDITED LIVE\", 32)","t":"funkin.backend.FunkinText","v":"demoButton"}],"snip":[{"c":"trace(\"main menu was customized by the state editor\");","p":0}]}
var logo:Dynamic = null;
var gf:Dynamic = null;
var titleText:Dynamic = null;
var demoButton:Dynamic = null;
var __sneKeyTracks = [];
function __snePlayKeys(o, keys, mode) {
	var t = (mode == 3) ? (keys.length == 0 ? 0.0 : keys[keys.length-1].t) : 0.0;
	__sneKeyTracks.push({o: o, keys: keys, mode: mode, t: t, dir: (mode == 3) ? -1 : 1, playing: true});
}
function __sneAnimateKeys(elapsed) {
	for (tr in __sneKeyTracks) {
		var keys = tr.keys; var o = tr.o;
		if (o == null || o.exists == false || keys.length == 0 || tr.playing == false) continue;
		var dur = keys[keys.length-1].t;
		if (dur <= 0) continue;
		tr.t += elapsed * tr.dir;
		if (tr.mode == 1) { tr.t = tr.t % dur; if (tr.t < 0) tr.t += dur; }
		else if (tr.mode == 2) {
			if (tr.t > dur) { tr.t = dur - (tr.t - dur); tr.dir = -1; }
			if (tr.t < 0) { tr.t = -tr.t; tr.dir = 1; }
		} else {
			if (tr.t > dur) tr.t = dur;
			if (tr.t < 0) tr.t = 0;
		}
		var a = keys[0]; var b = keys[0]; var u = 1.0;
		if (tr.t > keys[0].t) {
			if (tr.t >= keys[keys.length-1].t) { a = keys[keys.length-1]; b = a; }
			else {
				for (i in 0...keys.length-1) {
					if (tr.t >= keys[i].t && tr.t <= keys[i+1].t) {
						a = keys[i]; b = keys[i+1];
						var span = b.t - a.t;
						u = span <= 0 ? 1.0 : (tr.t - a.t) / span;
						if (a.ease != null) u = a.ease(u);
						break;
					}
				}
			}
		}
		o.x = a.x + (b.x - a.x) * u;
		o.y = a.y + (b.y - a.y) * u;
		o.angle = a.angle + (b.angle - a.angle) * u;
		if (Reflect.hasField(o, "scale")) o.scale.set(a.sx + (b.sx - a.sx) * u, a.sy + (b.sy - a.sy) * u);
		if (Reflect.hasField(o, "alpha")) o.alpha = a.alpha + (b.alpha - a.alpha) * u;
	}
}
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
// keyframe track for versionText
__snePlayKeys(versionText, [{t:0,x:20,y:680,angle:0,sx:1,sy:1,alpha:1,ease:flixel.tweens.FlxEase.quadInOut}, {t:1.5,x:1000,y:40,angle:0,sx:1,sy:1,alpha:1,ease:flixel.tweens.FlxEase.quadInOut}, {t:3,x:20,y:680,angle:0,sx:1,sy:1,alpha:1,ease:flixel.tweens.FlxEase.quadInOut}], 1);

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
__sneAnimateKeys(elapsed);

}
// >>> END STATE EDITOR PATCH <<<
function postCreate() {
	__sneEditorPatch();
}
function update(elapsed) {
	__sneEditorUpdate(elapsed);
}

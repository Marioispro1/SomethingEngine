// >>> STATE EDITOR PATCH - regenerated on export, do not edit below <<<
var __sneKeyTracks = [];
function __snePlayKeys(o, keys, mode) {
	var t = (mode == 3) ? (keys.length == 0 ? 0.0 : keys[keys.length-1].t) : 0.0;
	__sneKeyTracks.push({o: o, keys: keys, mode: mode, t: t, dir: (mode == 3) ? -1 : 1});
}
function __sneAnimateKeys(elapsed) {
	for (tr in __sneKeyTracks) {
		var keys = tr.keys; var o = tr.o;
		if (o == null || o.exists == false || keys.length == 0) continue;
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
// keyframe track for versionText
__snePlayKeys(versionText, [{t:0,x:20,y:680,angle:0,sx:1,sy:1,alpha:1,ease:flixel.tweens.FlxEase.quadInOut}, {t:1.5,x:1000,y:40,angle:0,sx:1,sy:1,alpha:1,ease:flixel.tweens.FlxEase.quadInOut}, {t:3,x:20,y:680,angle:0,sx:1,sy:1,alpha:1,ease:flixel.tweens.FlxEase.quadInOut}], 1);

}

function __sneEditorUpdate(elapsed) {
__sneAnimateKeys(elapsed);

}
// >>> END STATE EDITOR PATCH <<<
function postCreate() {
	__sneEditorPatch();
}
function update(elapsed) {
	__sneEditorUpdate(elapsed);
}

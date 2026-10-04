package funkin.backend.system.console.inspector;

import openfl.Lib;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.backend.system.console.inspector.ConsoleInspector.InspectorObject;
import funkin.backend.system.console.inspector.ConsoleInspector.InspectorKeyframe;

#if IMGUI_ENABLED
import lime.tools.imgui.ImGuiFlags;
import lime.tools.imgui.ImGuiTypes;
import lime.tools.imgui.ImGuiPtr;
#end
#if foxlite
import foxlite.FoxScene;
import foxlite.group.FoxTypedGroup;
import foxlite.group.FoxObjectGroup;
import foxlite.FoxBasic;
import foxlite.FoxObject;
import foxlite.FoxModel;
import foxlite.mesh.buffer.FoxVertexBuffer;
import foxlite.mesh.buffer.FoxVertexBufferType;
#end

using funkin.backend.utils.ImGuiUtil;

class InspectorObjectProperties {

	#if IMGUI_ENABLED
	public var inspector:ConsoleInspector = null;
	public var isOpen = new ImGuiBoolPtr(true);
	public var forceLayout:Bool = false;
	var __edited:Bool = false;
	var renamePtr = new ImGuiStringPtr("");
	var fieldFilter = new ImGuiStringPtr("");
	var bakeSecsPtr = new ImGuiFloatPtr(3);
	var animNewName = new ImGuiStringPtr("newAnim");
	var animNewPrefix = new ImGuiStringPtr("");
	var animNewFrames = new ImGuiStringPtr("");
	var animNewFps = new ImGuiFloatPtr(24);
	var animNewLoop = new ImGuiBoolPtr(false);
	var keyTimePtr = new ImGuiFloatPtr(0.5);
	var presetIdx = new ImGuiIntPtr(0);

	static var HOOK_PRESET_NAMES:Array<String> = [
		"pulse scale", "spin", "follow mouse", "fade on hover", "shake", "pulse on beat", "bounce on click", "destroy on click"
	];
	static var HOOK_PRESET_CODES:Array<String> = [
		'var s = 1 + 0.06 * Math.sin(FlxG.game.ticks / 300);\nobj.scale.set(s, s);',
		'obj.angle += 180 * elapsed;',
		'obj.x = FlxG.mouse.getWorldPosition().x - obj.width / 2;\nobj.y = FlxG.mouse.getWorldPosition().y - obj.height / 2;',
		'obj.alpha = FlxG.mouse.overlaps(obj) ? 0.5 : 1.0;',
		'obj.offset.x = FlxG.random.float(-3, 3);\nobj.offset.y = FlxG.random.float(-3, 3);',
		'var bpm = funkin.backend.system.Conductor.bpm;\nvar beat = (funkin.backend.system.Conductor.songPosition / (60000 / bpm)) % 1;\nvar s = 1 + 0.12 * (1 - beat);\nobj.scale.set(s, s);',
		'FlxTween.tween(obj.scale, {x: 1.3, y: 1.3}, 0.08, {ease: FlxEase.quadOut})\n	.then(FlxTween.tween(obj.scale, {x: 1.0, y: 1.0}, 0.2, {ease: FlxEase.bounceOut}));',
		'obj.kill();'
	];
	var boolPool:ImGuiPtrPool<ImGuiBoolPtr> = new ImGuiPtrPool<ImGuiBoolPtr>(function() {return new ImGuiBoolPtr(false);});
	var floatPool:ImGuiPtrPool<ImGuiFloatPtr> = new ImGuiPtrPool<ImGuiFloatPtr>(function() {return new ImGuiFloatPtr(0.0);});
	var intPool:ImGuiPtrPool<ImGuiIntPtr> = new ImGuiPtrPool<ImGuiIntPtr>(function() {return new ImGuiIntPtr(0);});
	var float4Pool:ImGuiPtrPool<ImGuiFloat4Ptr> = new ImGuiPtrPool<ImGuiFloat4Ptr>(function() {return new ImGuiFloat4Ptr(0, 0, 0, 0);});
	var stringPool:ImGuiPtrPool<ImGuiStringPtr> = new ImGuiPtrPool<ImGuiStringPtr>(function() {return new ImGuiStringPtr("");});
	
	var mainImageViewer:ImGuiImageViewer = new ImGuiImageViewer();
	var imageViewerMap:Map<Int, ImGuiImageViewer> = [];

	var tableFlags = ImGuiTableFlags.SizingStretchSame | ImGuiTableFlags.Resizable | ImGuiTableFlags.BordersOuter | ImGuiTableFlags.BordersV | ImGuiTableFlags.RowBg;

	public function new() {}

	public function show(objectData:InspectorObject, justChanged:Bool) {
		__edited = false;
		boolPool.reset();
		floatPool.reset();
		intPool.reset();
		float4Pool.reset();
		stringPool.reset();

		if (justChanged) {
			mainImageViewer.viewReset = true;
			imageViewerMap.clear();
		}

		var selectedObject:Dynamic = objectData.obj;

		var wcond = forceLayout ? ImGuiCond.Always : ImGuiCond.FirstUseEver;
		forceLayout = false;
		ImGui.setNextWindowPos(ImGuiUtil.getWindowSpaceX() + Lib.application.window.width - 300, ImGuiUtil.getWindowSpaceY(), wcond);
		ImGui.setNextWindowSize(300, Lib.application.window.height, wcond);
		if (ImGui.begin("Object Properties", isOpen)) {
			ImGui.text(objectData.name + " - " + objectData.type);

			var basic:FlxBasic = selectedObject is FlxBasic ? cast selectedObject : null;
			if (basic != null) {
				if (inspector != null) {
					if (justChanged) renamePtr.value = inspector.editorNames.get(basic) ?? "";
					ImGui.setNextItemWidth(ImGui.getContentRegionAvail().x * 0.6);
					if (ImGui.inputTextWithHint("##rename", "name (editor)", renamePtr))
						inspector.renameObject(basic, renamePtr.value);
					if (ImGui.button("Order Up##props")) inspector.moveObject(basic, 1);
					ImGui.sameLine();
					if (ImGui.button("Order Down##props")) inspector.moveObject(basic, -1);
					ImGui.sameLine();
					if (ImGui.button("Duplicate##props")) inspector.duplicateObject(basic);
				}
				showFlxBasicProperties(basic);
				showKeyframes(basic);
				showCameraSection(basic);
				showRawFields(basic);
				showBehaviorProperties(basic);
				if (inspector != null && ImGui.button("Delete Object##props"))
					inspector.deleteInspectorObject(basic);
			}
			#if foxlite
			var foxbasic:FoxBasic = selectedObject is FoxBasic ? cast selectedObject : null;
			if (foxbasic != null) {
				showFoxBasicProps(foxbasic);
			}
			#end
		}
		ImGui.end();

		if (__edited && inspector != null && objectData.obj is FlxBasic)
			inspector.markEdited(cast objectData.obj);
	}

	function showBehaviorProperties(basic:FlxBasic) {
		if (inspector == null) return;
		if (ImGui.collapsingHeader("Behavior##props")) {
			var hooks = inspector.getOrCreateHooks(basic);
			var wid = ImGui.getContentRegionAvail().x;
			ImGui.text("On Click (hscript):");
			var click = stringPool.get();
			click.value = hooks.clickCode;
			if (ImGui.inputTextMultiline("##onClickCode", click, wid, 70))
				hooks.clickCode = click.value;
			ImGui.text("On Update (elapsed):");
			var upd = stringPool.get();
			upd.value = hooks.updateCode;
			if (ImGui.inputTextMultiline("##onUpdateCode", upd, wid, 70))
				hooks.updateCode = upd.value;
			ImGui.setNextItemWidth(wid);
			if (ImGui.combo("##hookPreset", presetIdx, HOOK_PRESET_NAMES)) {}
			if (ImGui.button("Insert into Update##preset")) {
				hooks.updateCode = StringTools.trim(hooks.updateCode + "\n" + HOOK_PRESET_CODES[presetIdx.value]);
				inspector.markEdited(basic);
			}
			ImGui.sameLine();
			if (ImGui.button("Insert into Click##preset")) {
				hooks.clickCode = StringTools.trim(hooks.clickCode + "\n" + HOOK_PRESET_CODES[presetIdx.value]);
				inspector.markEdited(basic);
			}
			ImGui.text("Use 'obj' for this object; state fields are also\nin scope (postCreate-style). Runs live.");
		}
	}

	function showFlxBasicProperties(basic:FlxBasic) {
		var object:FlxObject = basic is FlxObject ? cast basic : null;
		var sprite:FlxSprite = basic is FlxSprite ? cast basic : null;
		var text:FlxText = basic is FlxText ? cast basic : null;
		var funkinSprite:FunkinSprite = basic is FunkinSprite ? cast basic : null;
		var funkinText:FunkinText = basic is FunkinText ? cast basic : null;

		if (object != null) {
			showFlxObjectTransformProperties(object, sprite, funkinSprite, funkinText);
			if (sprite != null) {
				showFlxSpriteGraphicsProperties(sprite);
				showFlxSpriteAnimationProperties(sprite);
			}
			showFlxObjectPhysicsProperties(object);
			if (text != null) {
				showFlxTextProperties(text);
			}
		}

		if (ImGui.collapsingHeader("Basic")) {
			if (ImGui.beginTable("Basic##1", 2, tableFlags))
			{
				checkboxField("Active", "active", basic);
				checkboxField("Visible", "visible", basic);
				checkboxField("Alive", "alive", basic);
				checkboxField("Exists", "exists", basic);
				ImGui.endTable();
			}
		}
	}

	function showFlxObjectTransformProperties(object:FlxObject, ?sprite:FlxSprite = null, ?funkinSprite:FunkinSprite = null, ?funkinText:FunkinText = null) {
		if (ImGui.collapsingHeader("Transform")) {
			if (ImGui.beginTable("TransformTable", 2, tableFlags))
			{
				dragFloat2Field("Position", "x", "y", object);
				dragFloat2Field("Width/Height", "width", "height", object);
				if (sprite != null) {
					dragFloat2Field("Scale", "x", "y", sprite.scale, 0.05);
					dragFloat2Field("Origin", "x", "y", sprite.origin, 0.1);
					dragFloat2Field("Offset", "x", "y", sprite.offset);
				}
				dragFloatField("Angle", "angle", object);
				dragFloat2Field("Scroll Factor", "x", "y", object.scrollFactor, 0.05);
				if (funkinSprite != null || funkinText != null) {
					dragFloatField("Zoom Factor", "zoomFactor", object, 0.05);
					checkboxField("Enabled", "zoomFactorEnabled", object);
					dragFloatField("Angle Factor", "angleFactor", object, 0.05);
					checkboxField("Enabled", "angleFactorEnabled", object);

					dragFloat2Field("Skew", "x", "y", funkinSprite != null ? funkinSprite.skew : funkinText.skew, 0.05);
				}

				//TODO: scripting

				ImGui.endTable();
			}
		}
	}
	function showFlxSpriteGraphicsProperties(sprite:FlxSprite) {
		if (ImGui.collapsingHeader("Graphics")) {
			if (sprite.graphic != null) {
				ImGui.text("Key: " + sprite.graphic.key);
				var wid = ImGui.getContentRegionAvail().x;
				if (sprite.graphic.bitmap != null) {
					mainImageViewer.drawCanvas(wid, 300, ImTextureID.fromBitmapData(sprite.graphic.bitmap), sprite.graphic.width, sprite.graphic.height);
				}
			}

			if (ImGui.beginTable("GraphicsTable", 2, tableFlags))
			{
				colorField("Color", "color", sprite);
				sliderFloatField("Alpha", "alpha", sprite, 0, 1);

				checkboxField("Flip X", "flipX", sprite);
				checkboxField("Flip Y", "flipY", sprite);
				checkboxField("Antialiasing", "antialiasing", sprite);

				enumAbstractField("Blend Mode", "blend", sprite, "openfl.display.BlendMode");

				ImGui.endTable();
			}
		}
	}

	function showFlxSpriteAnimationProperties(sprite:FlxSprite) {
		if (ImGui.collapsingHeader("Animation")) {
			if (sprite.animation == null || sprite.animation.getAnimationList().length == 0) {
				ImGui.text("No animations.");
			} else {
				ImGui.text("Playing: " + (sprite.animation.curAnim != null ? sprite.animation.curAnim.name : "none"));
				if (ImGui.beginTable("AnimTable", 5, tableFlags)) {
					for (a in sprite.animation.getAnimationList()) {
						ImGui.pushIDFromStr(a.name);
						ImGui.tableNextRow();
						ImGui.tableSetColumnIndex(0);
						ImGui.text(a.name);
						ImGui.tableSetColumnIndex(1);
						var wid = ImGui.getContentRegionAvail().x;
						ImGui.setNextItemWidth(wid);
						var fs = stringPool.get();
						fs.value = a.frames.join(",");
						if (ImGui.inputTextWithHint("##frames", "0,1,2", fs)) {
							var parsed:Array<Int> = [];
							for (p in fs.value.split(",")) {
								var v = Std.parseInt(StringTools.trim(p));
								if (v != null) parsed.push(v);
							}
							if (parsed.length > 0) { a.frames = parsed; __edited = true; if (inspector != null) inspector.markEdited(sprite); }
						}
						ImGui.tableSetColumnIndex(2);
						ImGui.setNextItemWidth(50);
						var fr = floatPool.get();
						fr.value = a.frameRate;
						if (ImGui.dragFloat("##fps", fr, 0.5, 0, 0, "%.0f")) { a.frameRate = fr.value; __edited = true; if (inspector != null) inspector.markEdited(sprite); }
						ImGui.tableSetColumnIndex(3);
						var lp = boolPool.get();
						lp.value = a.looped;
						if (ImGui.checkbox("##loop", lp)) { a.looped = lp.value; __edited = true; if (inspector != null) inspector.markEdited(sprite); }
						ImGui.tableSetColumnIndex(4);
						if (ImGui.button("Play")) sprite.animation.play(a.name, true);
						ImGui.sameLine();
						if (ImGui.button("Del")) {
							sprite.animation.remove(a.name);
							if (inspector != null) inspector.recordAnimOp(sprite, 'animation.remove("${a.name}")');
						}
						ImGui.popID();
					}
					ImGui.endTable();
				}
			}

			ImGui.separator();
			ImGui.text("Add animation:");
			ImGui.setNextItemWidth(90); ImGui.inputTextWithHint("##animName", "name", animNewName);
			ImGui.sameLine(); ImGui.setNextItemWidth(90); ImGui.inputTextWithHint("##animPrefix", "prefix", animNewPrefix);
			ImGui.sameLine(); ImGui.setNextItemWidth(70); ImGui.inputTextWithHint("##animFrames", "0,1,2", animNewFrames);
			ImGui.setNextItemWidth(90); ImGui.dragFloat("fps##animFps", animNewFps, 0.5, 0, 0, "%.0f");
			ImGui.sameLine(); ImGui.checkbox("loop##animLoop", animNewLoop);
			if (ImGui.button("Add Animation##animAdd")) {
				var name = animNewName.value;
				var prefix = animNewPrefix.value;
				var framesTxt = animNewFrames.value;
				var fps = animNewFps.value;
				var looped = animNewLoop.value;
				if (name != null && name.length > 0) {
					if (framesTxt != null && framesTxt.length > 0) {
						var parsed:Array<Int> = [];
						for (p in framesTxt.split(",")) {
							var v = Std.parseInt(StringTools.trim(p));
							if (v != null) parsed.push(v);
						}
						if (parsed.length > 0) {
							sprite.animation.add(name, parsed, fps, looped);
							if (inspector != null) inspector.recordAnimOp(sprite, 'animation.add("${ConsoleInspector.escapeHaxe(name)}", ${parsed.toString()}, $fps, $looped)');
						}
					} else {
						sprite.animation.addByPrefix(name, prefix, fps, looped);
						if (inspector != null) inspector.recordAnimOp(sprite, 'animation.addByPrefix("${ConsoleInspector.escapeHaxe(name)}", "${ConsoleInspector.escapeHaxe(prefix)}", $fps, $looped)');
					}
					__edited = true;
				}
			}
		}
	}

	function showKeyframes(basic:FlxBasic) {
		if (inspector == null) return;
		if (!ImGui.collapsingHeader("Keyframes##props")) return;
		var tr = inspector.getOrCreateTrack(basic);

		// playback controls
		if (ImGui.button(tr.playing ? "Pause##kf" : "Play##kf")) inspector.playTrack(tr);
		ImGui.sameLine();
		ImGui.setNextItemWidth(95);
		var modeIdx = intPool.get();
		modeIdx.value = tr.mode;
		if (ImGui.combo("##kfMode", modeIdx, ["Once", "Loop", "PingPong", "Reverse", "Beats"])) { tr.mode = modeIdx.value; inspector.syncPatchTrack(tr); inspector.markEdited(basic); }
		ImGui.sameLine();
		ImGui.text('t=' + FlxMath.roundDecimal(tr.t, 2) + "s");

		// playhead scrub slider
		if (tr.keys.length > 0) {
			var scrub = floatPool.get();
			scrub.value = tr.t;
			ImGui.setNextItemWidth(-1);
			if (ImGui.sliderFloat("##kfScrub", scrub, 0, Math.max(inspector.trackDuration(tr), 0.001), "t=%.2fs")) {
				tr.t = scrub.value;
				if (tr.patchTrack != null) tr.patchTrack.t = tr.t;
				if (!tr.playing) inspector.applyTrack(basic, tr);
			}
		}

		// key capture row
		ImGui.setNextItemWidth(70);
		ImGui.dragFloat("time##kfAddTime", keyTimePtr, 0.01, 0, 0, "%.2f");
		ImGui.sameLine();
		if (ImGui.smallButton("@t##kfSetNow")) keyTimePtr.value = FlxMath.roundDecimal(tr.t, 2);
		if (ImGui.isItemHovered()) ImGui.setTooltip("set the time field to the current playhead");
		ImGui.sameLine();
		if (ImGui.button("Add Key##kf")) {
			inspector.addKeyframe(basic, keyTimePtr.value);
			keyTimePtr.value = FlxMath.roundDecimal(inspector.trackDuration(tr) + 0.5, 2);
		}
		if (ImGui.isItemHovered()) ImGui.setTooltip("snapshot the object's transform at this time");
		ImGui.sameLine();
		var armed = inspector.clickCaptureFor == basic;
		if (ImGui.button(armed ? "Click scene!##kf" : "Add @ Mouse##kf")) inspector.armClickCapture(basic);
		if (ImGui.isItemHovered()) ImGui.setTooltip("arm, then click in the game view to place a position keyframe");
		ImGui.sameLine();
		if (tr.sel >= 0 && tr.sel < tr.keys.length && ImGui.button("Del Key##kf")) {
			tr.keys.splice(tr.sel, 1);
			tr.sel = -1;
			inspector.syncPatchTrack(tr);
			inspector.markEdited(basic);
		}
		ImGui.sameLine();
		if (tr.sel >= 0 && tr.sel < tr.keys.length && ImGui.button("Dup##kf")) {
			var k = tr.keys[tr.sel];
			var nk:InspectorKeyframe = {t: k.t + 0.25, x: k.x, y: k.y, angle: k.angle, scaleX: k.scaleX, scaleY: k.scaleY, alpha: k.alpha, ease: k.ease};
			tr.keys.push(nk);
			inspector.sortTrack(tr);
			tr.sel = tr.keys.indexOf(nk);
			inspector.syncPatchTrack(tr);
			inspector.markEdited(basic);
		}
		if (ImGui.isItemHovered()) ImGui.setTooltip("duplicate the selected keyframe 0.25s later");
		ImGui.sameLine();
		if (tr.keys.length > 0 && ImGui.button("Clear##kf")) {
			tr.keys = [];
			tr.sel = -1;
			tr.playing = false;
			tr.t = 0;
			inspector.syncPatchTrack(tr);
			inspector.markEdited(basic);
		}
		if (ImGui.isItemHovered()) ImGui.setTooltip("remove every keyframe in this track");
		if (tr.keys.length > 0 && ImGui.button("Snap keys to beats##kf")) {
			var beat = (funkin.backend.system.Conductor.bpm > 0) ? 60.0 / funkin.backend.system.Conductor.bpm : 0.25;
			for (k in tr.keys) k.t = FlxMath.roundDecimal(Math.round(k.t / beat) * beat, 3);
			inspector.sortTrack(tr);
			inspector.syncPatchTrack(tr);
			inspector.markEdited(basic);
		}
		if (ImGui.isItemHovered()) ImGui.setTooltip("round all key times to the nearest beat of the current Conductor.bpm");
		ImGui.sameLine();
		ImGui.setNextItemWidth(52);
		ImGui.dragFloat("##kfBakeSecs", bakeSecsPtr, 0.1, 0.5, 30, "%.1fs");
		ImGui.sameLine();
		var isBaking = inspector.baking != null && inspector.baking.obj == basic;
		if (ImGui.button(isBaking ? "Baking!##kf" : "Bake##kf") && inspector.baking == null)
			inspector.bakeMotion(basic, bakeSecsPtr.value);
		if (ImGui.isItemHovered()) ImGui.setTooltip("record this object's live motion for N seconds into keyframes (replaces the track)");

		// timeline row
		if (tr.keys.length > 0) {
			inspector.sortTrack(tr);
			ImGui.text("Keys:");
			ImGui.sameLine();
			for (i => k in tr.keys) {
				ImGui.pushIDFromInt(i);
				var lbl = 'K${i}@${FlxMath.roundDecimal(k.t, 1)}' + (tr.sel == i ? "*" : "");
				if (ImGui.smallButton(lbl)) tr.sel = i;
				if (ImGui.isItemHovered()) ImGui.setTooltip('t=${k.t} pos=${Math.round(k.x)},${Math.round(k.y)} ease=${k.ease}');
				ImGui.sameLine();
				ImGui.popID();
			}
			ImGui.text("");
		}

		// selected keyframe editor
		if (tr.sel >= 0 && tr.sel < tr.keys.length) {
			var k = tr.keys[tr.sel];
			ImGui.separatorText('Keyframe ${tr.sel}');
			var edited = false;
			if (ImGui.beginTable("KeyTable", 2, tableFlags)) {
				if (dragFloatField("Time", "t", k, 0.01)) edited = true;
				if (dragFloat2Field("Pos", "x", "y", k, 1)) edited = true;
				if (dragFloatField("Angle", "angle", k, 1)) edited = true;
				if (dragFloat2Field("Scale", "scaleX", "scaleY", k, 0.01)) edited = true;
				if (dragFloatField("Alpha", "alpha", k, 0.01)) edited = true;
				ImGui.tableNextRow();
				ImGui.tableSetColumnIndex(0);
				ImGui.text("Ease (to next)");
				ImGui.tableSetColumnIndex(1);
				ImGui.setNextItemWidth(ImGui.getContentRegionAvail().x);
				var names = inspector.getEaseNames();
				var ei = intPool.get();
				ei.value = names.indexOf(k.ease);
				if (ei.value < 0) ei.value = 0;
				if (ImGui.combo("##kfease", ei, names)) {
					k.ease = names[ei.value];
					edited = true;
				}
				ImGui.endTable();
			}
			if (edited) {
				inspector.sortTrack(tr);
				tr.sel = tr.keys.indexOf(k);
				inspector.syncPatchTrack(tr);
				inspector.markEdited(basic);
			}
			if (ImGui.button("Snap pose##kf")) {
				var nk = inspector.snapshotKey(basic, k.t);
				k.x = nk.x; k.y = nk.y; k.angle = nk.angle;
				k.scaleX = nk.scaleX; k.scaleY = nk.scaleY; k.alpha = nk.alpha;
				inspector.syncPatchTrack(tr);
				inspector.markEdited(basic);
			}
			ImGui.sameLine();
			if (ImGui.button("Preview key##kf")) {
				tr.t = k.t;
				if (tr.patchTrack != null) tr.patchTrack.t = tr.t;
				inspector.applyTrack(basic, tr);
			}
		}
	}

	function showCameraSection(basic:FlxBasic) {
		if (inspector == null || !ImGui.collapsingHeader("Camera##props")) return;
		var camNames:Array<String> = [];
		for (i => c in FlxG.cameras.list) camNames.push('Camera $i' + (i == 0 ? ' (default)' : ''));
		if (camNames.length == 0) { ImGui.text("No cameras."); return; }
		var ci = intPool.get();
		ci.value = FlxG.cameras.list.indexOf(basic.camera);
		if (ci.value < 0) ci.value = 0;
		ImGui.setNextItemWidth(-1);
		if (ImGui.combo("Draw on##camPick", ci, camNames)) {
			basic.cameras = [FlxG.cameras.list[ci.value]];
			__edited = true;
			inspector.markEdited(basic);
		}
		if (ImGui.isItemHovered()) ImGui.setTooltip("which camera renders this object");
	}

	function showRawFields(basic:FlxBasic) {
		if (ImGui.collapsingHeader("All Fields (raw)##props")) {
			var filter = fieldFilter.value;
			ImGui.inputText("Filter##fields", fieldFilter);
			if (ImGui.beginTable("FieldsTable", 2, tableFlags)) {
				var cls = Type.getClass(basic);
				var fields:Array<String> = cls != null ? Type.getInstanceFields(cls) : [];
				fields.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
				var count = 0;
				for (f in fields) {
					if (filter != null && filter.length > 0 && f.indexOf(filter) == -1) continue;
					var v:Dynamic = null;
					var ok = try { v = Reflect.getProperty(basic, f); true; } catch(e) { false; }
					if (!ok) continue;
					if (++count > 150) {
						ImGui.tableNextRow();
						ImGui.tableSetColumnIndex(0);
						ImGui.text("... truncated");
						break;
					}
					if (Reflect.isFunction(v)) continue;
					if (v is Bool) checkboxField(f, f, basic);
					else if (v is Int || v is Float) dragFloatField(f, f, basic, 0.25);
					else if (v is String) inputTextField(f, f, basic);
					else {
						ImGui.tableNextRow();
						ImGui.tableSetColumnIndex(0);
						ImGui.text(f);
						ImGui.tableSetColumnIndex(1);
						ImGui.text(Std.string(v));
					}
				}
				ImGui.endTable();
			}
		}
	}

	function showFlxObjectPhysicsProperties(object:FlxObject) {
		if (ImGui.collapsingHeader("Physics")) {
			if (ImGui.beginTable("PhysicsTable", 2, tableFlags))
			{
				checkboxField("Moves", "moves", object);
				checkboxField("Immovable", "immovable", object);
				checkboxField("Solid", "solid", object);

				dragFloat2Field("Velocity", "x", "y", object.velocity);
				dragFloat2Field("Acceleration", "x", "y", object.acceleration);
				dragFloat2Field("Drag", "x", "y", object.drag);
				dragFloatField("Mass", "mass", object);
				dragFloatField("Elasticity", "elasticity", object);
				dragFloatField("Angular Velocity", "angularVelocity", object);
				dragFloatField("Angular Acceleration", "angularAcceleration", object);
				dragFloatField("Angular Drag", "angularDrag", object);
				dragFloat2Field("Max Velocity", "x", "y", object.maxVelocity);
				dragFloatField("Max Angular", "maxAngular", object);
				ImGui.endTable();
			}
		}
	}

	function showFlxTextProperties(text:FlxText) {
		if (ImGui.collapsingHeader("Text")) {
			if (ImGui.beginTable("TextTable", 2, tableFlags))
			{
				inputTextFieldMultiline("Text", "text", text, 400, 200);
				dragIntField("Size", "size", text);
				inputTextField("Font", "font", text);
				dragFloat2Field("Field Width/Height", "fieldWidth", "fieldHeight", text);
				enumAbstractField("Alignment", "alignment", text, "flixel.text.FlxTextAlign");
				dragFloatField("Letter Spacing", "letterSpacing", text);

				colorField("Border Color", "borderColor", text);

				{
					ImGui.tableNextRow();
					ImGui.tableSetColumnIndex(0);
					ImGui.text("Border Style");
					ImGui.tableSetColumnIndex(1);
					var wid = ImGui.getContentRegionAvail().x;
					ImGui.setNextItemWidth(wid);

					var index = intPool.get();
					var list = ["NONE", "SHADOW", "SHADOW_XY", "OUTLINE", "OUTLINE_FAST", "OUTLINE_CARDINAL"];
					switch(text.borderStyle) { //not that easy to automate due to args on SHADOW_XY
						case NONE:
							index.value = 0;
						case SHADOW:
							index.value = 1;
						case SHADOW_XY(offsetX, offsetY):
							index.value = 2;
						case OUTLINE:
							index.value = 3;
						case OUTLINE_FAST:
							index.value = 4;
						case OUTLINE_CARDINAL:
							index.value = 5;
					}			
					if (ImGui.combo("##Border StyleborderStyle", index, list)) {
						switch(index.value) {
							case 0:
								text.borderStyle = NONE;
							case 1:
								text.borderStyle = SHADOW;
							case 2:
								text.borderStyle = SHADOW_XY(0, 0);
							case 3:
								text.borderStyle = OUTLINE;
							case 4:
								text.borderStyle = OUTLINE_FAST;
							case 5:
								text.borderStyle = OUTLINE_CARDINAL;
						}
						__edited = true;
					}

					switch(text.borderStyle) {
						case SHADOW_XY(offsetX, offsetY):
							//todo
						default:
					}	
				}
				dragFloatField("Border Size", "borderSize", text);
				dragFloatField("Border Quality", "borderQuality", text);

				checkboxField("Bold", "bold", text);
				checkboxField("Underline", "underline", text);
				checkboxField("Italic", "italic", text);
				checkboxField("Word Wrap", "wordWrap", text);
				checkboxField("Auto Size", "autoSize", text);
				ImGui.endTable();
			}				
		}
	}

	#if foxlite
	function showFoxBasicProps(basic:FoxBasic) {
		var object:FoxObject = basic is FoxObject ? cast basic : null;
		var model:FoxModel = basic is FoxModel ? cast basic : null;

		if (object != null) {
			ImGui.separator();
			showFoxObjectTransformProperties(object);
			if (model != null) showFoxModelGraphicsProperties(model);
		}

		if (ImGui.collapsingHeader("Basic")) {
			if (ImGui.beginTable("Basic##1", 2, tableFlags))
			{
				textField("Name", basic.name);
				checkboxField("Active", "active", basic);
				checkboxField("Visible", "visible", basic);
				ImGui.endTable();
			}
		}
	}

	function showFoxObjectTransformProperties(object:FoxObject) {
		if (ImGui.collapsingHeader("Transform")) {
			if (ImGui.beginTable("TransformTable", 2, tableFlags))
			{
				var dirty = false;
				if (dragFloat3Field("Position", "x", "y", "z", object.position, 0.05)) dirty = true;
				if (dragFloat3Field("Rotation", "angleX", "angleY", "angleZ", object)) dirty = true;
				if (dragFloat3Field("Scale", "x", "y", "z", object.scale, 0.05)) dirty = true;
				if (dirty) {
					object.update(0.0); //force update transform
				}
				ImGui.endTable();
			}
		}
	}

	function showFoxModelGraphicsProperties(model:FoxModel) {
		if (model != null && ImGui.collapsingHeader("Graphics")) {
			if (ImGui.beginTable("Model##1", 2, tableFlags))
			{
				checkboxField("Frustrum Culling", "frustumCulling", model);
				checkboxField("Cast Shadows", "castShadows", model);
				checkboxField("Cast Colored Shadows", "castColoredShadows", model);
				ImGui.endTable();
			}

			ImGui.separator();
			
			for (i => mesh in model.meshes) {
				var nodeID = "mesh" + i;
				if (ImGui.treeNode(nodeID, mesh.assetsKey != null ? mesh.assetsKey : "Mesh " + i)) {
					ImGui.pushIDFromInt(i);
					if (ImGui.beginTable("MeshTable" + i, 2, tableFlags))
					{
						textField("Key", mesh.assetsKey);
						textField("Is Copy", mesh.__isCopy ? "True" : "False");
						@:privateAccess {
							final vertexBuffer  = mesh.buffers[FoxVertexBufferType.VERTICES],
								  uvBuffer      = mesh.buffers[FoxVertexBufferType.UVS],
								  normalBuffer  = mesh.buffers[FoxVertexBufferType.NORMALS],
								  tangentBuffer = mesh.buffers[FoxVertexBufferType.TANGENTS],
								  colorBuffer   = mesh.buffers[FoxVertexBufferType.COLORS],
								  boneWeights   = mesh.buffers[FoxVertexBufferType.WEIGHTS],
								  boneIndices   = mesh.buffers[FoxVertexBufferType.BONE_INDICES],
								  indexBuffer   = mesh.buffers[FoxVertexBufferType.INDICES];
							// this should be better
							inline function stride(buffer:FoxVertexBuffer) return buffer.components * buffer.bytesPerElement;
							if (vertexBuffer != null) textField("Vertex Buffer", 	  "Num: " + vertexBuffer.count  + ", Stride: " + stride(vertexBuffer)  + ", Size: " + (vertexBuffer.count  * stride(vertexBuffer) ));
							if (uvBuffer != null) textField("UV Buffer", 			  "Num: " + uvBuffer.count      + ", Stride: " + stride(uvBuffer)      + ", Size: " + (uvBuffer.count      * stride(uvBuffer)     ));
							if (indexBuffer != null) textField("Index Buffer",        "Num: " + indexBuffer.count   				    				   + ", Size: " + (indexBuffer.count   * stride(indexBuffer)  ));
							if (normalBuffer != null) textField("Normal Buffer",      "Num: " + normalBuffer.count  + ", Stride: " + stride(normalBuffer)  + ", Size: " + (normalBuffer.count  * stride(normalBuffer) ));
							if (tangentBuffer != null) textField("Tangent Buffer",    "Num: " + tangentBuffer.count + ", Stride: " + stride(tangentBuffer) + ", Size: " + (tangentBuffer.count * stride(tangentBuffer)));
							if (colorBuffer != null) textField("Color Buffer", 		  "Num: " + colorBuffer.count   + ", Stride: " + stride(colorBuffer)   + ", Size: " + (colorBuffer.count   * stride(colorBuffer)  ));
							if (boneWeights != null) textField("Bone Weights Buffer", "Num: " + boneWeights.count   + ", Stride: " + stride(boneWeights)   + ", Size: " + (boneWeights.count   * stride(boneWeights)  ));
							if (boneIndices != null) textField("Bone Indices Buffer", "Num: " + boneIndices.count   + ", Stride: " + stride(boneIndices)   + ", Size: " + (boneIndices.count   * stride(boneIndices)  ));
						}
						ImGui.endTable();
					}
					
					if (mesh.material != null) {
						ImGui.separatorText("Material");
						if (ImGui.beginTable("MaterialTable" + i, 2, tableFlags))
						{
							textField("Name", mesh.material.name);
							textField("Key", mesh.material.assetsKey);
							dragIntField("Render Priority", "renderPriority", mesh.material);
							checkboxField("Depth Test", "depthTest", mesh.material);
							enumAbstractField("Depth Func", "depthFunc", mesh.material, "foxlite.material.FoxDepthCompareMode");
							checkboxField("Depth Write", "depthWrite", mesh.material);
							checkboxField("Color Write", "colorWrite", mesh.material);
							enumAbstractField("Culling", "culling", mesh.material, "foxlite.material.FoxTriangleFace");
							enumAbstractField("Shadow Culling", "shadowCulling", mesh.material, "foxlite.material.FoxTriangleFace");
							enumAbstractField("Blend Mode", "blendMode", mesh.material, "foxlite.material.FoxBlendMode");
							sliderFloatField("Alpha Scissor", "alphaScissor", mesh.material, 0, 1);
							ImGui.endTable();
						}



						if (ImGui.treeNode(nodeID + "textures", "Textures")) {
							for (texName => tex in mesh.material.textures) {
								ImGui.separatorText(texName);
								var wid = ImGui.getContentRegionAvail().x;
								@:privateAccess
								var id:Int = tex.glTexture.__getTexture().id;
								if (id != 0) {
									if (!imageViewerMap.exists(id)) imageViewerMap.set(id, new ImGuiImageViewer());
									imageViewerMap.get(id).drawCanvas(wid, 300, new ImTextureID(id), tex.width, tex.height);
								}
							}
							ImGui.treePop();
						}
						if (ImGui.treeNode(nodeID + "params", "Parameters")) {
							if (ImGui.beginTable("ParamsTable" + i, 2, tableFlags)) {
								for (name => value in mesh.material.params) {
									textField(name, Std.string(value));
								}
								ImGui.endTable();
							}
							ImGui.treePop();
						}						
					}
					ImGui.popID();
					ImGui.treePop();
				}
			}
		}
	}

	#end

	////////////////////////////////////

	inline function dragFloatField(name:String, field:String, object:Dynamic, speed:Float = 1.0, min:Float = 0.0, max:Float = 0.0, format:String = "%.3f", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);

		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var f = floatPool.get();
		f.value = Reflect.getProperty(object, field);
		if (ImGui.dragFloat("##" + name + field, f, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field, f.value);
			didChange = true;
			__edited = true;
		}
		return didChange;
	}
	inline function dragFloat2Field(name:String, field:String, field2:String, object:Dynamic, speed:Float = 1.0, min:Float = 0.0, max:Float = 0.0, format:String = "%.3f", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x / 2;
		ImGui.setNextItemWidth(wid);

		var f = floatPool.get();
		f.value = Reflect.getProperty(object, field);
		if (ImGui.dragFloat("##" + name + field, f, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field, f.value);
			didChange = true;
			__edited = true;
		}

		ImGui.sameLine();
		ImGui.setNextItemWidth(wid);

		var f2 = floatPool.get();
		f2.value = Reflect.getProperty(object, field2);
		if (ImGui.dragFloat("##" + name + field2, f2, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field2, f2.value);
			didChange = true;
			__edited = true;
		}
		return didChange;
	}
	inline function dragFloat3Field(name:String, field:String, field2:String, field3:String, object:Dynamic, speed:Float = 1.0, min:Float = 0.0, max:Float = 0.0, format:String = "%.3f", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x / 3;
		ImGui.setNextItemWidth(wid);

		var f = floatPool.get();
		f.value = Reflect.getProperty(object, field);
		if (ImGui.dragFloat("##" + name + field, f, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field, f.value);
			didChange = true;
			__edited = true;
		}

		ImGui.sameLine();
		ImGui.setNextItemWidth(wid);

		var f2 = floatPool.get();
		f2.value = Reflect.getProperty(object, field2);
		if (ImGui.dragFloat("##" + name + field2, f2, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field2, f2.value);
			didChange = true;
			__edited = true;
		}

		ImGui.sameLine();
		ImGui.setNextItemWidth(wid);

		var f3 = floatPool.get();
		f3.value = Reflect.getProperty(object, field3);
		if (ImGui.dragFloat("##" + name + field3, f3, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field3, f3.value);
			didChange = true;
			__edited = true;
		}
		return didChange;
	}
	inline function sliderFloatField(name:String, field:String, object:Dynamic, min:Float, max:Float, format:String = "%.3f", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var f = floatPool.get();
		f.value = Reflect.getProperty(object, field);
		if (ImGui.sliderFloat("##" + name + field, f, min, max, format, flags)) {
			Reflect.setProperty(object, field, f.value);
			didChange = true;
			__edited = true;
		}
		return didChange;
	}
	inline function dragIntField(name:String, field:String, object:Dynamic, speed:Float = 1.0, min:Int = 0, max:Int = 0, format:String = "%d", flags:ImGuiSliderFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var i = intPool.get();
		i.value = Reflect.getProperty(object, field);
		if (ImGui.dragInt("##" + name + field, i, speed, min, max, format, flags)) {
			Reflect.setProperty(object, field, i.value);
			didChange = true;
			__edited = true;
		}
		return didChange;
	}
	inline function checkboxField(name:String, field:String, object:Dynamic) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var b = boolPool.get(); b.value = Reflect.getProperty(object, field); 
		if (ImGui.checkbox("##" + name + field, b)) {
			Reflect.setProperty(object, field, b.value);
			didChange = true;
			__edited = true;
		}
		return didChange;
	}
	inline function textField(name:String, text:String) {
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		ImGui.text(text);
	}
	inline function colorField(name:String, field:String, object:Dynamic, flags:ImGuiColorEditFlags = 0) {
		var didChange:Bool = false;
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var color:FlxColor = Reflect.getProperty(object, field);
		var float4 = float4Pool.get();
		float4.values[0] = color.redFloat;
		float4.values[1] = color.greenFloat;
		float4.values[2] = color.blueFloat;
		float4.values[3] = color.alphaFloat;
		if (ImGui.colorEdit4("##" + name + field, float4, flags)) {
			Reflect.setProperty(object, field, FlxColor.fromRGBFloat(float4.values[0], float4.values[1], float4.values[2], float4.values[3]));
			didChange = true;
			__edited = true;
		}
		return didChange;
	}
	inline function inputTextField(name:String, field:String, object:Dynamic, flags:ImGuiInputTextFlags = 0) {

		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);

		var wid = ImGui.getContentRegionAvail().x;
		ImGui.setNextItemWidth(wid);

		var s = stringPool.get();
		s.value = Reflect.getProperty(object, field);
		if (ImGui.inputText("##" + name + field, s, flags)) {
			Reflect.setProperty(object, field, s.value);
		}
	}
	inline function inputTextFieldMultiline(name:String, field:String, object:Dynamic, width:Float, height:Float, flags:ImGuiInputTextFlags = 0) {
		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);
		var s = stringPool.get();
		s.value = Reflect.getProperty(object, field);
		if (ImGui.inputTextMultiline("##" + name + field, s, width, height, flags)) {
			Reflect.setProperty(object, field, s.value);
		}
	}
	inline function enumFieldString(name:String, field:String, object:Dynamic, list:Array<String>) { //not working
		var index = intPool.get();
		index.value = list.indexOf(Std.string(Reflect.getProperty(object, field)));
		if (ImGui.combo(name + "##" + field, index, list)) {
			Reflect.setProperty(object, field, list[index.value]);
			__edited = true;
		}
	}
	inline function enumAbstractField(name:String, field:String, object:Dynamic, type:String) {

		ImGui.tableNextRow();
		ImGui.tableSetColumnIndex(0);
		ImGui.text(name);
		ImGui.tableSetColumnIndex(1);

		var t = Type.resolveClass(type + "_HSC");
		if (t != null) {
			var wid = ImGui.getContentRegionAvail().x;
			ImGui.setNextItemWidth(wid);

			var curValue = Reflect.getProperty(object, field);
			var index = intPool.get();

			var fields = Type.getClassFields(t);
			var filteredFields:Array<String> = [];
			for (f in fields) {
				if (!f.startsWith("from") && !f.startsWith("to")) filteredFields.push(f);
			}
			index.value = -1;
			for (i => f in filteredFields) {
				if (Reflect.getProperty(t, f) == curValue) index.value = i;
			}

			if (ImGui.combo("##" + name + field, index, filteredFields)) {
				Reflect.setProperty(object, field, Reflect.getProperty(t, filteredFields[index.value]));
				__edited = true;
			}

		}
	}
	#end
}

#if IMGUI_ENABLED
//quick class that handles imgui pointers for temp values
class ImGuiPtrPool<T> {
	var members:Array<T> = [];
	var used:Int = 0;
	var constructor:Void->T;
	public function new(constructor:Void->T) {
		this.constructor = constructor;
	}
	public function reset() {
		used = 0;
	}
	public function get():T {
		if (used >= members.length) {
			members.push(constructor());
		}
		var obj = members[used];
		used++;
		return obj;
	}
}

//https://github.com/ocornut/imgui/blob/master/imgui_demo.cpp#L841
class ImGuiImageViewer {
	var gridEnabled:ImGuiBoolPtr = new ImGuiBoolPtr(false);
	public var viewReset:Bool = true;
	var viewOffsetX:Float = 0;
	var viewOffsetY:Float = 0;
	var zoom:ImGuiFloatPtr = new ImGuiFloatPtr(10.0);
	var zoom100:ImGuiFloatPtr = new ImGuiFloatPtr(10.0);
	var zoomMin:Float = 0.1;
	var zoomMax:Float = 10000;

	public function new() {}

	public function drawOptions() {
		ImGui.setNextItemWidth(150);
		zoom100.value = zoom.value * 100;
		if (ImGui.dragFloat("Zoom", zoom100, 5.0, zoomMin * 100.0, zoomMax * 100, "%.0f%%", ImGuiSliderFlags.AlwaysClamp))
			zoom.value = zoom100.value / 100.0;
	}

	public function drawCanvas(canvas_size_x:Float, canvas_size_y:Float, image_tex_ref:ImTextureID, image_w:Int, image_h:Int) {
		var drawList = ImGui.getWindowDrawList();
		ImGui.invisibleButton("##Canvas", canvas_size_x, canvas_size_y);
		var canvas_min = ImGui.getItemRectMin();
		var canvas_max = ImGui.getItemRectMax();

		if (viewReset) {
			var xZoom = canvas_size_x / image_w;
			var yZoom = canvas_size_y / image_h;
			zoom.value = (image_w > image_h ? xZoom : yZoom);
			viewOffsetX = (canvas_size_x * 0.5 / xZoom) - 0.5;
			viewOffsetY = (canvas_size_y * 0.5 / yZoom) - 0.5;
		}
		viewReset = false;

		if (ImGui.setItemKeyOwner(ImGuiKey.MouseWheelY)) {
			if (ImGuiIO.mouseWheel != 0.0) {
				zoom.value = FlxMath.bound(zoom.value * (1.0 + ImGuiIO.mouseWheel * 0.10), zoomMin, zoomMax);
			}
		}
		var zoomValue = zoom.value;
		if (ImGui.isItemActive() && ImGui.isMouseDragging(0)) {
			viewOffsetX -= ImGuiIO.mouseDeltaX / zoomValue;
			viewOffsetY -= ImGuiIO.mouseDeltaY / zoomValue;
		}

		var minX:Float = Std.int((canvas_min.x - (viewOffsetX * zoomValue)) + (canvas_size_x * 0.5));
		var minY:Float = Std.int((canvas_min.y - (viewOffsetY * zoomValue)) + (canvas_size_y * 0.5));
		var maxX:Float = Std.int(minX + image_w * zoomValue);
		var maxY:Float = Std.int(minY + image_h * zoomValue);
		drawList.addRect([canvas_min.x - 1.0, canvas_min.y - 1.0, canvas_max.x + 1.0, canvas_max.y + 1.0], 0xFFFFFFFF);
		drawList.pushClipRect(canvas_min.x, canvas_min.y, canvas_max.x, canvas_max.y, true);
		drawList.addRectFilled([minX, minY, maxX, maxY], 0xFF646464);
		drawList.addImage(image_tex_ref, [minX, minY, maxX, maxY]);

		if (gridEnabled.value && zoomValue > 6.0)
		{
			var step:Float = zoomValue;
			for (px in Std.int((canvas_min.x - minX) / step)...Std.int((canvas_max.x - minX) / step)) {
				drawList.addLineV(minX + px * step, canvas_min.y, canvas_max.y, 0x64FFFFFF, 1.0);
			}
			for (py in Std.int((canvas_min.y - minY) / step)...Std.int((canvas_max.y - minY) / step)) {
				drawList.addLineH(canvas_min.x, canvas_max.x, minY + py * step, 0x64FFFFFF, 1.0);
			}
		}
		drawList.popClipRect();
	}

	
}
#end
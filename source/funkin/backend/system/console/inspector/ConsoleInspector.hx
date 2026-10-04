package funkin.backend.system.console.inspector;

//WIP

import openfl.Lib;
import flixel.FlxState;
import flixel.math.FlxPoint;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import funkin.backend.FunkinText;
import funkin.backend.assets.IModsAssetLibrary;
import funkin.backend.assets.ModsFolder;
import funkin.backend.assets.ModsFolderLibrary;
import funkin.backend.system.Conductor;
import funkin.backend.scripting.HScript;
import funkin.backend.scripting.ModState;
import funkin.backend.scripting.Script;
import funkin.backend.scripting.ScriptPack;
import funkin.game.Stage;

#if IMGUI_ENABLED
import lime.tools.imgui.ImGuiFlags;
import lime.tools.imgui.ImGuiHandler;
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
#end

using funkin.backend.utils.ImGuiUtil;

typedef InspectorObject = {
	var obj:Dynamic;
	var name:String;
	var type:String;
	var members:Array<InspectorObject>;
	var memberIndex:Int;
	var ?groupParent:InspectorObject;
}

/** A transform keyframe; `ease` is the FlxEase field name used for the segment to the next key. */
typedef InspectorKeyframe = {t:Float, x:Float, y:Float, angle:Float, scaleX:Float, scaleY:Float, alpha:Float, ease:String};

/** mode: 0 = once, 1 = loop, 2 = pingpong, 3 = reverse-once. patchTrack = live copy inside the loaded patch script. */
/** mode: 0 = once, 1 = loop, 2 = pingpong, 3 = reverse-once, 4 = loop-in-beats. patchTrack = live copy inside the loaded patch script. */
typedef InspectorTrack = {keys:Array<InspectorKeyframe>, mode:Int, playing:Bool, t:Float, dir:Int, sel:Int, ?patchTrack:Dynamic};

/** A point-in-time of everything the editor can change (props on live objects + editor metadata). */
typedef InspectorSnapshot = {
	props:Map<FlxBasic, {x:Float, y:Float, angle:Float, scaleX:Float, scaleY:Float, alpha:Float, color:Int, visible:Bool}>,
	names:Map<FlxBasic, String>,
	hooks:Map<FlxBasic, {c:String, u:String}>,
	tracks:Map<FlxBasic, {mode:Int, keys:Array<InspectorKeyframe>}>
};

class ConsoleInspector {

	var hscript:ConsoleHscript;
	var cachedInstanceFields:Map<String, Array<String>> = [];
	public function new(hscript:ConsoleHscript) {
		this.hscript = hscript;
		#if IMGUI_ENABLED
		objectProperties.inspector = this;
		loadSettings();
		// the perf overlay draws even when the inspector itself is closed
		ImGuiHandler.instance.addCallback(perfOverlay);
		#end
	}

	#if IMGUI_ENABLED
	var selectedObject:Dynamic = null;
	var selectedObjectData:InspectorObject = null;
	var selectedObjectValidThisFrame:Bool = false;
	var justChangedObject:Bool = false;

	var objectProperties:InspectorObjectProperties = new InspectorObjectProperties();
	var gizmo:InspectorGizmo = new InspectorGizmo();
	#if foxlite
	var gizmo3D:InspectorGizmo3D = new InspectorGizmo3D();
	#end

	// ============ STATE EDITOR ============

	/** Names assigned to objects created by the editor so they show up in the tree. */
	public var editorNames:Map<FlxBasic, String> = [];
	var editorCounter:Int = 0;

	/** Objects created by the editor; used to generate the patch script. */
	var addedObjects:Array<{obj:FlxBasic, varName:String, typeName:String, createCode:String, parent:FlxGroup, ?cloneSource:FlxSprite}> = [];

	/** Pre-existing objects whose properties were edited through the inspector. */
	var editedObjects:Map<FlxBasic, Bool> = [];

	/** Expressions of pre-existing objects deleted through the editor. */
	var removedExpressions:Array<String> = [];

	/** Custom hscript behavior attached to objects (onClick / update). fromPatch = patch already runs it. */
	var objectHooks:Map<FlxBasic, {updateCode:String, clickCode:String, code:String, script:Script, fromPatch:Bool}> = [];

	/** Animation operations performed on sprites (method-call bodies, emitted per object). */
	var animOps:Map<FlxBasic, Array<String>> = [];

	/** Draw-order changes: object, its group and the member index it was moved to. */
	var moveOps:Array<{obj:FlxBasic, parent:FlxGroup, index:Int}> = [];

	/** Reparent operations for patch export. */
	var reparentOps:Array<{obj:FlxBasic, from:FlxGroup, to:FlxGroup}> = [];

	/** Freeform code snippets appended to the patch (phase 0 = create, 1 = update). */
	var patchSnippets:Array<{code:String, phase:Int}> = [];

	/** Keyframe animation tracks per object. */
	public var keyTracks:Map<FlxBasic, InspectorTrack> = [];

	/** Object awaiting a click-in-scene keyframe placement. */
	public var clickCaptureFor:FlxBasic = null;

	/** Clicking the game view selects the topmost object under the mouse. */
	public var clickSelect:Bool = true;
	var clickSelectPtr = new ImGuiBoolPtr(true);

	/** Draws keyframe markers + motion paths over the game view. */
	public var showKeyOverlay:Bool = true;
	var showKeyOverlayPtr = new ImGuiBoolPtr(true);

	/** Always-on-top perf overlay (frame graph / fps / memory). View menu or `perf` command. */
	public var showPerf:Bool = false;
	var showPerfPtr = new ImGuiBoolPtr(false);
	var frameTimes:Array<Float> = [];

	/** Keyframe marker being dragged in the scene, if any. */
	var keyDrag:{obj:FlxBasic, index:Int, cam:FlxCamera} = null;

	/** Set when the mouse interacted with a keyframe marker this frame (blocks scene click-select). */
	var keyMouseConsumed:Bool = false;

	/** Scene object(s) being moved by dragging directly with the mouse, if any. */
	var sceneDrag:{obj:FlxObject, cam:FlxCamera, offX:Float, offY:Float, moved:Bool, others:Array<{o:FlxObject, dx:Float, dy:Float}>} = null;

	/** Scene-tree rebuild throttling: structural edits set objectsDirty for an instant refresh. */
	var objectsDirty:Bool = true;
	var objectsTimer:Float = 0;

	/** In-scene text edit state, opened by double-clicking a FlxText. */
	var textEditTarget:FlxText = null;
	var textEditOpen = new ImGuiBoolPtr(false);
	var textEditPtr:ImGuiStringPtr = null;
	var textEditDirty:Bool = false;
	var textEditJustOpened:Bool = false;
	var textEditX:Float = 0;
	var textEditY:Float = 0;

	/** Extra objects added to the selection with Ctrl+click (selectedObject stays the primary). */
	var selectedObjects:Array<FlxBasic> = [];

	/** Clipboard spec for Ctrl+C/V object copy-paste. */
	var clipboard:Dynamic = null;

	/** Named session snapshots, independent of the undo stack. */
	var namedSnapshots:Map<String, InspectorSnapshot> = [];
	var snapshotName = new ImGuiStringPtr("checkpoint");
	var snapshotPick = new ImGuiIntPtr(0);

	/** State layer filter for the tree + scene picking (0 = all, 1+ = FlxG.state/substates). */
	var stateLayerPtr = new ImGuiIntPtr(0);

	/** Song scrub slider (PlayState only). */
	var songScrubPtr = new ImGuiFloatPtr(0);

	/** Camera manager drag ptrs. */
	var camZoomPtr = new ImGuiFloatPtr(1);
	var camScrollPtr = new ImGuiFloat2Ptr(0, 0);

	/** Motion bake state: records an object's live pose into a key track. */
	public var baking:{obj:FlxBasic, keys:Array<InspectorKeyframe>, t:Float, nextT:Float, dur:Float} = null;
	static inline var BAKE_STEP:Float = 0.05;

	/** Right-click keyframe context menu target. */
	var keyCtx:{obj:FlxBasic, index:Int} = null;
	var keyCtxTimePtr = new ImGuiFloatPtr(0);
	var keyCtxEasePtr = new ImGuiIntPtr(0);

	/** Snapshot taken right after adopting the state's patch; basis for the "changes" list. */
	var adoptSnapshot:InspectorSnapshot = null;

	/** Sound preview window state. */
	var soundPreviewOpen = new ImGuiBoolPtr(false);
	var soundPreviewList:Array<String> = null;
	var soundPreviewFilter = new ImGuiStringPtr("");
	var previewSound:flixel.sound.FlxSound = null;
	var previewWave:Array<Float> = null;
	var previewWaveDur:Float = 0;
	var previewWavePath:String = null;
	var previewStatus:String = "";

	/** Shift+drag rubber-band marquee selection (screen coords). */
	var marquee:{x0:Float, y0:Float} = null;

	/** Last persisted editor settings, so we only write on change. */
	var savedGizmoMode:Int = -1;
	var savedClickSelect:Bool = true;
	var savedKeyOverlay:Bool = true;
	var savedShowPerf:Bool = false;

	/** Asset browser window state. */
	var assetBrowserOpen = new ImGuiBoolPtr(false);
	var assetBrowserList:Array<String> = null;
	var assetBrowserFilter = new ImGuiStringPtr("");
	var assetBrowserSel:String = null;
	var assetBrowserBmd:openfl.display.BitmapData = null;
	var assetBrowserStatus:String = "";
	var assetClickPlace:Bool = false;

	/** Force window pos/size for one frame (clears stale docking positions). */
	public var forceLayout:Bool = false;

	// ---- undo/redo (debounced snapshots of editable state) ----
	var undoStack:Array<InspectorSnapshot> = [];
	var redoStack:Array<InspectorSnapshot> = [];
	var snapBaseline:InspectorSnapshot = null;
	var snapPending:Bool = false;
	var snapTimer:Float = 0;

	var easeNames:Array<String> = null;

	var addKind = new ImGuiIntPtr(0);
	var addImagePath = new ImGuiStringPtr("");
	var treeFilter = new ImGuiStringPtr("");
	var addTextContent = new ImGuiStringPtr("New Text");
	var addTextSize = new ImGuiIntPtr(24);
	var addCustomCode = new ImGuiStringPtr("new flixel.FlxSprite(0, 0, Paths.image('menus/menuBG'))");
	var codeRunnerText = new ImGuiStringPtr("// 'obj' = selection, 'state' = FlxG.state\ntrace(obj);\n");
	var codeRunnerPhase = new ImGuiIntPtr(0);
	var newStateName = new ImGuiStringPtr("MyState");
	var jumpToTab:Int = -1;
	var saveStatus:String = "";
	var runStatus:String = "";

	var currentStateObjects:Array<InspectorObject> = [];
	var inspectorObjectsThatNeedUpdating:Array<InspectorObject> = [];

	function updateObjects() {
		var rootState:FlxState = FlxG.state;
		if (rootState != null && rootState != lastAdoptedState)
			adoptPatch(rootState);
		var states:Array<FlxState> = [FlxG.state];
		var stateToCheck:FlxState = FlxG.state;
		while(stateToCheck.subState != null) {
			states.push(stateToCheck.subState);
			stateToCheck = stateToCheck.subState;
		}
		
		if (currentStateObjects.length > states.length) {
			currentStateObjects.resize(states.length);
		}
		for (index => state in states) {
			if (currentStateObjects[index] == null || currentStateObjects[index].obj != state) {

				var packageName = hscript.getFieldTypeName(state);
				if (!cachedInstanceFields.exists(packageName)) {
					cachedInstanceFields.set(packageName, Type.getInstanceFields(Type.getClass(state)));
				}
				var packageSplit = packageName.split(".");
				var stateName = packageSplit[packageSplit.length-1];

				currentStateObjects[index] = {
					obj: state,
					name: stateName,
					type: packageName,
					memberIndex: index,
					members: []
				};
			}
		}

		for (index => inspectorObject in currentStateObjects) {
			updateObjectMembers(index, inspectorObject);
		}
	}

	function updateObjectMembers(index:Int, inspectorObject:InspectorObject, fromGroup:Bool = false) {
		var objMembers:Array<Dynamic> = inspectorObject.obj.members;
		#if foxlite
		if (inspectorObject.obj is FoxScene) {
			objMembers = inspectorObject.obj.foxGroup.members;
		}
		#end
		if (objMembers == null) {
			return;
		}

		//sort and remove if needed
		var membersToRemove:Array<InspectorObject> = [];
		for (member in inspectorObject.members) {
			var currentIndex:Int = objMembers.indexOf(member.obj);
			if (currentIndex == -1) {
				membersToRemove.push(member);
			}
			member.memberIndex = currentIndex;
		}
		for (m in membersToRemove) inspectorObject.members.remove(m);
		inspectorObject.members.sort(function(a, b) {
           if(a.memberIndex < b.memberIndex) return -1;
           else if(a.memberIndex > b.memberIndex) return 1;
           else return 0;
        });

		//we have new members to add
		if (inspectorObject.members.length != objMembers.length) {
			var newList:Array<InspectorObject> = [];
			var oldListIndex:Int = 0;
			for (i in 0...objMembers.length) {
				if (inspectorObject.members[oldListIndex] == null || inspectorObject.members[oldListIndex].memberIndex != i || inspectorObject.members[oldListIndex].obj != objMembers[i]) {
					var member:Dynamic = objMembers[i];
					var memberPackage = hscript.getFieldTypeName(objMembers[i]);
					var memberPackageSplit = memberPackage.split(".");
					var memberType = memberPackageSplit[memberPackageSplit.length-1];
					var memberName:String = fromGroup ? inspectorObject.name + ".members[" + i + "]" : figureOutObjectName(inspectorObject.type, inspectorObject.obj, member);
					var newObj = {
						obj: objMembers[i],
						name: memberName,
						type: memberType,
						memberIndex: i,
						members: [],
						groupParent: fromGroup ? inspectorObject : null
					};
					newList.push(newObj);
					if (member is FlxTypedGroup || member is FlxTypedSpriteGroup #if foxlite || member is FoxScene || member is FoxTypedGroup || member is FoxObjectGroup #end) {
						updateObjectMembers(i, newObj, true);
					}
				} else {
					newList.push(inspectorObject.members[oldListIndex]);
					oldListIndex++;
				}
			}
			inspectorObject.members = newList;
		}
	}

	function showEditorMenuBar() {
		if (ImGui.beginMenuBar()) {
			if (ImGui.beginMenu("File")) {
				if (ImGui.menuItem("New State...")) ImGui.openPopup("##newState");
				if (ImGui.beginMenu("Open Scripted State")) {
					var states = listScriptedStates();
					if (states.length == 0) ImGui.menuItem("(none found)", null, false, false);
					for (s in states) if (ImGui.menuItem(s)) openScriptedState(s);
					ImGui.endMenu();
				}
				ImGui.separator();
				if (ImGui.menuItem("Undo", "Ctrl+Z")) doUndo();
				if (ImGui.menuItem("Redo", "Ctrl+Y")) doRedo();
				ImGui.separator();
				if (ImGui.menuItem("Copy", "Ctrl+C", false, selectedObject != null)) copySelected();
				if (ImGui.menuItem("Paste", "Ctrl+V", false, clipboard != null)) pasteClipboard();
				if (ImGui.menuItem("Cut", "Ctrl+X", false, selectedObject != null)) {
					copySelected();
					for (o in selectionList()) deleteInspectorObject(o);
				}
				if (ImGui.menuItem("Duplicate", "Ctrl+D", false, selectedObject != null)) duplicateObject(cast selectedObject);
				if (ImGui.menuItem("Delete", "Del", false, selectedObject != null)) {
					var sel = selectionList();
					if (sel.length > 1) for (o in sel) deleteInspectorObject(o);
					else deleteInspectorObject(cast selectedObject);
				}
				ImGui.separator();
				if (ImGui.menuItem("Reload State Scripts")) reloadStateScripts();
				if (ImGui.menuItem("Save Patch", "Ctrl+S")) savePatch();
				if (ImGui.isItemHovered()) ImGui.setTooltip("writes data/states/<State>.hx");
				ImGui.endMenu();
			}
			if (ImGui.beginMenu("Add")) {
				var kinds = ["Sprite", "Text", "Button", "Group", "Custom (code)"];
				for (i => k in kinds)
					if (ImGui.menuItem(k)) { addKind.value = i; jumpToTab = 1; }
				ImGui.endMenu();
			}
			if (ImGui.beginMenu("View")) {
				if (ImGui.menuItem("Object Properties")) objectProperties.isOpen.value = true;
				if (ImGui.menuItem("Sound Preview", null, soundPreviewOpen.value)) soundPreviewOpen.value = !soundPreviewOpen.value;
				if (ImGui.menuItem("Asset Browser", null, assetBrowserOpen.value)) assetBrowserOpen.value = !assetBrowserOpen.value;
				if (ImGui.menuItem("Perf Overlay", null, showPerf)) { showPerf = !showPerf; showPerfPtr.value = showPerf; }
				if (ImGui.menuItem("Screenshot to exports/")) takeScreenshot();
				if (ImGui.menuItem("Reset Layout")) {
					forceLayout = true;
					objectProperties.isOpen.value = true;
					#if sys
					if (sys.FileSystem.exists("imgui.ini")) sys.FileSystem.deleteFile("imgui.ini");
					#end
				}
				ImGui.endMenu();
			}
			if (ImGui.beginMenu("Help")) {
				ImGui.menuItem("Q/W/E/R - none/move/rotate/scale gizmo", null, false, false);
				ImGui.menuItem("Ctrl while dragging - snap", null, false, false);
				ImGui.menuItem("Click in scene - select object, drag - move it", null, false, false);
				ImGui.menuItem("Ctrl+click - add/remove from selection, drag moves all", null, false, false);
				ImGui.menuItem("Ctrl+C/X/V - copy, cut, paste objects", null, false, false);
				ImGui.menuItem("Del - delete selection, Del still types in text fields", null, false, false);
				ImGui.menuItem("Double-click text - edit its text", null, false, false);
				ImGui.menuItem("Drag keyframe marker - move key, right-click - key menu", null, false, false);
				ImGui.menuItem("F2 - console, F4 - this window", null, false, false);
				ImGui.endMenu();
			}
			ImGui.endMenuBar();
		}
	}

	function showNewStatePopup() {
		#if sys
		if (ImGui.beginPopup("##newState")) {
			ImGui.textWrapped("Creates data/states/<name>.hx and opens it as a scripted state.");
			ImGui.setNextItemWidth(-1);
			ImGui.inputText("Name##newState", newStateName);
			if (ImGui.button("Create & Open##newState")) {
				createAndOpenState(newStateName.value);
				ImGui.closeCurrentPopup();
			}
			ImGui.sameLine();
			if (ImGui.button("Cancel##newState")) ImGui.closeCurrentPopup();
			ImGui.endPopup();
		}
		#end
	}

	function showCreateTab() {
		ImGui.combo("Type##inspectorAdd", addKind, ["Sprite", "Text", "Button", "Group", "Custom (code)"]);
		switch (addKind.value) {
			case 0:
				ImGui.inputText("Image##inspectorAdd", addImagePath);
				if (ImGui.isItemHovered()) ImGui.setTooltip("path inside images/, e.g. menus/menuBG");
			case 1 | 2:
				ImGui.inputText("Text##inspectorAdd", addTextContent);
				ImGui.dragInt("Size##inspectorAdd", addTextSize);
			case 4:
				ImGui.textWrapped("Any hscript expression returning a FlxBasic, e.g. new funkin.game.Character(0, 0, 'bf')");
				ImGui.inputTextMultiline("##inspectorAddCustom", addCustomCode, ImGui.getContentRegionAvail().x, 60);
			default:
		}
		ImGui.textWrapped("Added to the selected group, or the state itself.");
		if (ImGui.button("Create##inspectorAdd")) createInspectorObject();
		if (selectedObject != null && selectedObject is FlxBasic) {
			ImGui.separator();
			if (ImGui.button("Delete Selected##inspector")) deleteInspectorObject(cast selectedObject);
		}
	}

	function showCodeTab() {
		ImGui.textWrapped("'obj' = selected object, 'state' = current state. Runs top-level hscript.");
		ImGui.inputTextMultiline("##runnerCode", codeRunnerText, ImGui.getContentRegionAvail().x, 140);
		if (ImGui.button("Run Now##runner")) runSnippet();
		ImGui.sameLine();
		ImGui.setNextItemWidth(110);
		ImGui.combo("##runnerPhase", codeRunnerPhase, ["postCreate", "update"]);
		ImGui.sameLine();
		if (ImGui.button("Append to Patch##runner")) {
			patchSnippets.push({code: codeRunnerText.value, phase: codeRunnerPhase.value});
			runStatus = "Queued (" + (codeRunnerPhase.value == 0 ? "create" : "update") + ")";
		}
		if (runStatus != "") ImGui.textWrapped(runStatus);

		if (patchSnippets.length > 0) {
			ImGui.separatorText("Queued in patch:");
			var toRemove = -1;
			for (i => sn in patchSnippets) {
				ImGui.pushIDFromInt(i);
				var preview = sn.code.split("\n")[0];
				if (preview.length > 38) preview = preview.substr(0, 35) + "...";
				ImGui.bulletText((sn.phase == 0 ? "[create] " : "[update] ") + preview);
				ImGui.sameLine();
				if (ImGui.smallButton("x")) toRemove = i;
				ImGui.popID();
			}
			if (toRemove != -1) patchSnippets.splice(toRemove, 1);
		}

		// most recent runtime/parse error per loaded script
		var errCount = 0;
		var packs:Array<ScriptPack> = [];
		if (FlxG.state is MusicBeatState)
			packs.push((cast FlxG.state : MusicBeatState).stateScripts);
		for (pack in packs) {
			if (pack == null) continue;
			for (s in pack.scripts)
				if (Script.lastErrors.exists(s)) errCount++;
		}
		if (errCount > 0 && ImGui.collapsingHeader('Script errors ($errCount)##errs')) {
			for (pack in packs) {
				if (pack == null) continue;
				for (s in pack.scripts) {
					var err = Script.lastErrors.get(s);
					if (err == null) continue;
					ImGui.textColored(0xFFFF6666, '${s.fileName}:');
					ImGui.indent();
					ImGui.textWrapped(err);
					if (ImGui.smallButton('clear##err${s.fileName}')) Script.lastErrors.remove(s);
					ImGui.unindent();
				}
			}
		}
	}

	function showExportTab() {
		ImGui.textWrapped("Exports edits as data/states/<State>.hx - auto-loaded every time the state opens.");
		ImGui.separator();
		if (ImGui.button("Save Patch##export")) savePatch();
		if (saveStatus != "") ImGui.textWrapped(saveStatus);
		#if sys
		ImGui.separator();
		var base = resolvePatchLibraryPath();
		ImGui.textWrapped("Target: " + (base != null ? base + "data/states/" : "no writable library"));
		#end
		if (ImGui.collapsingHeader("Changes##export")) {
			var diffs = diffFromBaseline();
			if (diffs.length == 0) ImGui.text("No changes since this state was adopted.");
			else {
				if (ImGui.beginChild("##diffList", 0, 150, ImGuiChildFlags.Borders))
					for (d in diffs) ImGui.textWrapped(d);
				ImGui.endChild();
			}
		}
	}

	function nameForObject(o:FlxBasic):String {
		var n = editorNames.get(o);
		if (n != null) return n;
		var d = findInspectorObjectFor(o);
		return d != null ? d.name : Type.getClassName(Type.getClass(o));
	}

	/** Diffs the current scene against the post-adoption snapshot; returns display lines. */
	function diffFromBaseline():Array<String> {
		var out:Array<String> = [];
		if (adoptSnapshot == null) return out;
		var cur = captureSnapshot();
		for (o => p in adoptSnapshot.props) {
			var nm = nameForObject(o);
			var q = cur.props.get(o);
			if (q == null) { out.push('- $nm (removed)'); continue; }
			var diffs:Array<String> = [];
			if (p.x != q.x) diffs.push('x ${FlxMath.roundDecimal(p.x,1)}->${FlxMath.roundDecimal(q.x,1)}');
			if (p.y != q.y) diffs.push('y ${FlxMath.roundDecimal(p.y,1)}->${FlxMath.roundDecimal(q.y,1)}');
			if (p.angle != q.angle) diffs.push('angle ${FlxMath.roundDecimal(p.angle,1)}->${FlxMath.roundDecimal(q.angle,1)}');
			if (p.scaleX != q.scaleX || p.scaleY != q.scaleY) diffs.push('scale');
			if (p.alpha != q.alpha) diffs.push('alpha ${FlxMath.roundDecimal(p.alpha,2)}->${FlxMath.roundDecimal(q.alpha,2)}');
			if (p.color != q.color) diffs.push('color');
			if (p.visible != q.visible) diffs.push(q.visible ? 'shown' : 'hidden');
			if (diffs.length > 0) out.push('~ $nm: ${diffs.join(", ")}');
		}
		for (o => p in cur.props)
			if (!adoptSnapshot.props.exists(o) && editorNames.exists(o)) out.push('+ ${nameForObject(o)}');
		for (o => h in objectHooks) {
			var old = adoptSnapshot.hooks.get(o);
			if (old == null) {
				if (h.clickCode != "" || h.updateCode != "") out.push('+ ${nameForObject(o)} hooks');
			} else if (old.c != h.clickCode || old.u != h.updateCode)
				out.push('~ ${nameForObject(o)} hooks');
		}
		for (o => tr in keyTracks) {
			var old = adoptSnapshot.tracks.get(o);
			var nm = nameForObject(o);
			if (old == null) { if (tr.keys.length > 0) out.push('+ $nm keyframes (${tr.keys.length})'); continue; }
			var same = old.mode == tr.mode && old.keys.length == tr.keys.length;
			if (same)
				for (i in 0...old.keys.length) {
					var a = old.keys[i], b = tr.keys[i];
					if (a.t != b.t || a.x != b.x || a.y != b.y || a.angle != b.angle || a.scaleX != b.scaleX
						|| a.scaleY != b.scaleY || a.alpha != b.alpha || a.ease != b.ease) { same = false; break; }
				}
			if (!same) out.push('~ $nm keyframes (${tr.keys.length})');
		}
		for (e in removedExpressions) out.push('- $e (deleted)');
		return out;
	}

	function listScriptedStates():Array<String> {
		var out:Array<String> = [];
		#if sys
		var seen:Map<String, Bool> = [];
		for (l in ModsFolder.getLoadedModsLibs()) {
			var mfl:ModsFolderLibrary = (l is ModsFolderLibrary) ? cast l : null;
			if (mfl == null) continue;
			var dir = mfl.basePath + "/data/states";
			if (!sys.FileSystem.exists(dir)) continue;
			for (f in sys.FileSystem.readDirectory(dir)) {
				if (!f.endsWith(".hx") || seen.exists(f)) continue;
				seen.set(f, true);
				out.push(f.substr(0, f.length - 3));
			}
		}
		out.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		#end
		return out;
	}

	function openScriptedState(name:String) {
		FlxG.switchState(new ModState(name));
	}

	function createAndOpenState(name:String) {
		#if sys
		var clean = sanitizeVarName(name);
		var base = resolvePatchLibraryPath();
		if (base == null) { saveStatus = "No writable library"; return; }
		var dir = '$base/data/states';
		sys.FileSystem.createDirectory(dir);
		var path = '$dir/$clean.hx';
		if (!sys.FileSystem.exists(path)) {
			sys.io.File.saveContent(path,
				'// Scripted state: $clean - edit with the State Editor (F4) or directly.\n\n'
				+ 'function postCreate() {\n\t// add(sprite), state fields are in scope\n}\n\n'
				+ 'function update(elapsed) {\n}\n\n'
				+ 'function destroy() {\n}\n');
		}
		openScriptedState(clean);
		#end
	}

	function reloadStateScripts() {
		if (FlxG.state is MusicBeatState)
			(cast FlxG.state : MusicBeatState).stateScripts.reload();
	}

	/** Small always-on-top perf window - runs on its own ImGui callback so it works with the inspector closed. */
	function perfOverlay() {
		if (showPerfPtr.value != showPerf) {
			showPerf = showPerfPtr.value;
			persistSettings();
		}
		if (!showPerf) return;

		var ms = FlxG.elapsed * 1000;
		if (frameTimes.length == 0 || frameTimes[frameTimes.length - 1] != ms) {
			frameTimes.push(ms);
			if (frameTimes.length > 240) frameTimes.shift();
		}
		var fps = FlxG.elapsed > 0 ? 1 / FlxG.elapsed : 0;
		var avg = 0.0, max = 0.0;
		for (t in frameTimes) { avg += t; if (t > max) max = t; }
		if (frameTimes.length > 0) avg /= frameTimes.length;

		var stateName = Type.getClassName(Type.getClass(FlxG.state));
		ImGui.setNextWindowPos(6, 6, ImGuiCond.FirstUseEver);
		ImGui.setNextWindowBGAlpha(0.6);
		var flags = ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.AlwaysAutoResize | ImGuiWindowFlags.NoFocusOnAppearing | ImGuiWindowFlags.NoNav;
		if (ImGui.begin("Perf##overlay", showPerfPtr, flags)) {
			var overlay = '${round1(ms)}ms  ${Std.int(fps)}fps';
			ImGui.text(stateName);
			ImGui.text('$overlay  avg ${round1(avg)}ms  max ${round1(max)}ms');
			#if cpp
			ImGui.text('mem ${Std.int(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / 1048576)} MB');
			#end
			ImGui.plotLines("##frametimes", frameTimes, frameTimes.length, 0, overlay, 0, Math.max(40, max), 280, 42);
		}
		ImGui.end();
	}

	inline function round1(v:Float):Float return Std.int(v * 10) / 10;

	public function displayUI() {
		// rebuild the scene tree at ~7Hz (or instantly when an edit marks it dirty)
		if (objectsDirty || (objectsTimer -= FlxG.elapsed) <= 0) {
			objectsTimer = 0.15;
			objectsDirty = false;
			updateObjects();
		}

		FlxG.mouse.visible = true; //TODO: rework this, temp force on
		
		var wcond = forceLayout ? ImGuiCond.Always : ImGuiCond.FirstUseEver;
		objectProperties.forceLayout = forceLayout;
		forceLayout = false;
		ImGui.setNextWindowPos(ImGuiUtil.getWindowSpaceX(), ImGuiUtil.getWindowSpaceY(), wcond);
		ImGui.setNextWindowSize(320, Lib.application.window.height, wcond);
		if (ImGui.begin("State Editor", null, ImGuiWindowFlags.MenuBar)) {
			showEditorMenuBar();
			showNewStatePopup();

			if (ImGui.beginTabBar("##stateEditorTabs")) {
				if (ImGui.beginTabItem("Scene", null, jumpToTab == 0 ? ImGuiTabItemFlags.SetSelected : 0)) {
					jumpToTab = -1;
					ImGui.separatorText("Tools/Gizmo");
					ImGui.indent();
					if (ImGui.selectable("None (Q)", gizmo.gizmoMode == -1)) gizmo.gizmoMode = -1;
					if (ImGui.selectable("Position (W)", gizmo.gizmoMode == 0)) gizmo.gizmoMode = 0;
					if (ImGui.selectable("Rotation (E)", gizmo.gizmoMode == 1)) gizmo.gizmoMode = 1;
					if (ImGui.selectable("Scale (R)", gizmo.gizmoMode == 2)) gizmo.gizmoMode = 2;
					ImGui.checkbox("Click/drag scene objects##pick", clickSelectPtr);
					clickSelect = clickSelectPtr.value;
					ImGui.checkbox("Show keyframes##pick", showKeyOverlayPtr);
					showKeyOverlay = showKeyOverlayPtr.value;
					ImGui.unindent();

					if (currentStateObjects.length > 1) {
						var layerNames = ["All layers"];
						for (o in currentStateObjects) layerNames.push(o.name);
						if (stateLayerPtr.value >= layerNames.length) stateLayerPtr.value = 0;
						ImGui.setNextItemWidth(-1);
						ImGui.combo("##stateLayer", stateLayerPtr, layerNames);
						if (ImGui.isItemHovered()) ImGui.setTooltip("limit the tree + scene clicks to one state/substate");
					}

					if (selectedObjects.length > 0) {
						ImGui.separatorText('${selectionList().length} selected');
						if (ImGui.smallButton("L##al")) alignSelection("l");
						ImGui.sameLine(); if (ImGui.smallButton("CX##al")) alignSelection("cx");
						ImGui.sameLine(); if (ImGui.smallButton("R##al")) alignSelection("r");
						ImGui.sameLine(); if (ImGui.smallButton("T##al")) alignSelection("t");
						ImGui.sameLine(); if (ImGui.smallButton("CY##al")) alignSelection("cy");
						ImGui.sameLine(); if (ImGui.smallButton("B##al")) alignSelection("b");
						ImGui.sameLine(); if (ImGui.smallButton("Dist H##al")) alignSelection("dh");
						ImGui.sameLine(); if (ImGui.smallButton("Dist V##al")) alignSelection("dv");
						if (ImGui.isItemHovered()) ImGui.setTooltip("spread selected objects evenly");
					}

					if (ImGui.collapsingHeader("Snapshots##snap")) {
						ImGui.setNextItemWidth(150);
						ImGui.inputTextWithHint("##snapName", "snapshot name", snapshotName);
						ImGui.sameLine();
						if (ImGui.smallButton("Save##snap")) {
							namedSnapshots.set(snapshotName.value, captureSnapshot());
							runStatus = 'Snapshot "${snapshotName.value}" saved';
						}
						var snapNames = [for (n in namedSnapshots.keys()) n];
						if (snapNames.length > 0) {
							snapNames.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
							if (snapshotPick.value >= snapNames.length) snapshotPick.value = 0;
							ImGui.setNextItemWidth(150);
							ImGui.combo("##snapPick", snapshotPick, snapNames);
							if (snapshotPick.value < snapNames.length) {
								var nm = snapNames[snapshotPick.value];
								ImGui.sameLine();
								if (ImGui.smallButton("Restore##snap")) {
									applySnapshot(namedSnapshots.get(nm));
									runStatus = 'Restored "$nm"';
								}
								ImGui.sameLine();
								if (ImGui.smallButton("x##snap")) namedSnapshots.remove(nm);
							}
						}
					}

					if (ImGui.collapsingHeader("Cameras##cams")) {
						if (ImGui.smallButton("New Camera##cams")) {
							var c = new FlxCamera(0, 0, FlxG.width, FlxG.height);
							FlxG.cameras.add(c, false);
							runStatus = 'Camera ${FlxG.cameras.list.indexOf(c)} created';
						}
						var i = 0;
						var deadCam:FlxCamera = null;
						for (cam in FlxG.cameras.list) {
							ImGui.pushIDFromStr('cam$i');
							ImGui.text('$i');
							ImGui.sameLine();
							ImGui.setNextItemWidth(90);
							camZoomPtr.value = cam.zoom;
							if (ImGui.dragFloat("zoom", camZoomPtr, 0.01, 0.05, 50)) cam.zoom = camZoomPtr.value;
							ImGui.sameLine();
							ImGui.setNextItemWidth(150);
							camScrollPtr.values[0] = cam.scroll.x;
							camScrollPtr.values[1] = cam.scroll.y;
							if (ImGui.dragFloat2("scroll", camScrollPtr, 1)) cam.scroll.set(camScrollPtr.values[0], camScrollPtr.values[1]);
							ImGui.sameLine();
							if (ImGui.smallButton("x") && FlxG.cameras.list.length > 1) deadCam = cam;
							ImGui.popID();
							i++;
						}
						if (deadCam != null) FlxG.cameras.remove(deadCam);
					}

					if (FlxG.state is funkin.game.PlayState && ImGui.collapsingHeader("Song##scrub")) {
						var ps:funkin.game.PlayState = cast FlxG.state;
						if (ps.inst != null && ps.inst.length > 0) {
							songScrubPtr.value = Conductor.songPosition / 1000;
							ImGui.setNextItemWidth(-1);
							if (ImGui.sliderFloat("##songScrub", songScrubPtr, 0, ps.inst.length / 1000, "%.1fs")) {
								var ms = songScrubPtr.value * 1000;
								try {
									ps.inst.time = ms;
									if (ps.vocals != null) ps.vocals.time = ms;
									Conductor.songPosition = ms;
								} catch(e) runStatus = 'Seek failed: $e';
							}
							if (ImGui.isItemHovered()) ImGui.setTooltip("scrub the song position (dev tool)");
						}
					}

					ImGui.separatorText("Scene Tree");
					ImGui.setNextItemWidth(-1);
					ImGui.inputTextWithHint("##treeFilter", "Filter objects...", treeFilter);
					for (index => member in currentStateObjects) {
						if (stateLayerPtr.value > 0 && index != stateLayerPtr.value - 1) continue;
						if (treeFilterActive() && !treeMatch(member)) continue;
						var nodeID = member.name + index;
						var flags = ImGuiTreeNodeFlags.DefaultOpen;
						if (member.obj == selectedObject || (member.obj is FlxBasic && selectedObjects.contains(cast member.obj)))
							flags |= ImGuiTreeNodeFlags.Selected;
						if (ImGui.treeNodeEx(nodeID, flags, member.name + " (" + member.type + ")")) {
							if (ImGui.isItemClicked()) {
								selectObject(member.obj, ImGui.isKeyDown(ImGuiKey.LeftCtrl) || ImGui.isKeyDown(ImGuiKey.RightCtrl));
							}
							showNodeExtras(member);
							if (member.members.length > 0) {
								generateTreeForMembers(nodeID, member);
							}
							ImGui.treePop();
						}
					}
					ImGui.endTabItem();
				}
				if (ImGui.beginTabItem("Create", null, jumpToTab == 1 ? ImGuiTabItemFlags.SetSelected : 0)) {
					jumpToTab = -1;
					showCreateTab();
					ImGui.endTabItem();
				}
				if (ImGui.beginTabItem("Code")) {
					showCodeTab();
					ImGui.endTabItem();
				}
				if (ImGui.beginTabItem("Export")) {
					showExportTab();
					ImGui.endTabItem();
				}
				ImGui.endTabBar();
			}
		}
		ImGui.end();

		if (selectedObject != null) {
			selectedObjectValidThisFrame = false;
			for (member in currentStateObjects) {
				if (member.obj == selectedObject) {
					selectedObjectValidThisFrame = true;
					selectedObjectData = member;
					break;
				}
				checkForSelectedObjectThisFrame(member);
			}

			if (selectedObjectValidThisFrame) {
				objectProperties.show(selectedObjectData, justChangedObject);
				if (selectedObject is FlxObject) {
					gizmo.show(selectedObjectData, cast selectedObject, justChangedObject);
					if (gizmo.objectWasEdited) {
						gizmo.objectWasEdited = false;
						markEdited(cast selectedObject);
					}
				} #if foxlite else if (selectedObject is FoxObject) {
					gizmo3D.show(selectedObjectData, cast selectedObject, justChangedObject);
				}
				#end
				justChangedObject = false;
			} else {
				selectedObject = null;
				selectedObjectData = null;
			}
		}

		drawTextEdit();
		drawSoundPreview();
		drawAssetBrowser();
		if (marquee != null) {
			var mp = ImGui.getMousePos();
			var dl = ImGui.getBackgroundDrawList(ImGui.getMainViewport());
			var x0 = Math.min(marquee.x0, mp.x), y0 = Math.min(marquee.y0, mp.y);
			var x1 = Math.max(marquee.x0, mp.x), y1 = Math.max(marquee.y0, mp.y);
			dl.addRectFilled([x0, y0, x1, y1], 0x33FFFFFF);
			dl.addRect([x0, y0, x1, y1], 0xFFFFFFFF, 0, 1.5);
		}
		drawKeyframeOverlays();
		tickUndo(FlxG.elapsed);
		tickKeyTracks(FlxG.elapsed);
		runObjectHooks();
	}

	/** Floating in-scene text edit window; opened by double-clicking a FlxText. Edits apply live. */
	function drawTextEdit() {
		if (textEditTarget == null) return;

		var close = !isAliveInScene(textEditTarget);
		if (!close) {
			if (textEditJustOpened) ImGui.setNextWindowPos(textEditX, textEditY, ImGuiCond.Appearing);
			ImGui.setNextWindowSize(340, 0, ImGuiCond.Appearing);
			if (ImGui.begin("Edit Text##sceneTextEdit", textEditOpen,
				ImGuiWindowFlags.NoCollapse | ImGuiWindowFlags.AlwaysAutoResize)) {
				var name = editorNames.get(textEditTarget) ?? findInspectorObjectFor(textEditTarget)?.name;
				if (name != null) ImGui.text(name);
				if (textEditJustOpened) {
					ImGui.setKeyboardFocusHere();
					textEditJustOpened = false;
				}
				if (ImGui.inputTextMultiline("##sceneTextEditInput", textEditPtr, 320, 120)) {
					textEditTarget.text = textEditPtr.value;
					textEditDirty = true;
				}
				if (ImGui.button("Done##sceneTextEdit")) close = true;
				if (ImGui.isWindowFocused(ImGuiFocusedFlags.RootAndChildWindows) && ImGui.isKeyPressed(ImGuiKey.Escape))
					close = true;
			}
			ImGui.end();
			if (!textEditOpen.value) close = true;
		}

		if (close) {
			if (textEditDirty) markEdited(textEditTarget);
			textEditTarget = null;
			textEditOpen.value = false;
		}
	}

	// ============ SOUND PREVIEW ============

	function drawSoundPreview() {
		#if sys
		if (!soundPreviewOpen.value) {
			stopSoundPreview();
			return;
		}
		if (soundPreviewList == null) {
			soundPreviewList = [];
			var seen:Map<String, Bool> = [];
			for (folder in ["sounds", "music"]) {
				for (f in Paths.assetsTree.getFiles('assets/$folder')) {
					var lower = f.toLowerCase();
					if (!(lower.endsWith(".ogg") || lower.endsWith(".wav") || lower.endsWith(".mp3"))) continue;
					var id = '$folder/$f';
					if (seen.exists(id)) continue;
					seen.set(id, true);
					soundPreviewList.push(id);
				}
			}
			soundPreviewList.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		}
		ImGui.setNextWindowSize(340, 430, ImGuiCond.FirstUseEver);
		if (ImGui.begin("Sound Preview##snd", soundPreviewOpen)) {
			ImGui.setNextItemWidth(-1);
			ImGui.inputTextWithHint("##sndFilter", "filter...", soundPreviewFilter);
			var filter = StringTools.trim(soundPreviewFilter.value).toLowerCase();
			if (ImGui.beginChild("##sndList", 0, 240)) {
				for (s in soundPreviewList) {
					if (filter != "" && s.toLowerCase().indexOf(filter) == -1) continue;
					if (ImGui.selectable(s, previewWavePath == s)) {
						previewWavePath = s;
						loadWaveform(s);
					}
				}
			}
			ImGui.endChild();
			if (previewWavePath != null) {
				ImGui.text(previewWavePath + (previewWaveDur > 0 ? '  (${FlxMath.roundDecimal(previewWaveDur, 2)}s)' : ""));
				drawWaveform();
				if (ImGui.button("Play##snd")) playSoundPreview();
				ImGui.sameLine();
				if (ImGui.button("Stop##snd")) stopSoundPreview();
			}
			if (previewStatus != "") ImGui.textWrapped(previewStatus);
		}
		ImGui.end();
		#end
	}

	function loadWaveform(id:String) {
		previewWave = null;
		previewWaveDur = 0;
		previewStatus = "";
		#if sys
		var path = Paths.assetsTree.getSpecificPath('assets/$id');
		if (path == null) { previewStatus = 'No file for $id'; return; }
		try {
			var buf = lime.media.AudioBuffer.fromFile(path);
			if (buf == null || buf.data == null || buf.channels <= 0) { previewStatus = "Couldn't decode audio"; return; }
			var bytesPerFrame = Std.int(buf.channels * (buf.bitsPerSample / 8));
			if (bytesPerFrame <= 0) { previewStatus = "Unknown audio format"; return; }
			var frames = Std.int(buf.data.length / bytesPerFrame);
			previewWaveDur = buf.sampleRate > 0 ? frames / buf.sampleRate : 0;
			var data = buf.data;
			var cols = 160;
			var peaks:Array<Float> = [];
			for (i in 0...cols) {
				var lo = Std.int(i / cols * frames);
				var hi = Std.int((i + 1) / cols * frames);
				if (hi <= lo) hi = lo + 1;
				var step = Std.int(Math.max(1, (hi - lo) / 40));
				var peak = 0.0;
				var j = lo;
				while (j < hi) {
					var off = j * bytesPerFrame;
					if (off + 1 < data.length) {
						var v = 0.0;
						if (buf.bitsPerSample == 16) {
							var s16 = (data[off + 1] << 8) | data[off];
							if (s16 >= 32768) s16 -= 65536;
							v = Math.abs(s16 / 32768);
						} else if (buf.bitsPerSample == 8) {
							v = Math.abs((data[off] - 128) / 128);
						}
						if (v > peak) peak = v;
					}
					j += step;
				}
				peaks.push(peak);
			}
			previewWave = peaks;
		} catch(e) {
			previewStatus = 'Decode failed: $e';
		}
		#end
	}

	function drawWaveform() {
		if (previewWave == null || previewWave.length == 0) return;
		var dl = ImGui.getWindowDrawList();
		var pos = ImGui.getCursorScreenPos();
		var w = ImGui.getContentRegionAvail().x;
		var h = 56.0;
		dl.addRectFilled([pos.x, pos.y, pos.x + w, pos.y + h], 0x33000000, 2);
		var cols = previewWave.length;
		var barW = Math.max(1, w / cols * 0.7);
		for (i in 0...cols) {
			var px = pos.x + (i + 0.5) / cols * w;
			var hh = Math.max(2, previewWave[i] * h);
			dl.addLine([px, pos.y + h / 2 - hh / 2, px, pos.y + h / 2 + hh / 2], 0xFF5EC9FF, barW);
		}
		ImGui.dummy(w, h);
	}

	function playSoundPreview() {
		#if sys
		stopSoundPreview();
		var path = Paths.assetsTree.getSpecificPath('assets/$previewWavePath');
		if (path == null) return;
		try {
			var snd = openfl.media.Sound.fromFile(path);
			if (snd != null) {
				previewSound = FlxG.sound.load(snd);
				previewSound.play();
			}
		} catch(e) previewStatus = 'Play failed: $e';
		#end
	}

	function stopSoundPreview() {
		if (previewSound != null) {
			previewSound.stop();
			previewSound.destroy();
			previewSound = null;
		}
	}

	// ============ SETTINGS PERSISTENCE ============

	function loadSettings() {
		try {
			var d:Dynamic = FlxG.save.data.sneEditor;
			if (d != null) {
				if (d.gizmoMode != null) gizmo.gizmoMode = d.gizmoMode;
				if (d.clickSelect != null) { clickSelect = d.clickSelect; clickSelectPtr.value = d.clickSelect; }
				if (d.showKeyOverlay != null) { showKeyOverlay = d.showKeyOverlay; showKeyOverlayPtr.value = d.showKeyOverlay; }
			if (d.showPerf != null) { showPerf = d.showPerf; showPerfPtr.value = d.showPerf; }
			}
		} catch(e) {}
		savedGizmoMode = gizmo.gizmoMode;
		savedClickSelect = clickSelect;
		savedKeyOverlay = showKeyOverlay;
		savedShowPerf = showPerf;
	}

	/** Writes editor settings to FlxG.save when any tracked value changed since last write. */
	function persistSettings() {
		if (gizmo.gizmoMode == savedGizmoMode && clickSelect == savedClickSelect && showKeyOverlay == savedKeyOverlay && showPerf == savedShowPerf) return;
		savedGizmoMode = gizmo.gizmoMode;
		savedClickSelect = clickSelect;
		savedKeyOverlay = showKeyOverlay;
		savedShowPerf = showPerf;
		try {
			FlxG.save.data.sneEditor = {gizmoMode: gizmo.gizmoMode, clickSelect: clickSelect, showKeyOverlay: showKeyOverlay, showPerf: showPerf};
			FlxG.save.flush();
		} catch(e) {}
	}

	// ============ FOCUS / SCREENSHOT ============

	/** Scrolls the object's camera so the selected object ends up centered on screen. */
	function focusSelected() {
		var o:FlxObject = selectedObject is FlxObject ? cast selectedObject : null;
		if (o == null) return;
		var cam = o.getDefaultCamera();
		if (cam == null) return;
		cam.scroll.set(
			o.x + o.width / 2 - (cam.width / cam.zoom) / 2,
			o.y + o.height / 2 - (cam.height / cam.zoom) / 2);
		runStatus = "Focused camera on selection";
	}

	/** Grabs the next rendered frame and writes it to exports/screenshot-N.png. */
	function takeScreenshot() {
		#if sys
		var win = FlxG.stage.window;
		if (win == null) { runStatus = "No window"; return; }
		var cb;
		cb = function(ctx:lime.graphics.RenderContext) {
			win.onRender.remove(cb);
			var gl = ctx.webgl;
			if (gl == null) { runStatus = "No GL context for screenshot"; return; }
			var w = Std.int(win.width * win.scale);
			var h = Std.int(win.height * win.scale);
			if (w <= 0 || h <= 0) { runStatus = "Window has no size"; return; }
			try {
				var pixels = new lime.utils.UInt8Array(w * h * 4);
				gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
				var out = new lime.utils.UInt8Array(w * h * 4);
				var row = w * 4;
				for (y in 0...h) {
					var dst = (h - 1 - y) * row;
					var src = y * row;
					for (i in 0...row) out[dst + i] = pixels[src + i];
				}
				var buf = new lime.graphics.ImageBuffer(out, w, h, 32, lime.graphics.PixelFormat.RGBA32);
				buf.premultiplied = false;
				var img = new lime.graphics.Image(buf);
				var png = img.encode(lime.graphics.ImageFileFormat.PNG);
				var dir = "exports";
				if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
				var n = 1;
				while (sys.FileSystem.exists('$dir/screenshot-$n.png')) n++;
				var path = '$dir/screenshot-$n.png';
				sys.io.File.saveBytes(path, png);
				runStatus = 'Saved $path';
			} catch(e) runStatus = 'Screenshot failed: $e';
		}
		win.onRender.add(cb, false, -10000);
		runStatus = "Capturing frame...";
		#end
	}

	// ============ MARQUEE ============

	/** Walks every visible FlxObject in the picked layer (or all layers). */
	function forEachSceneFlxObject(f:FlxObject->Void) {
		var states:Array<FlxState> = [];
		var st:FlxState = FlxG.state;
		while (st != null) { states.push(st); st = st.subState; }
		var li = stateLayerPtr.value - 1;
		if (li >= 0) states = li < states.length ? [states[li]] : [];
		for (s in states) {
			var all:Array<FlxBasic> = [];
			collectScene(cast s, all);
			for (m in all) if (m is FlxObject && m.visible && m.exists) f(cast m);
		}
	}

	/** Screen-space bounds of an object's rendered quad (transform-aware for sprites). */
	function objectScreenRect(o:FlxObject):{x0:Float, y0:Float, x1:Float, y1:Float} {
		var cam = o.getDefaultCamera();
		var sf = scrollFactorFor(o);
		var sprite:FlxSprite = o is FlxSprite ? cast o : null;
		var corners:Array<FlxPoint> = [];
		if (sprite != null && sprite.frame != null) {
			@:privateAccess var mat = sprite._matrix;
			for (c in [
				FlxPoint.get(0, 0), FlxPoint.get(sprite.frame.frame.width, 0),
				FlxPoint.get(sprite.frame.frame.width, sprite.frame.frame.height), FlxPoint.get(0, sprite.frame.frame.height)
			]) {
				c.transform(mat);
				corners.push(gizmo.toScreenPoint(c, cam, sf));
			}
		} else {
			for (c in [
				FlxPoint.get(o.x, o.y), FlxPoint.get(o.x + o.width, o.y),
				FlxPoint.get(o.x + o.width, o.y + o.height), FlxPoint.get(o.x, o.y + o.height)
			]) corners.push(gizmo.toScreenPoint(c, cam, sf));
		}
		if (corners.length == 0) return null;
		var x0 = corners[0].x, y0 = corners[0].y, x1 = x0, y1 = y0;
		for (p in corners) {
			if (p.x < x0) x0 = p.x; if (p.y < y0) y0 = p.y;
			if (p.x > x1) x1 = p.x; if (p.y > y1) y1 = p.y;
		}
		for (p in corners) p.put();
		return {x0: x0, y0: y0, x1: x1, y1: y1};
	}

	// ============ ASSET BROWSER ============

	function drawAssetBrowser() {
		#if sys
		if (!assetBrowserOpen.value) return;
		if (assetBrowserList == null) {
			assetBrowserList = [];
			try {
				var base = Paths.assetsTree.getSpecificPath('assets/images');
				if (base != null && sys.FileSystem.isDirectory(base))
					walkImages(base, 'assets/images', assetBrowserList);
			} catch(e) assetBrowserStatus = 'listing failed: $e';
		}
		ImGui.setNextWindowSize(360, 440, ImGuiCond.FirstUseEver);
		if (ImGui.begin("Asset Browser##ab", assetBrowserOpen)) {
			ImGui.setNextItemWidth(-1);
			ImGui.inputTextWithHint("##abFilter", "filter...", assetBrowserFilter);
			var filter = StringTools.trim(assetBrowserFilter.value).toLowerCase();
			if (ImGui.beginChild("##abList", 0, 240)) {
				for (path in assetBrowserList) {
					var id = path.substr('assets/images/'.length);
					if (filter != "" && id.toLowerCase().indexOf(filter) == -1) continue;
					if (ImGui.selectable(id, assetBrowserSel == path)) {
						if (assetBrowserSel != path) {
							assetBrowserSel = path;
							assetBrowserBmd = null;
							try assetBrowserBmd = Assets.getBitmapData(path)
							catch(e) assetBrowserStatus = 'load failed: $e';
						}
					}
				}
			}
			ImGui.endChild();
			if (assetBrowserBmd != null) {
				var maxW = 320.0, maxH = 120.0;
				var sc = Math.min(maxW / assetBrowserBmd.width, maxH / assetBrowserBmd.height);
				if (sc > 1.5) sc = 1.5;
				ImGui.image(ImTextureID.fromBitmapData(assetBrowserBmd), assetBrowserBmd.width * sc, assetBrowserBmd.height * sc);
			}
			if (assetBrowserSel != null) {
				if (ImGui.button("Add to scene##ab")) spawnBrowserAsset(null);
				ImGui.sameLine();
				if (ImGui.button("Click to place##ab")) {
					assetClickPlace = true;
					runStatus = "Click in the scene to place " + assetBrowserSel;
				}
			}
			if (assetBrowserStatus != "") ImGui.textWrapped(assetBrowserStatus);
		}
		ImGui.end();
		#end
	}

	function walkImages(dir:String, prefix:String, out:Array<String>) {
		for (f in sys.FileSystem.readDirectory(dir)) {
			var p = dir + '/' + f;
			if (sys.FileSystem.isDirectory(p)) walkImages(p, prefix + '/' + f, out);
			else {
				var lower = f.toLowerCase();
				if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg')) out.push(prefix + '/' + f);
			}
		}
	}

	/** Spawns the browser-selected image as a sprite at the camera center (or where clicked). */
	function spawnBrowserAsset(?wp:FlxPoint) {
		var path = assetBrowserSel;
		if (path == null || !Assets.exists(path)) { runStatus = "No asset selected"; return; }
		var parent = getEditParent();
		var varName = '__editor_${++editorCounter}';
		var cam = FlxG.camera;
		var nx = wp != null ? wp.x : (cam != null ? cam.scroll.x + FlxG.width / cam.zoom / 2 - 40 : 100);
		var ny = wp != null ? wp.y : (cam != null ? cam.scroll.y + FlxG.height / cam.zoom / 2 - 40 : 100);
		var s = new FlxSprite(nx, ny);
		s.loadGraphic(path);
		parent.add(s);
		editorNames.set(s, varName);
		var short = shortImageKey(path);
		addedObjects.push({
			obj: s, varName: varName, typeName: "flixel.FlxSprite",
			createCode: 'new flixel.FlxSprite($nx, $ny, ' + (short != null ? 'Paths.image("${escapeHaxe(short)}")' : '"${escapeHaxe(path)}"') + ')',
			parent: parent
		});
		selectObject(s);
		markEdited(s);
		runStatus = 'Added ${path.substr(14)}';
	}

	function checkForSelectedObjectThisFrame(object:InspectorObject) {
		if (selectedObjectValidThisFrame) return;
		for (member in object.members) {
			if (member.obj == selectedObject) {
				selectedObjectValidThisFrame = true;
				selectedObjectData = member;
				return;
			}
			if (member.members.length > 0) {
				checkForSelectedObjectThisFrame(member);
			}
		}
	}

	inline function treeFilterActive() return StringTools.trim(treeFilter.value) != "";

	function treeMatch(m:InspectorObject):Bool {
		var f = StringTools.trim(treeFilter.value).toLowerCase();
		if (m.name != null && m.name.toLowerCase().indexOf(f) >= 0) return true;
		if (m.type != null && m.type.toLowerCase().indexOf(f) >= 0) return true;
		for (c in m.members) if (treeMatch(c)) return true;
		return false;
	}

	function generateTreeForMembers(id:String, object:InspectorObject) {
		for (index => member in object.members) {
			if (treeFilterActive() && !treeMatch(member)) continue;
			var valid = member.obj != null;
			var nodeID = id + object.name + index;
			var flags = treeFilterActive() ? ImGuiTreeNodeFlags.DefaultOpen : ImGuiTreeNodeFlags.None;
			if (member.members.length == 0) flags |= ImGuiTreeNodeFlags.Leaf;
			if (valid && (member.obj == selectedObject || (member.obj is FlxBasic && selectedObjects.contains(cast member.obj))))
				flags |= ImGuiTreeNodeFlags.Selected;
			if (ImGui.treeNodeEx(nodeID, flags, member.name + (valid ? " (" + member.type + ")" : ""))) {
				if (valid && ImGui.isItemClicked()) {
					selectObject(member.obj, ImGui.isKeyDown(ImGuiKey.LeftCtrl) || ImGui.isKeyDown(ImGuiKey.RightCtrl));
				}
				if (valid) showNodeExtras(member);
				if (valid && member.members.length > 0) {
					generateTreeForMembers(nodeID, member);
				}
				ImGui.treePop();
			}
		}
	}

	/** Right-click menu + drag-to-reparent attached to a tree node. */
	function showNodeExtras(member:InspectorObject) {
		var obj = member.obj;
		if (ImGui.beginPopupContextItem('ctx_${member.name}_${member.memberIndex}')) {
			if (ImGui.menuItem("Select")) selectObject(obj);
			if (obj is FlxBasic) {
				if (ImGui.menuItem("Duplicate")) duplicateObject(cast obj);
				if (ImGui.menuItem("Add Keyframe")) addKeyframe(cast obj, 0);
				if (ImGui.menuItem("Delete")) deleteInspectorObject(cast obj);
				var e = exprFor(cast obj);
				if (e != null && ImGui.menuItem('Copy path ($e)')) ImGui.setClipboardText(e);
			}
			ImGui.endPopup();
		}
		if (obj is FlxBasic && ImGui.beginDragDropSource()) {
			ImGui.setDragDropPayload(new ImGuiPayload("sne-obj", obj));
			ImGui.text(member.name);
			ImGui.endDragDropSource();
		}
		if (obj is FlxGroup && ImGui.beginDragDropTarget()) {
			var p = ImGui.acceptDragDropPayload("sne-obj");
			if (p != null && p.data is FlxBasic && p.data != obj)
				reparentObject(cast p.data, cast obj);
			ImGui.endDragDropTarget();
		}
	}

	/** True if `obj` is a group containing `g` (can't reparent into own child). */
	function groupContainsGroup(obj:FlxBasic, g:FlxGroup):Bool {
		if (!(obj is FlxGroup)) return false;
		var og:FlxGroup = cast obj;
		if (og.members == null) return false;
		for (m in og.members) {
			if (m == g) return true;
			if (groupContainsGroup(m, g)) return true;
		}
		return false;
	}

	public function reparentObject(obj:FlxBasic, newParent:FlxGroup) {
		objectsDirty = true;
		if (groupContainsGroup(obj, newParent)) return;
		var old = findParentGroup(obj, cast FlxG.state);
		if (old == null || old == newParent) return;
		old.members.remove(obj);
		newParent.add(obj);
		reparentOps.push({obj: obj, from: old, to: newParent});
		for (a in addedObjects)
			if (a.obj == obj) a.parent = newParent;
		markEdited(obj);
	}

	function selectObject(obj:Dynamic, additive:Bool = false) {
		if (additive && obj is FlxBasic) {
			var b:FlxBasic = cast obj;
			if (selectedObjects.contains(b)) {
				selectedObjects.remove(b);
				if (selectedObject == b && selectedObjects.length > 0)
					selectedObject = selectedObjects[selectedObjects.length - 1];
			} else {
				if (selectedObject is FlxBasic && !selectedObjects.contains(cast selectedObject))
					selectedObjects.push(cast selectedObject);
				if (!selectedObjects.contains(b)) selectedObjects.push(b);
				selectedObject = b;
			}
			justChangedObject = true;
		} else {
			selectedObjects.resize(0);
			if (selectedObject != obj) {
				selectedObject = obj;
				justChangedObject = true;
			}
		}
	}

	/** Primary selection + Ctrl-clicked extras, in click order. */
	function selectionList():Array<FlxBasic> {
		var out = selectedObjects.copy();
		if (selectedObject is FlxBasic && !out.contains(cast selectedObject))
			out.push(cast selectedObject);
		return out;
	}

	// ============ STATE EDITOR METHODS ============

	/** Marks a pre-existing object as edited so it gets written to the patch on save. */
	public function markEdited(obj:FlxBasic) {
		if (obj != null) {
			editedObjects.set(obj, true);
			queueSnapshot();
		}
	}

	public function getOrCreateHooks(obj:FlxBasic) {
		var h = objectHooks.get(obj);
		if (h == null)
			objectHooks.set(obj, h = {updateCode: "", clickCode: "", code: null, script: null, fromPatch: false});
		return h;
	}

	function getEditParent():FlxGroup {
		if (selectedObject is FlxGroup) return cast selectedObject;
		if (selectedObjectData != null && selectedObjectData.groupParent != null && selectedObjectData.groupParent.obj is FlxGroup)
			return cast selectedObjectData.groupParent.obj;
		return cast FlxG.state; // FlxState is a group
	}

	function createInspectorObject() {
		objectsDirty = true;
		var parent = getEditParent();
		var varName = '__editor_${++editorCounter}';
		var obj:FlxBasic = null;
		var typeName:String = null;
		var code:String = null;

		switch (addKind.value) {
			case 0:
				var path = addImagePath.value;
				var s = new FlxSprite(0, 0);
				if (path != null && path.length > 0)
					s.loadGraphic(Paths.image(path));
				else
					s.makeGraphic(80, 80, 0xFF7F00FF);
				s.scrollFactor.set();
				s.antialiasing = true;
				obj = s;
				typeName = "flixel.FlxSprite";
				code = 'new flixel.FlxSprite(0, 0, Paths.image("${escapeHaxe(path)}"))';
			case 1:
				obj = new FunkinText(0, 0, 0, addTextContent.value, addTextSize.value);
				typeName = "funkin.backend.FunkinText";
				code = 'new funkin.backend.FunkinText(0, 0, 0, "${escapeHaxe(addTextContent.value)}", ${addTextSize.value})';
			case 2:
				var t = new FunkinText(0, 0, 0, addTextContent.value, addTextSize.value);
				t.color = 0xFF5BCEFA;
				obj = t;
				typeName = "funkin.backend.FunkinText";
				code = 'new funkin.backend.FunkinText(0, 0, 0, "${escapeHaxe(addTextContent.value)}", ${addTextSize.value})';
				var h = getOrCreateHooks(obj);
				h.clickCode = 'trace("${escapeHaxe(addTextContent.value)} clicked!");';
			case 3:
				obj = new FlxTypedGroup();
				typeName = "flixel.group.FlxTypedGroup";
				code = "new flixel.group.FlxTypedGroup()";
			case 4:
				var made = evalSnippet('return ${addCustomCode.value};');
				if (made is FlxBasic) {
					obj = cast made;
					typeName = "Dynamic";
					code = '(${addCustomCode.value})';
				} else {
					saveStatus = "Expr didn't return a FlxBasic";
				}
		}
		if (obj == null) return;

		parent.add(obj);
		editorNames.set(obj, varName);
		addedObjects.push({obj: obj, varName: varName, typeName: typeName, createCode: code, parent: parent});
		selectObject(obj);
		queueSnapshot();
	}

	/** Evaluates hscript code with 'obj'/'state' bound; returns the __run function result. */
	function evalSnippet(code:String):Dynamic {
		runStatus = "";
		try {
			var s = Script.fromString('function __run() {\n$code\n}', 'inspector-eval.hx');
			s.setParent(FlxG.state);
			s.set("obj", selectedObject);
			s.set("state", FlxG.state);
			s.load();
			var result = s.call("__run");
			return result is Script ? null : result;
		} catch(e) {
			runStatus = 'Error: $e';
			Logs.error('Inspector eval: $e');
			return null;
		}
	}

	function runSnippet() {
		evalSnippet(codeRunnerText.value);
		if (runStatus == "") runStatus = "Ran OK";
	}

	/** Renames an editor-created object (affects tree label + patch var name). */
	public function renameObject(obj:FlxBasic, name:String) {
		objectsDirty = true;
		if (name == null || name.length == 0) {
			editorNames.remove(obj);
			return;
		}
		editorNames.set(obj, name);
		for (a in addedObjects)
			if (a.obj == obj) a.varName = sanitizeVarName(name);
	}

	public static function sanitizeVarName(s:String):String {
		var b = new StringBuf();
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			var ok = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95;
			if (i == 0 && c >= 48 && c <= 57) b.addChar(95);
			b.addChar(ok ? c : 95);
		}
		var r = b.toString();
		return r.length == 0 ? "_obj" : r;
	}

	/** Moves an object by `dir` slots in its group's draw order. */
	public function moveObject(obj:FlxBasic, dir:Int) {
		objectsDirty = true;
		var parent = findParentGroup(obj, cast FlxG.state);
		if (parent == null || parent.members == null) return;
		var i = parent.members.indexOf(obj);
		if (i == -1) return;
		var n = i + dir;
		if (dir < 0 && n < 0) n = 0;
		if (dir > 0 && n >= parent.members.length) n = parent.members.length - 1;
		if (n == i) return;
		parent.members.remove(obj);
		parent.members.insert(n, obj);
		moveOps.push({obj: obj, parent: parent, index: n});
		markEdited(obj);
	}

	/** Duplicates a sprite/text into the same group. */
	public function duplicateObject(obj:FlxBasic) {
		objectsDirty = true;
		var parent = findParentGroup(obj, cast FlxG.state);
		if (parent == null) return;
		var varName = '__editor_${++editorCounter}';
		var copy:FlxBasic = null;
		var code:String = null;
		var typeName:String = "Dynamic";
		var cloneSource:FlxSprite = null;

		if (obj is FlxText) {
			var t:FlxText = cast obj;
			var nt = new FunkinText(t.x, t.y, t.fieldWidth, t.text, t.size);
			nt.color = t.color;
			nt.alignment = t.alignment;
			copy = nt;
			typeName = "funkin.backend.FunkinText";
			code = 'new funkin.backend.FunkinText(${t.x}, ${t.y}, ${t.fieldWidth}, "${escapeHaxe(t.text)}", ${t.size})';
		} else if (obj is FlxSprite) {
			var s:FlxSprite = cast obj;
			var ns = new FlxSprite(s.x, s.y);
			ns.loadGraphicFromSprite(s);
			for (a in s.animation.getAnimationList())
				ns.animation.add(a.name, a.frames.copy(), a.frameRate, a.looped, a.flipX, a.flipY);
			if (s.animation.curAnim != null) ns.animation.play(s.animation.curAnim.name, true);
			ns.scale.copyFrom(s.scale);
			ns.updateHitbox();
			copy = ns;
			cloneSource = s;
			typeName = "flixel.FlxSprite";
			code = "new flixel.FlxSprite(0, 0)";
		} else if (obj is FlxTypedGroup) {
			copy = new FlxTypedGroup();
			typeName = "flixel.group.FlxTypedGroup";
			code = "new flixel.group.FlxTypedGroup()";
		}
		if (copy == null) return;

		parent.add(copy);
		editorNames.set(copy, varName);
		addedObjects.push({obj: copy, varName: varName, typeName: typeName, createCode: code, parent: parent, cloneSource: cloneSource});
		selectObject(copy);
	}

	/** Snapshots the selected object's editable props for Ctrl+V pasting. */
	public function copySelected() {
		var b:FlxBasic = selectedObject is FlxBasic ? cast selectedObject : null;
		if (b == null) { runStatus = "Nothing selected"; return; }
		var o:FlxObject = b is FlxObject ? cast b : null;
		var s:FlxSprite = b is FlxSprite ? cast b : null;
		var t:FlxText = b is FlxText ? cast b : null;
		clipboard = {
			kind: t != null ? 2 : (s != null ? 1 : (b is FlxGroup ? 3 : 0)),
			x: o != null ? o.x : 0, y: o != null ? o.y : 0, angle: o != null ? o.angle : 0,
			alpha: s != null ? s.alpha : 1, color: s != null ? s.color : 0xFFFFFFFF,
			sx: s != null ? s.scale.x : 1, sy: s != null ? s.scale.y : 1,
			w: o != null ? o.width : 0, h: o != null ? o.height : 0,
			scrollX: o != null ? o.scrollFactor.x : 1, scrollY: o != null ? o.scrollFactor.y : 1,
			visible: b.visible,
			text: t != null ? t.text : "", size: t != null ? t.size : 24,
			fieldW: t != null ? t.fieldWidth : 0, fieldH: t != null ? t.fieldHeight : 0,
			graphKey: s != null && s.graphic != null ? s.graphic.key : null
		};
		runStatus = "Copied";
	}

	/** `assets/images/x.png` -> `x` for Paths.image() calls; null if the key isn't an images/ asset. */
	static function shortImageKey(key:String):Null<String> {
		if (key == null || !key.startsWith('assets/images/')) return null;
		var k = key.substr(14);
		var dot = k.lastIndexOf('.');
		return dot == -1 ? k : k.substr(0, dot);
	}

	/** Creates a new object from the Ctrl+C snapshot, offset so it doesn't overlap the source. */
	public function pasteClipboard() {
		objectsDirty = true;
		var c = clipboard;
		if (c == null) { runStatus = "Clipboard empty"; return; }
		var parent = getEditParent();
		var varName = '__editor_${++editorCounter}';
		var nx:Float = c.x + 24;
		var ny:Float = c.y + 24;
		var obj:FlxBasic = null;
		var typeName = "Dynamic";
		var code:String = null;

		switch (c.kind) {
			case 1:
				var s = new FlxSprite(nx, ny);
				var short = shortImageKey(c.graphKey);
				if (c.graphKey != null && Assets.exists(c.graphKey)) s.loadGraphic(c.graphKey);
				else s.makeGraphic(80, 80, 0xFF7F00FF);
				s.scale.set(c.sx, c.sy);
				s.alpha = c.alpha;
				s.color = c.color;
				obj = s;
				typeName = "flixel.FlxSprite";
				code = c.graphKey != null
					? 'new flixel.FlxSprite($nx, $ny, ' + (short != null ? 'Paths.image("${escapeHaxe(short)}")' : '"${escapeHaxe(c.graphKey)}"') + ')'
					: 'new flixel.FlxSprite($nx, $ny)';
			case 2:
				var t = new FunkinText(nx, ny, c.fieldW, c.text, c.size);
				t.fieldHeight = c.fieldH;
				t.color = c.color;
				t.alpha = c.alpha;
				obj = t;
				typeName = "funkin.backend.FunkinText";
				code = 'new funkin.backend.FunkinText($nx, $ny, ${c.fieldW}, "${escapeHaxe(c.text)}", ${c.size})';
			case 3:
				obj = new FlxTypedGroup();
				typeName = "flixel.group.FlxTypedGroup";
				code = "new flixel.group.FlxTypedGroup()";
			default:
				obj = new FlxObject(nx, ny, c.w, c.h);
				typeName = "flixel.FlxObject";
				code = 'new flixel.FlxObject($nx, $ny, ${c.w}, ${c.h})';
		}
		if (obj is FlxObject) {
			var oo:FlxObject = cast obj;
			oo.angle = c.angle;
			oo.scrollFactor.set(c.scrollX, c.scrollY);
		}
		obj.visible = c.visible;

		parent.add(obj);
		editorNames.set(obj, varName);
		addedObjects.push({obj: obj, varName: varName, typeName: typeName, createCode: code, parent: parent});
		selectObject(obj);
		markEdited(obj);
		runStatus = "Pasted";
	}

	/** Aligns every selected object on the given edge/center (mode: l, cx, r, t, cy, b) or spreads them (dh, dv). */
	public function alignSelection(mode:String) {
		var sel = [for (o in selectionList()) if (o is FlxObject) (cast o : FlxObject)];
		if (sel.length < 2) { runStatus = "Select 2+ objects (Ctrl+click)"; return; }
		var xs = [for (o in sel) o.x], rs = [for (o in sel) o.x + o.width];
		var ys = [for (o in sel) o.y], bs = [for (o in sel) o.y + o.height];
		function min(a:Array<Float>) { var m = a[0]; for (v in a) if (v < m) m = v; return m; }
		function max(a:Array<Float>) { var m = a[0]; for (v in a) if (v > m) m = v; return m; }
		switch (mode) {
			case "l": for (o in sel) o.x = min(xs);
			case "r": for (o in sel) o.x = max(rs) - o.width;
			case "t": for (o in sel) o.y = min(ys);
			case "b": for (o in sel) o.y = max(bs) - o.height;
			case "cx": for (o in sel) o.x = (min(xs) + max(rs)) / 2 - o.width / 2;
			case "cy": for (o in sel) o.y = (min(ys) + max(bs)) / 2 - o.height / 2;
			case "dh", "dv":
				var horiz = mode == "dh";
				sel.sort(function(a, b) { var d = (horiz ? a.x : a.y) - (horiz ? b.x : b.y); return d < 0 ? -1 : (d > 0 ? 1 : 0); });
				var span = horiz ? (max(rs) - min(xs)) : (max(bs) - min(ys));
				var total = 0.0; for (o in sel) total += horiz ? o.width : o.height;
				var gap = (span - total) / (sel.length - 1);
				var pos = horiz ? min(xs) : min(ys);
				for (o in sel) {
					if (horiz) { o.x = pos; pos += o.width + gap; }
					else { o.y = pos; pos += o.height + gap; }
				}
			default:
		}
		for (o in sel) markEdited(o);
		runStatus = 'Aligned ${sel.length} objects';
	}

	/** Starts recording `seconds` of the object's live motion into its key track. */
	public function bakeMotion(obj:FlxBasic, seconds:Float) {
		baking = {obj: obj, keys: [], t: 0, nextT: 0, dur: Math.max(0.1, seconds)};
		runStatus = 'Baking ${FlxMath.roundDecimal(seconds, 1)}s of motion...';
	}

	/** Records an animation operation for patch export. */
	public function recordAnimOp(sprite:FlxBasic, op:String) {
		var ops = animOps.get(sprite);
		if (ops == null) animOps.set(sprite, ops = []);
		ops.push(op);
		markEdited(sprite);
	}

	/** The state whose patch session was last adopted into the editor. */
	var lastAdoptedState:FlxState = null;

	/**
	 * Reads the SNE-META manifest out of the state's patch file (if any) and re-adopts
	 * editor-created objects, hooks, keyframes, anim ops and snippets into the live
	 * session, so patch-made objects stay editable and re-export stays idempotent.
	 */
	function adoptPatch(state:FlxState) {
		objectsDirty = true;
		if (state == lastAdoptedState) return;
		lastAdoptedState = state;
		undoStack.resize(0);
		redoStack.resize(0);
		snapBaseline = null;
		snapPending = false;
		adoptSnapshot = captureSnapshot();
		namedSnapshots.clear();
		selectedObjects.resize(0);
		baking = null;
		#if sys
		if (!(state is MusicBeatState)) return;
		var mbs:MusicBeatState = cast state;
		var name = mbs.scriptName ?? Type.getClassName(Type.getClass(state)).split('.').pop();
		var base = resolvePatchLibraryPath();
		if (base == null) return;
		var path = '$base/data/states/$name.hx';
		if (!sys.FileSystem.exists(path)) return;
		var src = sys.io.File.getContent(path);
		var mi = src.indexOf('// SNE-META ');
		if (mi == -1) return;
		var eol = src.indexOf('\n', mi);
		if (eol == -1) eol = src.length;
		var meta:Dynamic = try haxe.Json.parse(StringTools.trim(src.substring(mi + 12, eol))) catch(e) {
			Logs.warn('State Editor: failed to parse SNE-META: $e');
			return;
		};
		if (meta == null) return;

		// editor-created objects
		for (od in (meta.objs : Array<Dynamic>)) {
			var obj:Dynamic = try mbs.stateScripts.get(od.v) catch(e) null;
			if (obj is FlxBasic && addedObjects.filter(a -> a.varName == od.v).length == 0) {
				editorNames.set(cast obj, od.v);
				addedObjects.push({obj: cast obj, varName: od.v, typeName: od.t, createCode: od.c,
					parent: findParentGroup(cast obj, state)});
			}
		}
		// edited pre-existing objects
		for (e in (meta.edit : Array<Dynamic>)) {
			var o = resolveSceneExpr(state, e);
			if (o is FlxBasic) markEdited(cast o);
		}
		// removals
		for (e in (meta.rem : Array<Dynamic>)) removedExpressions.push(e);
		// hooks (mark fromPatch - the loaded patch already executes them)
		for (name in Reflect.fields(meta.hooks)) {
			var o = resolveSceneExpr(state, name);
			if (!(o is FlxBasic)) continue;
			var hd:Dynamic = Reflect.field(meta.hooks, name);
			objectHooks.set(cast o, {updateCode: hd.u ?? "", clickCode: hd.c ?? "", code: null, script: null, fromPatch: true});
		}
		// keyframe tracks
		for (name in Reflect.fields(meta.trk)) {
			var o = resolveSceneExpr(state, name);
			if (!(o is FlxBasic)) continue;
			var td:Dynamic = Reflect.field(meta.trk, name);
			var tr = getOrCreateTrack(cast o);
			tr.mode = td.m ?? 1;
			tr.keys = [for (k in (td.k : Array<Dynamic>))
				{t: k.t, x: k.x, y: k.y, angle: k.a, scaleX: k.sx, scaleY: k.sy, alpha: k.al, ease: k.e}];
			// bind to the patch's live track so Play/Pause drives it
			var live:Array<Dynamic> = try mbs.stateScripts.get('__sneKeyTracks') catch(e) null;
			if (live != null)
				for (pt in live)
					if (pt.o == o) { tr.patchTrack = pt; break; }
		}
		// animation ops
		for (name in Reflect.fields(meta.anim)) {
			var o = resolveSceneExpr(state, name);
			if (!(o is FlxBasic)) continue;
			var ops:Array<String> = [];
			for (op in (Reflect.field(meta.anim, name) : Array<Dynamic>)) ops.push(op);
			animOps.set(cast o, ops);
		}
		// draw-order ops
		for (m in (meta.mov : Array<Dynamic>)) {
			var o = resolveSceneExpr(state, m.e);
			var p = resolveSceneExpr(state, m.p);
			if (o is FlxBasic)
				moveOps.push({obj: cast o, parent: (p is FlxGroup) ? (cast p : FlxGroup) : cast state, index: m.i});
		}
		// queued snippets
		for (s in (meta.snip : Array<Dynamic>)) patchSnippets.push({code: s.c, phase: s.p});
		#end
	}

	/** Resolves a member-path expression (a.b, a.members[2]) or a patch variable name to a live object. */
	function resolveSceneExpr(state:FlxState, expr:String):Dynamic {
		if (expr == null || expr == "") return null;
		var cur:Dynamic = state;
		for (seg in expr.split('.')) {
			if (seg == "") return null;
			var bracket = seg.indexOf('[');
			var field = bracket == -1 ? seg : seg.substr(0, bracket);
			cur = Reflect.getProperty(cur, field);
			if (cur == null && state is MusicBeatState)
				cur = try (cast state : MusicBeatState).stateScripts.get(field) catch(e) null;
			if (cur == null) return null;
			if (bracket != -1) {
				var close = seg.indexOf(']', bracket);
				var idx = Std.parseInt(seg.substring(bracket + 1, close));
				var members:Array<Dynamic> = cur.members;
				if (idx == null || members == null || idx < 0 || idx >= members.length) return null;
				cur = members[idx];
			}
		}
		return cur;
	}

	public function getOrCreateTrack(obj:FlxBasic):InspectorTrack {
		var tr = keyTracks.get(obj);
		if (tr == null)
			keyTracks.set(obj, tr = {keys: [], mode: 1, playing: false, t: 0.0, dir: 1, sel: -1});
		return tr;
	}

	public function getEaseNames():Array<String> {
		if (easeNames == null) {
			easeNames = [];
			for (f in Type.getClassFields(flixel.tweens.FlxEase))
				if (Reflect.isFunction(Reflect.field(flixel.tweens.FlxEase, f)))
					easeNames.push(f);
			easeNames.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		}
		return easeNames;
	}

	public function snapshotKey(obj:FlxBasic, t:Float, ?x:Float, ?y:Float):InspectorKeyframe {
		var o = obj is FlxObject ? (cast obj : FlxObject) : null;
		var s = obj is FlxSprite ? (cast obj : FlxSprite) : null;
		return {
			t: t,
			x: x ?? (o != null ? o.x : 0),
			y: y ?? (o != null ? o.y : 0),
			angle: o != null ? o.angle : 0,
			scaleX: s != null ? s.scale.x : 1,
			scaleY: s != null ? s.scale.y : 1,
			alpha: s != null ? s.alpha : 1,
			ease: "quadInOut"
		};
	}

	public function addKeyframe(obj:FlxBasic, t:Float, ?x:Float, ?y:Float) {
		var tr = getOrCreateTrack(obj);
		var k = snapshotKey(obj, t, x, y);
		tr.keys.push(k);
		sortTrack(tr);
		tr.sel = tr.keys.indexOf(k);
		syncPatchTrack(tr);
		markEdited(obj);
	}

	/**
	 * For tracks adopted from a saved patch: copies edited keys/mode into the
	 * patch script's live track so the running animation reflects edits
	 * immediately (eases are resolved to FlxEase functions).
	 */
	public function syncPatchTrack(tr:InspectorTrack) {
		var pt = tr.patchTrack;
		if (pt == null) return;
		var arr:Array<Dynamic> = [];
		for (k in tr.keys)
			arr.push({t: k.t, x: k.x, y: k.y, angle: k.angle, sx: k.scaleX, sy: k.scaleY, alpha: k.alpha,
				ease: Reflect.field(flixel.tweens.FlxEase, k.ease)});
		pt.keys = arr;
		pt.mode = tr.mode;
	}

	public function sortTrack(tr:InspectorTrack) {
		tr.keys.sort(function(a, b) return a.t < b.t ? -1 : (a.t > b.t ? 1 : 0));
	}

	public function armClickCapture(obj:FlxBasic) {
		clickCaptureFor = clickCaptureFor == obj ? null : obj;
	}

	public function trackDuration(tr:InspectorTrack):Float {
		return tr.keys.length == 0 ? 0 : tr.keys[tr.keys.length - 1].t;
	}

	public function playTrack(tr:InspectorTrack) {
		if (tr.patchTrack != null) {
			// adopted track: drive the patch script's live copy
			var pt:Dynamic = tr.patchTrack;
			pt.playing = !(pt.playing != false);
			tr.playing = pt.playing;
			var dur = trackDuration(tr);
			if (tr.playing && tr.mode == 3) { pt.dir = -1; if (pt.t <= 0 || pt.t >= dur) pt.t = dur; }
			else if (tr.playing && pt.t >= dur) pt.t = 0;
			return;
		}
		tr.playing = !tr.playing;
		if (!tr.playing) return;
		var dur = trackDuration(tr);
		if (tr.mode == 3) {
			tr.dir = -1;
			if (tr.t <= 0 || tr.t >= dur) tr.t = dur;
		} else {
			tr.dir = 1;
			if (tr.t >= dur) tr.t = 0;
		}
	}

	function advanceTrack(tr:InspectorTrack, elapsed:Float) {
		var dur = trackDuration(tr);
		if (dur <= 0) { tr.playing = false; return; }
		// mode 4: t is in beats, driven by Conductor.bpm
		tr.t += elapsed * tr.dir * (tr.mode == 4 ? (Conductor.bpm / 60) : 1);
		switch (tr.mode) {
			case 1, 4:
				tr.t = tr.t % dur;
				if (tr.t < 0) tr.t += dur;
			case 2:
				if (tr.t > dur) { tr.t = dur - (tr.t - dur); tr.dir = -1; }
				if (tr.t < 0) { tr.t = -tr.t; tr.dir = 1; }
			case 3:
				if (tr.t <= 0) { tr.t = 0; tr.playing = false; }
			default:
				if (tr.t >= dur) { tr.t = dur; tr.playing = false; }
		}
	}

	/** Evaluates the track at its current time and applies it to the object. */
	public function applyTrack(obj:FlxBasic, tr:InspectorTrack) {
		if (tr.keys.length == 0 || !(obj is FlxObject)) return;
		var o:FlxObject = cast obj;
		var p = evalTrackPose(tr, tr.t);
		o.x = p.x;
		o.y = p.y;
		o.angle = p.angle;
		if (obj is FlxSprite) {
			var s:FlxSprite = cast obj;
			s.scale.set(p.scaleX, p.scaleY);
			s.alpha = p.alpha;
		}
	}

	/** Samples the track's eased pose at time `t`. Public so the editor can preview paths. */
	public function evalTrackPose(tr:InspectorTrack, t:Float):{x:Float, y:Float, angle:Float, scaleX:Float, scaleY:Float, alpha:Float} {
		var keys = tr.keys;
		var a = keys[0];
		var b = keys[0];
		var u = 1.0;
		if (t > keys[0].t) {
			if (t >= keys[keys.length - 1].t) {
				a = b = keys[keys.length - 1];
			} else {
				for (i in 0...keys.length - 1) {
					if (t >= keys[i].t && t <= keys[i + 1].t) {
						a = keys[i];
						b = keys[i + 1];
						var span = b.t - a.t;
						u = span <= 0 ? 1.0 : (t - a.t) / span;
						if (a.ease != null) {
							var ef = Reflect.field(flixel.tweens.FlxEase, a.ease);
							if (ef != null) u = ef(u);
						}
						break;
					}
				}
			}
		}
		return {
			x: a.x + (b.x - a.x) * u,
			y: a.y + (b.y - a.y) * u,
			angle: a.angle + (b.angle - a.angle) * u,
			scaleX: a.scaleX + (b.scaleX - a.scaleX) * u,
			scaleY: a.scaleY + (b.scaleY - a.scaleY) * u,
			alpha: a.alpha + (b.alpha - a.alpha) * u
		};
	}

	/** Picks the topmost visible object under the mouse, searching substates first. */
	function pickSceneObject():FlxBasic {
		var states:Array<FlxState> = [];
		var state:FlxState = FlxG.state;
		while (state != null) {
			states.push(state);
			state = state.subState;
		}
		if (stateLayerPtr.value > 0) {
			var li = stateLayerPtr.value - 1;
			return li < states.length ? pickObjectAt(cast states[li]) : null;
		}
		var i = states.length - 1;
		while (i >= 0) {
			var r = pickObjectAt(cast states[i]);
			if (r != null) return r;
			i--;
		}
		return null;
	}

	/** True if (px,py) is inside convex quad a-b-c-d (same winding, world coords). */
	static function pointInQuad(px:Float, py:Float, ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float, dx:Float, dy:Float):Bool {
		var s1 = (bx - ax) * (py - ay) - (px - ax) * (by - ay);
		var s2 = (cx - bx) * (py - by) - (px - bx) * (cy - by);
		var s3 = (dx - cx) * (py - cy) - (px - cx) * (dy - cy);
		var s4 = (ax - dx) * (py - dy) - (px - dx) * (ay - dy);
		return (s1 >= 0 && s2 >= 0 && s3 >= 0 && s4 >= 0) || (s1 <= 0 && s2 <= 0 && s3 <= 0 && s4 <= 0);
	}

	/**
	 * Hit-test the sprite's real drawn footprint (offset/scale/angle-aware via _matrix)
	 * rather than its raw x/y/w/h hitbox, in the object's own camera + scrollFactor space.
	 */
	function objectHitAt(m:FlxObject):Bool {
		var mp = ImGui.getMousePos();
		var wp = gizmo.screenToWorldPoint(FlxPoint.get(mp.x, mp.y), m.getDefaultCamera(), scrollFactorFor(m));
		var hit = false;
		var sprite:FlxSprite = m is FlxSprite ? cast m : null;
		if (sprite != null && sprite.frame != null) {
			@:privateAccess
			var matrix = sprite._matrix;
			var p1 = FlxPoint.get(0, 0).transform(matrix);
			var p2 = FlxPoint.get(sprite.frame.frame.width, 0).transform(matrix);
			var p3 = FlxPoint.get(sprite.frame.frame.width, sprite.frame.frame.height).transform(matrix);
			var p4 = FlxPoint.get(0, sprite.frame.frame.height).transform(matrix);
			hit = pointInQuad(wp.x, wp.y, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y, p4.x, p4.y);
			p1.put(); p2.put(); p3.put(); p4.put();
		} else {
			hit = wp.x >= m.x && wp.x <= m.x + m.width && wp.y >= m.y && wp.y <= m.y + m.height;
		}
		wp.put();
		return hit;
	}

	function pickObjectAt(group:FlxGroup):FlxBasic {
		if (group.members == null) return null;
		var i = group.members.length - 1;
		while (i >= 0) {
			var m = group.members[i];
			if (m is FlxGroup) {
				var r = pickObjectAt(cast m);
				if (r != null) return r;
			} else if (m is FlxObject && m.visible && m.exists) {
				if (objectHitAt(cast m)) return m;
			}
			i--;
		}
		return null;
	}

	/** Runs live keyframe playback + click-to-place capture + scene click-select. Called each frame while the editor is open. */
	/** Called by every mutating edit; snapshots settle after a short debounce. */
	public function queueSnapshot() {
		snapPending = true;
		if (snapTimer <= 0) snapTimer = 0.8;
	}

	function collectScene(group:FlxGroup, out:Array<FlxBasic>) {
		if (group.members == null) return;
		for (m in group.members) {
			out.push(m);
			if (m is FlxGroup) collectScene(cast m, out);
		}
	}

	function captureSnapshot():InspectorSnapshot {
		var props:Map<FlxBasic, {x:Float, y:Float, angle:Float, scaleX:Float, scaleY:Float, alpha:Float, color:Int, visible:Bool}> = [];
		var all:Array<FlxBasic> = [];
		var st:FlxState = FlxG.state;
		while (st != null) {
			collectScene(cast st, all);
			st = st.subState;
		}
		for (m in all) {
			if (!(m is FlxObject)) continue;
			var o:FlxObject = cast m;
			var s = m is FlxSprite ? (cast m : FlxSprite) : null;
			props.set(m, {
				x: o.x, y: o.y, angle: o.angle, visible: m.visible,
				scaleX: s != null ? s.scale.x : 0, scaleY: s != null ? s.scale.y : 0,
				alpha: s != null ? s.alpha : 1, color: s != null ? s.color : 0
			});
		}
		var hooks:Map<FlxBasic, {c:String, u:String}> = [];
		for (o => h in objectHooks) hooks.set(o, {c: h.clickCode, u: h.updateCode});
		var tracks:Map<FlxBasic, {mode:Int, keys:Array<InspectorKeyframe>}> = [];
		for (o => tr in keyTracks)
			tracks.set(o, {mode: tr.mode, keys: [
				for (k in tr.keys) {t: k.t, x: k.x, y: k.y, angle: k.angle, scaleX: k.scaleX, scaleY: k.scaleY, alpha: k.alpha, ease: k.ease}
			]});
		return {props: props, names: editorNames.copy(), hooks: hooks, tracks: tracks};
	}

	function snapshotsDiffer(a:InspectorSnapshot, b:InspectorSnapshot):Bool {
		var na = 0, nb = 0;
		for (_ in a.props.keys()) na++;
		for (_ in b.props.keys()) nb++;
		if (na != nb) return true;
		for (o => p in a.props) {
			var q = b.props.get(o);
			if (q == null || p.x != q.x || p.y != q.y || p.angle != q.angle || p.scaleX != q.scaleX || p.scaleY != q.scaleY
				|| p.alpha != q.alpha || p.color != q.color || p.visible != q.visible) return true;
		}
		return false;
	}

	function applySnapshot(s:InspectorSnapshot) {
		for (o => p in s.props) {
			if (!isAliveInScene(o) || !(o is FlxObject)) continue;
			var ob:FlxObject = cast o;
			ob.x = p.x;
			ob.y = p.y;
			ob.angle = p.angle;
			o.visible = p.visible;
			if (o is FlxSprite) {
				var sp:FlxSprite = cast o;
				sp.scale.set(p.scaleX, p.scaleY);
				sp.alpha = p.alpha;
				sp.color = p.color;
			}
		}
		editorNames = s.names.copy();
		for (o => h in s.hooks) {
			var cur = getOrCreateHooks(o);
			cur.clickCode = h.c;
			cur.updateCode = h.u;
			cur.code = null; // force recompile
		}
		for (o => td in s.tracks) {
			var tr = getOrCreateTrack(o);
			tr.mode = td.mode;
			tr.keys = [
				for (k in td.keys) {t: k.t, x: k.x, y: k.y, angle: k.angle, scaleX: k.scaleX, scaleY: k.scaleY, alpha: k.alpha, ease: k.ease}
			];
		}
	}

	public function doUndo() {
		if (snapBaseline == null || undoStack.length == 0) return;
		redoStack.push(snapBaseline);
		snapBaseline = undoStack.pop();
		applySnapshot(snapBaseline);
		runStatus = 'Undo (${undoStack.length} left)';
	}

	public function doRedo() {
		if (snapBaseline == null || redoStack.length == 0) return;
		undoStack.push(snapBaseline);
		snapBaseline = redoStack.pop();
		applySnapshot(snapBaseline);
		runStatus = 'Redo (${redoStack.length} left)';
	}

	function tickUndo(elapsed:Float) {
		if (snapPending) {
			snapTimer -= elapsed;
			if (snapTimer <= 0) {
				var cur = captureSnapshot();
				if (snapBaseline == null) {
					snapBaseline = cur;
				} else if (snapshotsDiffer(snapBaseline, cur)) {
					undoStack.push(snapBaseline);
					if (undoStack.length > 64) undoStack.shift();
					redoStack.resize(0);
					snapBaseline = cur;
				}
				snapPending = false;
				snapTimer = 0;
			}
		}
		// wantTextInput (not wantCaptureKeyboard) so shortcuts work while a window is
		// merely focused, but stay dead while typing in a text field.
		if (!ImGuiIO.wantTextInput) {
			var ctrl = ImGui.isKeyDown(ImGuiKey.LeftCtrl) || ImGui.isKeyDown(ImGuiKey.RightCtrl);
			if (ctrl) {
				if (ImGui.isKeyPressed(ImGuiKey.Z)) doUndo();
				else if (ImGui.isKeyPressed(ImGuiKey.Y)) doRedo();
				else if (ImGui.isKeyPressed(ImGuiKey.D) && selectedObject != null) {
					var sel = selectionList();
					if (sel.length > 1) for (o in sel) duplicateObject(o);
					else duplicateObject(cast selectedObject);
					runStatus = "Duplicated";
				}
				else if (ImGui.isKeyPressed(ImGuiKey.S)) savePatch();
				else if (ImGui.isKeyPressed(ImGuiKey.C) && selectedObject is FlxBasic) copySelected();
				else if (ImGui.isKeyPressed(ImGuiKey.V) && clipboard != null) pasteClipboard();
				else if (ImGui.isKeyPressed(ImGuiKey.X) && selectedObject is FlxBasic) {
					copySelected();
					for (o in selectionList()) deleteInspectorObject(o);
				}
			}
			else if (ImGui.isKeyPressed(ImGuiKey.Delete) && selectedObject != null) {
				var sel = selectionList();
				if (sel.length > 1) for (o in sel) deleteInspectorObject(o);
				else deleteInspectorObject(cast selectedObject);
			}
			else if (ImGui.isKeyPressed(ImGuiKey.F)) focusSelected();
		}
		persistSettings();
	}

	function tickKeyTracks(elapsed:Float) {
		// continue an in-progress object drag (grabbed by clicking it in the scene)
		if (sceneDrag != null) {
			if (!isAliveInScene(sceneDrag.obj) || !ImGui.isMouseDown(0)) {
				if (sceneDrag.moved) {
					markEdited(sceneDrag.obj);
					for (oth in sceneDrag.others) markEdited(oth.o);
				}
				sceneDrag = null;
			} else {
				var mp = ImGui.getMousePos();
				var wp = gizmo.screenToWorldPoint(FlxPoint.get(mp.x, mp.y), sceneDrag.cam, scrollFactorFor(sceneDrag.obj));
				var nx = wp.x + sceneDrag.offX;
				var ny = wp.y + sceneDrag.offY;
				if (ImGui.isKeyDown(ImGuiKey.LeftCtrl)) {
					nx = Math.fround(nx / gizmo.snapPos) * gizmo.snapPos;
					ny = Math.fround(ny / gizmo.snapPos) * gizmo.snapPos;
				} else {
					var snapped = edgeSnapPos(nx, ny, sceneDrag.obj, sceneDrag.cam);
					nx = snapped.x;
					ny = snapped.y;
				}
				if (sceneDrag.obj.x != nx || sceneDrag.obj.y != ny) {
					sceneDrag.obj.x = nx;
					sceneDrag.obj.y = ny;
					sceneDrag.moved = true;
					for (oth in sceneDrag.others) {
						oth.o.x = nx + oth.dx;
						oth.o.y = ny + oth.dy;
					}
				}
				wp.put();
			}
		}

		// marquee: shift+drag draws a rubber band; releasing selects everything inside
		if (marquee != null) {
			if (!ImGui.isMouseDown(0)) {
				var mp = ImGui.getMousePos();
				var x0 = Math.min(marquee.x0, mp.x), y0 = Math.min(marquee.y0, mp.y);
				var x1 = Math.max(marquee.x0, mp.x), y1 = Math.max(marquee.y0, mp.y);
				selectedObjects.resize(0);
				forEachSceneFlxObject(function(o) {
					var r = objectScreenRect(o);
					if (r != null && r.x1 >= x0 && r.x0 <= x1 && r.y1 >= y0 && r.y0 <= y1)
						selectObject(o, true);
				});
				marquee = null;
				keyMouseConsumed = true;
			}
		}
		var shiftDown = ImGui.isKeyDown(ImGuiKey.LeftShift) || ImGui.isKeyDown(ImGuiKey.RightShift);
		if (marquee == null && clickSelect && shiftDown && ImGui.isMouseClicked(0) && !ImGuiIO.wantCaptureMouse) {
			var mp = ImGui.getMousePos();
			marquee = {x0: mp.x, y0: mp.y};
		}

		if (clickSelect && clickCaptureFor == null && !keyMouseConsumed && keyDrag == null && sceneDrag == null && marquee == null
			&& ImGui.isMouseClicked(0) && !ImGuiIO.wantCaptureMouse && !shiftDown
			&& !gizmo.positionActive && !gizmo.rotationActive && !gizmo.scaleActive) {
			if (assetClickPlace) {
				assetClickPlace = false;
				var mp = ImGui.getMousePos();
				var wp = gizmo.screenToWorldPoint(FlxPoint.get(mp.x, mp.y), FlxG.camera, null);
				spawnBrowserAsset(wp);
				wp.put();
			} else {
				var pick = pickSceneObject();
				if (pick != null) {
					selectObject(pick, ImGui.isKeyDown(ImGuiKey.LeftCtrl) || ImGui.isKeyDown(ImGuiKey.RightCtrl));
					if (pick is FlxText && ImGui.isMouseDoubleClicked(0)) {
						sceneDrag = null;
						textEditTarget = cast pick;
						if (textEditPtr == null) textEditPtr = new ImGuiStringPtr("");
						textEditPtr.value = textEditTarget.text;
						textEditDirty = false;
						textEditJustOpened = true;
						textEditOpen.value = true;
						var mp = ImGui.getMousePos();
						textEditX = mp.x;
						textEditY = mp.y;
					} else if (pick is FlxObject) {
						var o:FlxObject = cast pick;
						var data = findInspectorObjectFor(pick);
						var cam = data != null ? gizmo.prepareObjectCamera(data, pick) : FlxG.camera;
						var mp = ImGui.getMousePos();
						var wp = gizmo.screenToWorldPoint(FlxPoint.get(mp.x, mp.y), cam, scrollFactorFor(pick));
						// dragging a member of a multi-selection moves the whole selection
						var others:Array<{o:FlxObject, dx:Float, dy:Float}> = [];
						if (selectedObjects.contains(pick))
							for (m in selectionList())
								if (m != pick && m is FlxObject)
									others.push({o: cast m, dx: (cast m : FlxObject).x - o.x, dy: (cast m : FlxObject).y - o.y});
						sceneDrag = {obj: o, cam: cam, offX: o.x - wp.x, offY: o.y - wp.y, moved: false, others: others};
						wp.put();
					}
				}
			}
		}
		if (clickCaptureFor != null && ImGui.isMouseClicked(0) && !ImGuiIO.wantCaptureMouse) {
			var obj = clickCaptureFor;
			clickCaptureFor = null;
			var tr = getOrCreateTrack(obj);
			var wp = FlxG.mouse.getWorldPosition();
			addKeyframe(obj, trackDuration(tr) + 0.25, wp.x, wp.y);
			runStatus = 'Key added at ${Math.round(wp.x)}, ${Math.round(wp.y)}';
		}
		var dead:Array<FlxBasic> = null;
		for (obj => tr in keyTracks) {
			if (!isAliveInScene(obj)) {
				if (dead == null) dead = [];
				dead.push(obj);
				continue;
			}
			if (tr.patchTrack != null) {
				// adopted track - the patch script drives it; mirror its time for display
				tr.t = tr.patchTrack.t;
				tr.playing = tr.patchTrack.playing != false;
				continue;
			}
			if (tr.playing) {
				advanceTrack(tr, elapsed);
				applyTrack(obj, tr);
			}
		}
		if (dead != null)
			for (o in dead) keyTracks.remove(o);

		// motion bake: record live poses until the duration elapses or the object dies
		if (baking != null) {
			var b = baking;
			b.t += elapsed;
			if (b.t >= b.nextT) {
				b.keys.push(snapshotKey(b.obj, b.t));
				b.nextT += BAKE_STEP;
			}
			if (b.t >= b.dur || !isAliveInScene(b.obj)) {
				var tr = getOrCreateTrack(b.obj);
				tr.keys = b.keys;
				tr.mode = 0;
				tr.sel = -1;
				tr.playing = false;
				tr.t = 0;
				sortTrack(tr);
				syncPatchTrack(tr);
				markEdited(b.obj);
				runStatus = 'Baked ${b.keys.length} keys (${FlxMath.roundDecimal(b.dur, 1)}s)';
				baking = null;
			}
		}
	}

	inline function scrollFactorFor(obj:FlxBasic):FlxPoint
		return obj is FlxObject ? (cast obj : FlxObject).scrollFactor : null;

	/**
	 * Snaps the dragged object's position so its edges/centers line up with other
	 * scene objects within ~6 screen px. Only same-camera-space bounds are compared.
	 */
	function edgeSnapPos(nx:Float, ny:Float, obj:FlxObject, cam:FlxCamera):{x:Float, y:Float} {
		var thr = 6.0 / (cam != null && cam.zoom != 0 ? cam.zoom : 1);
		var excl = selectionList();
		if (!excl.contains(obj)) excl.push(obj);
		var candX:Array<Float> = [];
		var candY:Array<Float> = [];
		function gather(list:Array<InspectorObject>) {
			for (m in list) {
				if (m.obj is FlxObject && !excl.contains(m.obj) && m.obj.visible) {
					var o:FlxObject = cast m.obj;
					candX.push(o.x); candX.push(o.x + o.width / 2); candX.push(o.x + o.width);
					candY.push(o.y); candY.push(o.y + o.height / 2); candY.push(o.y + o.height);
				}
				if (m.members != null) gather(m.members);
			}
		}
		for (root in currentStateObjects) gather(root.members);
		var offsX = [0.0, obj.width / 2, obj.width];
		var offsY = [0.0, obj.height / 2, obj.height];
		var bestX = thr + 1, snapX = nx, bestY = thr + 1, snapY = ny;
		for (off in offsX) {
			var v = nx + off;
			for (c in candX) {
				var d = Math.abs(v - c);
				if (d < bestX) { bestX = d; snapX = c - off; }
			}
		}
		for (off in offsY) {
			var v = ny + off;
			for (c in candY) {
				var d = Math.abs(v - c);
				if (d < bestY) { bestY = d; snapY = c - off; }
			}
		}
		return {x: snapX, y: snapY};
	}

	/** Evaluates the track's position at its current time without applying it. */
	public function evalTrackPos(tr:InspectorTrack):FlxPoint {
		if (tr.keys.length == 0) return null;
		var p = evalTrackPose(tr, tr.t);
		return FlxPoint.get(p.x, p.y);
	}

	/**
	 * Draws keyframe markers + motion paths over the game view, and handles
	 * clicking/dragging markers. Called every frame while the editor is open.
	 */
	function drawKeyframeOverlays() {
		keyMouseConsumed = false;
		var drawList = ImGui.getBackgroundDrawList(ImGui.getMainViewport());

		// continue an in-progress key drag
		if (keyDrag != null) {
			var tr = keyTracks.get(keyDrag.obj);
			if (tr == null || keyDrag.index >= tr.keys.length || !isAliveInScene(keyDrag.obj) || !ImGui.isMouseDown(0)) {
				if (tr != null && keyDrag.index < tr.keys.length) {
					syncPatchTrack(tr);
					markEdited(keyDrag.obj);
				}
				keyDrag = null;
			} else {
				var k = tr.keys[keyDrag.index];
				var wp = FlxG.mouse.getWorldPosition(keyDrag.cam);
				var sf = scrollFactorFor(keyDrag.obj);
				if (sf != null) {
					k.x = wp.x + keyDrag.cam.viewMarginLeft * (sf.x - 1);
					k.y = wp.y + keyDrag.cam.viewMarginTop * (sf.y - 1);
				} else {
					k.x = wp.x;
					k.y = wp.y;
				}
				keyMouseConsumed = true;
			}
		}

		if (!showKeyOverlay) return;

		var mouse = ImGui.getMousePos();
		var hoverObj:FlxBasic = null;
		var hoverIdx:Int = -1;
		var hoverDist:Float = 121; // max pick radius (11px), squared

		for (obj => tr in keyTracks) {
			if (tr.keys.length == 0 || !isAliveInScene(obj)) continue;
			var data = findInspectorObjectFor(obj);
			var cam = data != null ? gizmo.prepareObjectCamera(data, obj) : FlxG.camera;
			var sel = obj == selectedObject;
			var lineCol:Int = sel ? 0xCCE6C55A : 0x4DE6C55A;
			var markCol:Int = sel ? 0xFFE6C55A : 0x99E6C55A;
			var sf = scrollFactorFor(obj);

			// motion path through the keys (ease applied per segment)
			if (tr.keys.length > 1) {
				var prev = gizmo.toScreenPoint(FlxPoint.get(tr.keys[0].x, tr.keys[0].y), cam, sf);
				for (i in 1...tr.keys.length) {
					var a = tr.keys[i - 1];
					var b = tr.keys[i];
					var ef:Dynamic = a.ease != null ? Reflect.field(flixel.tweens.FlxEase, a.ease) : null;
					for (s in 1...13) {
						var u = s / 12;
						if (ef != null) u = ef(u);
						var p = gizmo.toScreenPoint(FlxPoint.get(a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u), cam, sf);
						drawList.addLine([prev.x, prev.y, p.x, p.y], lineCol, sel ? 2.0 : 1.0);
						prev.put();
						prev = p;
					}
				}
				prev.put();
			}

			// keyframe markers
			for (i => k in tr.keys) {
				var p = gizmo.toScreenPoint(FlxPoint.get(k.x, k.y), cam, sf);
				var isSelKey = sel && tr.sel == i;
				var r = isSelKey ? 7 : 5;
				var dx = mouse.x - p.x;
				var dy = mouse.y - p.y;
				var d2 = dx * dx + dy * dy;
				if (!ImGuiIO.wantCaptureMouse && d2 < hoverDist) {
					hoverDist = d2;
					hoverObj = obj;
					hoverIdx = i;
				}
				drawList.addCircleFilled(p.x, p.y, r, isSelKey ? 0xFF5EC9FF : markCol, 10);
				drawList.addCircle(p.x, p.y, r + 1, 0xB3000000, 10, 1);
				drawList.addText(p.x + 8, p.y - 6, markCol, 'K$i@${FlxMath.roundDecimal(k.t, 2)}s');
				p.put();
			}

			// playhead ghost
			if (sel) {
				var pos = evalTrackPos(tr);
				if (pos != null) {
					var p = gizmo.toScreenPoint(pos, cam, sf);
					drawList.addCircle(p.x, p.y, 9, 0xFFFFFFFF, 12, 1.5);
					drawList.addText(p.x + 11, p.y - 6, 0xFFFFFFFF, 't=${FlxMath.roundDecimal(tr.t, 2)}s');
					p.put();
				}
			}
		}

		// armed click-capture ghost at the mouse position
		if (clickCaptureFor != null) {
			drawList.addCircle(mouse.x, mouse.y, 8, 0xFF7CFC00, 12, 2);
			drawList.addLine([mouse.x - 12, mouse.y, mouse.x + 12, mouse.y], 0xFF7CFC00, 1);
			drawList.addLine([mouse.x, mouse.y - 12, mouse.x, mouse.y + 12], 0xFF7CFC00, 1);
		}

		// grab a marker (runs before scene click-select in tickKeyTracks)
		if (hoverObj != null) {
			keyMouseConsumed = true;
			if (ImGui.isMouseClicked(0)) {
				var tr = keyTracks.get(hoverObj);
				tr.sel = hoverIdx;
				selectObject(hoverObj);
				var data = findInspectorObjectFor(hoverObj);
				keyDrag = {
					obj: hoverObj,
					index: hoverIdx,
					cam: data != null ? gizmo.prepareObjectCamera(data, hoverObj) : FlxG.camera
				};
			}
			if (ImGui.isMouseClicked(1)) {
				keyCtx = {obj: hoverObj, index: hoverIdx};
				var tr = keyTracks.get(hoverObj);
				keyCtxTimePtr.value = tr.keys[hoverIdx].t;
				keyCtxEasePtr.value = 0;
				ImGui.openPopup("##keyCtx");
			}
		}

		drawKeyContextMenu();
	}

	/** Popup for right-clicked keyframe markers: ease, time, snap pose, duplicate, delete. */
	function drawKeyContextMenu() {
		if (!ImGui.beginPopup("##keyCtx")) return;
		var tr = keyCtx == null ? null : keyTracks.get(keyCtx.obj);
		if (tr == null || keyCtx.index >= tr.keys.length) {
			ImGui.closeCurrentPopup();
			keyCtx = null;
			ImGui.endPopup();
			return;
		}
		var k = tr.keys[keyCtx.index];
		ImGui.text('Key ${keyCtx.index} @ ${FlxMath.roundDecimal(k.t, 2)}s');
		ImGui.separator();
		if (ImGui.dragFloat("time##keyCtx", keyCtxTimePtr, 0.01, 0, 0, "%.2f")) {
			k.t = keyCtxTimePtr.value;
			sortTrack(tr);
			keyCtx.index = tr.keys.indexOf(k);
			syncPatchTrack(tr);
			markEdited(keyCtx.obj);
		}
		ImGui.setNextItemWidth(170);
		var names = getEaseNames();
		if (keyCtxEasePtr.value <= 0) keyCtxEasePtr.value = names.indexOf(k.ease);
		if (keyCtxEasePtr.value < 0) keyCtxEasePtr.value = 0;
		if (ImGui.combo("ease to next##keyCtx", keyCtxEasePtr, names)) {
			k.ease = names[keyCtxEasePtr.value];
			syncPatchTrack(tr);
			markEdited(keyCtx.obj);
		}
		if (ImGui.menuItem("Snap pose to object")) {
			var nk = snapshotKey(keyCtx.obj, k.t);
			k.x = nk.x; k.y = nk.y; k.angle = nk.angle;
			k.scaleX = nk.scaleX; k.scaleY = nk.scaleY; k.alpha = nk.alpha;
			syncPatchTrack(tr);
			markEdited(keyCtx.obj);
		}
		if (ImGui.menuItem("Duplicate")) {
			var nk:InspectorKeyframe = {t: k.t + 0.25, x: k.x, y: k.y, angle: k.angle, scaleX: k.scaleX, scaleY: k.scaleY, alpha: k.alpha, ease: k.ease};
			tr.keys.push(nk);
			sortTrack(tr);
			tr.sel = keyCtx.index = tr.keys.indexOf(nk);
			keyCtxTimePtr.value = nk.t;
			syncPatchTrack(tr);
			markEdited(keyCtx.obj);
		}
		if (ImGui.menuItem("Delete")) {
			tr.keys.remove(k);
			tr.sel = -1;
			syncPatchTrack(tr);
			markEdited(keyCtx.obj);
			keyCtx = null;
			ImGui.closeCurrentPopup();
		}
		ImGui.endPopup();
	}

	public function deleteInspectorObject(obj:FlxBasic) {
		objectsDirty = true;
		var data = findInspectorObjectFor(obj);
		var isAdded = addedObjects.filter(a -> a.obj == obj).length > 0;

		if (!isAdded && data != null && !data.name.startsWith("Unknown") && data.name.indexOf(" ") == -1)
			removedExpressions.push(data.name);

		var parent = findParentGroup(obj, cast FlxG.state);
		if (parent != null) parent.remove(obj, true);

		objectHooks.remove(obj);
		editorNames.remove(obj);
		editedObjects.remove(obj);
		for (a in addedObjects) if (a.obj == obj) { addedObjects.remove(a); break; }

		if (selectedObject == obj) {
			selectedObject = null;
			selectedObjectData = null;
		}
		queueSnapshot();
	}

	function findParentGroup(obj:FlxBasic, group:FlxGroup):FlxGroup {
		if (group.members != null && group.members.indexOf(obj) != -1) return group;
		if (group.members != null)
			for (m in group.members)
				if (m is FlxGroup) {
					var r = findParentGroup(obj, cast m);
					if (r != null) return r;
				}
		return null;
	}

	function findInspectorObjectFor(obj:FlxBasic, ?list:Array<InspectorObject>):InspectorObject {
		if (list == null) list = currentStateObjects;
		for (m in list) {
			if (m.obj == obj) return m;
			var r = findInspectorObjectFor(obj, m.members);
			if (r != null) return r;
		}
		return null;
	}

	function isInScene(obj:FlxBasic, group:FlxGroup):Bool {
		if (group.members == null) return false;
		if (group.members.indexOf(obj) != -1) return true;
		for (m in group.members)
			if (m is FlxGroup && isInScene(obj, cast m)) return true;
		return false;
	}

	function exprFor(obj:FlxBasic):String {
		var data = findInspectorObjectFor(obj);
		if (data == null || data.name.startsWith("Unknown") || data.name.indexOf(" ") != -1) return null;
		return data.name;
	}

	function runObjectHooks() {
		var dead:Array<FlxBasic> = null;
		for (obj => h in objectHooks) {
			if (h.fromPatch) continue; // the loaded patch script runs these itself
			// object may belong to a destroyed state; skip + collect for cleanup
			if (!isAliveInScene(obj)) {
				(dead ??= []).push(obj);
				continue;
			}
			var s = getHookScript(obj, h);
			if (s == null) continue;
			try {
				if (h.updateCode != "") s.call("__update", [FlxG.elapsed]);
				if (h.clickCode != "" && FlxG.mouse.justPressed && (obj is FlxObject) && FlxG.mouse.overlaps(cast obj))
					s.call("__click");
			} catch(e) {
				Logs.warn('Inspector hook error on ${editorNames.get(obj) ?? "object"}: $e');
			}
		}
		if (dead != null) for (obj in dead) objectHooks.remove(obj);
	}

	function isAliveInScene(obj:FlxBasic):Bool {
		var state:FlxState = FlxG.state;
		while (state != null) {
			if (isInScene(obj, cast state)) return true;
			state = state.subState;
		}
		return false;
	}

	function getHookScript(obj:FlxBasic, h:{updateCode:String, clickCode:String, code:String, script:Script}):Script {
		if (h.updateCode == "" && h.clickCode == "") return null;
		var code = 'function __click() {\n${h.clickCode}\n}\nfunction __update(elapsed) {\n${h.updateCode}\n}';
		if (h.code != code) {
			h.code = code;
			try {
				var id = editorNames.get(obj) ?? 'obj${Std.string(obj.ID)}';
				var s = Script.fromString(code, 'inspector-hook-$id.hx');
				s.setParent(FlxG.state);
				s.set("obj", obj);
				s.load();
				h.script = s;
			} catch(e) {
				h.script = null;
				Logs.warn('Inspector hook compile failed: $e');
			}
		}
		return h.script;
	}

	public static function escapeHaxe(s:String):String {
		if (s == null) return "";
		return s.split("\\").join("\\\\").split("\"").join("\\\"").split("\n").join("\\n").split("\r").join("\\r");
	}

	function resolvePatchLibraryPath():String {
		var mod = ModsFolder.currentModFolder;
		for (l in ModsFolder.getLoadedModsLibs()) {
			var mfl:ModsFolderLibrary = (l is ModsFolderLibrary) ? cast l : null;
			if (mfl == null) continue;
			if (mod != null ? mfl.modName == mod : mfl.modName == "assets") return mfl.basePath;
		}
		return null;
	}

	function emitObjectProps(buf:StringBuf, expr:String, o:FlxBasic) {
		buf.add('$expr.visible = ${o.visible};\n');
		var camIdx = FlxG.cameras.list.indexOf(o.camera);
		if (camIdx > 0) buf.add('$expr.cameras = [FlxG.cameras.list[$camIdx]];\n');
		if (o is FlxObject) {
			var ob:FlxObject = cast o;
			buf.add('$expr.x = ${ob.x};\n');
			buf.add('$expr.y = ${ob.y};\n');
			if (ob.angle != 0) buf.add('$expr.angle = ${ob.angle};\n');
			buf.add('$expr.scrollFactor.set(${ob.scrollFactor.x}, ${ob.scrollFactor.y});\n');
		}
		if (o is FlxSprite) {
			var s:FlxSprite = cast o;
			buf.add('$expr.scale.set(${s.scale.x}, ${s.scale.y});\n');
			buf.add('$expr.updateHitbox();\n');
			buf.add('$expr.alpha = ${s.alpha};\n');
			buf.add('$expr.color = 0x${StringTools.hex(s.color, 8)};\n');
			if (s.flipX) buf.add('$expr.flipX = true;\n');
			if (s.flipY) buf.add('$expr.flipY = true;\n');
			if (s.offset.x != 0 || s.offset.y != 0) buf.add('$expr.offset.set(${s.offset.x}, ${s.offset.y});\n');
			buf.add('$expr.antialiasing = ${s.antialiasing};\n');
		}
		if (o is FlxText) {
			var t:FlxText = cast o;
			buf.add('$expr.text = "${escapeHaxe(t.text)}";\n');
			buf.add('$expr.size = ${t.size};\n');
			buf.add('$expr.fieldWidth = ${t.fieldWidth};\n');
			if (Std.string(t.borderStyle) != "NONE")
				buf.add('$expr.borderStyle = Type.createEnumIndex(Type.resolveEnum("flixel.text.FlxTextBorderStyle"), ${Type.enumIndex(t.borderStyle)});\n');
			buf.add('$expr.borderColor = 0x${StringTools.hex(t.borderColor, 8)};\n');
			buf.add('$expr.borderSize = ${t.borderSize};\n');
		}
		if (o is FlxSprite) {
			var s:FlxSprite = cast o;
			if (s.animation != null && s.animation.curAnim != null)
				buf.add('$expr.animation.play("${escapeHaxe(s.animation.curAnim.name)}");\n');
		}
		var ops = animOps.get(o);
		if (ops != null)
			for (op in ops)
				buf.add('$expr.$op;\n');
	}

	function savePatch() {
		#if sys
		updateObjects(); // refresh in case displayUI hasn't run yet
		var root = currentStateObjects[0];
		var stateObj:FlxState = FlxG.state;
		if (root != null && root.obj is FlxState) stateObj = cast root.obj;
		var stateName = (stateObj is MusicBeatState) ? ((cast stateObj : MusicBeatState).scriptName ?? Type.getClassName(Type.getClass(stateObj)).split('.').pop()) : Type.getClassName(Type.getClass(stateObj)).split('.').pop();
		var base = resolvePatchLibraryPath();
		if (base == null) { saveStatus = "No writable library"; Logs.error("State Editor: no writable asset library found"); return; }

		var dir = '$base/data/states';
		sys.FileSystem.createDirectory(dir);
		var path = '$dir/$stateName.hx';

		var post = new StringBuf();
		var upd = new StringBuf();
		var notes = new StringBuf();
		var decls = new StringBuf();
		var state:FlxState = stateObj;

		for (e in removedExpressions) post.add('remove($e); // deleted via State Editor\n');

		for (o in editedObjects.keys()) {
			if (addedObjects.filter(a -> a.obj == o).length > 0) continue; // emitted via creation
			if (!isInScene(o, cast state)) continue;
			var expr = exprFor(o);
			if (expr == null) {
				notes.add('// WARNING: could not resolve a path for an edited ${Type.getClassName(Type.getClass(o))}; changes not saved\n');
				continue;
			}
			post.add('// edits to $expr\n');
			emitObjectProps(post, expr, o);
			emitObjectHooks(upd, expr, o);
		}

		for (a in addedObjects) {
			if (!isInScene(a.obj, cast state)) continue;
			var v = a.varName;
			decls.add('var $v:Dynamic = null;\n');
			post.add('$v = ${a.createCode};\n');
			if (a.cloneSource != null) {
				var sexpr = exprFor(a.cloneSource);
				if (sexpr != null) {
					post.add('$v.loadGraphicFromSprite($sexpr);\n');
					for (an in a.cloneSource.animation.getAnimationList())
						post.add('$v.animation.add("${escapeHaxe(an.name)}", ${an.frames.toString()}, ${an.frameRate}, ${an.looped}, ${an.flipX}, ${an.flipY});\n');
				}
			}
			emitObjectProps(post, v, a.obj);
			var pexpr = (a.parent == null || a.parent == cast state) ? null : exprFor(a.parent);
			post.add(pexpr == null ? 'add($v);\n' : '$pexpr.add($v);\n');
			emitObjectHooks(upd, v, a.obj);
		}

		// draw-order changes replayed last
		for (m in moveOps) {
			if (!isInScene(m.obj, cast state)) continue;
			var e = exprFor(m.obj);
			if (e == null) continue;
			var pe = (m.parent == null || m.parent == cast state) ? "" : (exprFor(m.parent) ?? "") + ".";
			post.add('${pe}insert(${m.index}, ${pe}remove($e));\n');
		}

		// reparents replayed after order ops
		for (r in reparentOps) {
			if (!isInScene(r.obj, cast state)) continue;
			var e = exprFor(r.obj);
			if (e == null) continue;
			var fe = (r.from == cast state) ? "FlxG.state" : exprFor(r.from);
			var te = (r.to == cast state) ? "FlxG.state" : exprFor(r.to);
			if (fe != null && te != null)
				post.add('// reparent\n$te.add($fe.remove($e));\n');
		}

		// freeform snippets appended by the user
		for (sn in patchSnippets)
			(sn.phase == 0 ? post : upd).add('// code runner snippet\n${sn.code}\n');

		// hooks attached to pre-existing objects that weren't otherwise edited
		for (o => h in objectHooks) {
			if (addedObjects.filter(a -> a.obj == o).length > 0 || editedObjects.exists(o)) continue;
			if (!isInScene(o, cast state)) continue;
			var expr = exprFor(o);
			if (expr == null) {
				notes.add('// WARNING: could not resolve a path for a hooked ${Type.getClassName(Type.getClass(o))}; hooks not saved\n');
				continue;
			}
			emitObjectHooks(upd, expr, o);
		}

		// keyframe animation tracks
		var trackCode = new StringBuf();
		for (o => tr in keyTracks) {
			if (tr.keys.length == 0 || !isInScene(o, cast state)) continue;
			var expr = exprFor(o);
			if (expr == null) {
				notes.add('// WARNING: could not resolve a path for an animated ${Type.getClassName(Type.getClass(o))}; keyframes not saved\n');
				continue;
			}
			var parts:Array<String> = [];
			for (k in tr.keys)
				parts.push('{t:${k.t},x:${k.x},y:${k.y},angle:${k.angle},sx:${k.scaleX},sy:${k.scaleY},alpha:${k.alpha},ease:flixel.tweens.FlxEase.${k.ease}}');
			trackCode.add('// keyframe track for $expr\n__snePlayKeys($expr, [${parts.join(", ")}], ${tr.mode});\n');
		}
		var trackStr = trackCode.toString();
		var hasTracks = trackStr.length > 0;

		// session manifest - lets the editor re-adopt patch objects/hooks/tracks next launch
		var meta:Dynamic = {
			objs: [for (a in addedObjects) if (isInScene(a.obj, cast state)) {v: a.varName, c: a.createCode, t: a.typeName}],
			rem: removedExpressions.copy(),
			snip: [for (s in patchSnippets) {c: s.code, p: s.phase}],
			edit: [],
			hooks: {},
			trk: {},
			anim: {},
			mov: []
		};
		for (o in editedObjects.keys()) {
			var e = exprFor(o);
			if (e != null && isInScene(o, cast state)) (meta.edit : Array<String>).push(e);
		}
		for (o => h in objectHooks) {
			var e = exprFor(o);
			if (e != null && isInScene(o, cast state))
				Reflect.setField(meta.hooks, e, {c: h.clickCode, u: h.updateCode});
		}
		for (o => tr in keyTracks) {
			if (tr.keys.length == 0) continue;
			var e = exprFor(o);
			if (e != null && isInScene(o, cast state))
				Reflect.setField(meta.trk, e, {m: tr.mode, k: [
					for (k in tr.keys) {t: k.t, x: k.x, y: k.y, a: k.angle, sx: k.scaleX, sy: k.scaleY, al: k.alpha, e: k.ease}
				]});
		}
		for (o => ops in animOps) {
			var e = exprFor(o);
			if (e != null && isInScene(o, cast state)) Reflect.setField(meta.anim, e, ops);
		}
		for (m in moveOps) {
			var e = exprFor(m.obj);
			if (e != null && isInScene(m.obj, cast state))
				(meta.mov : Array<Dynamic>).push({e: e, p: exprFor(m.parent), i: m.index});
		}
		notes.add('// SNE-META ' + haxe.Json.stringify(meta) + '\n');

		writePatchFile(path, post.toString() + trackStr, upd.toString() + (hasTracks ? '__sneAnimateKeys(elapsed);\n' : ''),
			notes.toString() + decls.toString() + (hasTracks ? TRACK_PLAYER_SRC : ''));
		saveStatus = 'Saved $stateName.hx';
		Logs.trace('State Editor: wrote patch to $path', SUCCESS, GREEN);
		#else
		saveStatus = "sys only";
		#end
	}

	function emitObjectHooks(upd:StringBuf, expr:String, o:FlxBasic) {
		var h = objectHooks.get(o);
		if (h == null) return;
		if (h.clickCode != "")
			upd.add('if (FlxG.mouse.justPressed && FlxG.mouse.overlaps($expr)) {\nvar obj = $expr;\n${h.clickCode}\n}\n');
		if (h.updateCode != "")
			upd.add('// update hook for $expr\n{\nvar obj = $expr;\n${h.updateCode}\n}\n');
	}

	function writePatchFile(path:String, post:String, upd:String, notes:String) {
		var block = '// >>> STATE EDITOR PATCH - regenerated on export, do not edit below <<<\n'
			+ notes
			+ 'function __sneEditorPatch() {\n' + post + '\n}\n\n'
			+ 'function __sneEditorUpdate(elapsed) {\n' + upd + '\n}\n'
			+ '// >>> END STATE EDITOR PATCH <<<';

		var startMarker = '// >>> STATE EDITOR PATCH';
		var endMarker = '// >>> END STATE EDITOR PATCH <<<';
		var existing = sys.FileSystem.exists(path) ? sys.io.File.getContent(path) : null;
		var content:String;
		if (existing == null) {
			content = block
				+ '\nfunction postCreate() {\n\t__sneEditorPatch();\n}\n'
				+ 'function update(elapsed) {\n\t__sneEditorUpdate(elapsed);\n}\n';
		} else {
			var s = existing.indexOf(startMarker);
			var e = existing.indexOf(endMarker);
			if (s != -1 && e != -1) {
				content = existing.substring(0, s) + block + existing.substring(e + endMarker.length);
			} else {
				content = existing + '\n' + block;
				content = insertScriptCall(content, 'postCreate', '__sneEditorPatch();', '');
				content = insertScriptCall(content, 'update', '__sneEditorUpdate(elapsed);', 'elapsed');
			}
		}
		// don't write a patch that can't be re-parsed on next state load
		try Script.fromString(content, path)
		catch (e:Dynamic) {
			saveStatus = 'Generated patch did not parse, not written: $e';
			Logs.error('State Editor: generated patch failed to parse: $e');
			return;
		}
		sys.io.File.saveContent(path, content);
	}

	// Keyframe player emitted into patches when any object has a track.
	static var TRACK_PLAYER_SRC = 'var __sneKeyTracks = [];\n'
		+ 'function __snePlayKeys(o, keys, mode) {\n'
		+ '	var t = (mode == 3) ? (keys.length == 0 ? 0.0 : keys[keys.length-1].t) : 0.0;\n'
		+ '	__sneKeyTracks.push({o: o, keys: keys, mode: mode, t: t, dir: (mode == 3) ? -1 : 1, playing: true});\n'
		+ '}\n'
		+ 'function __sneAnimateKeys(elapsed) {\n'
		+ '	for (tr in __sneKeyTracks) {\n'
		+ '		var keys = tr.keys; var o = tr.o;\n'
		+ '		if (o == null || o.exists == false || keys.length == 0 || tr.playing == false) continue;\n'
		+ '		var dur = keys[keys.length-1].t;\n'
		+ '		if (dur <= 0) continue;\n'
		+ '		tr.t += elapsed * tr.dir * (tr.mode == 4 ? (funkin.backend.system.Conductor.bpm / 60) : 1);\n'
		+ '		if (tr.mode == 1 || tr.mode == 4) { tr.t = tr.t % dur; if (tr.t < 0) tr.t += dur; }\n'
		+ '		else if (tr.mode == 2) {\n'
		+ '			if (tr.t > dur) { tr.t = dur - (tr.t - dur); tr.dir = -1; }\n'
		+ '			if (tr.t < 0) { tr.t = -tr.t; tr.dir = 1; }\n'
		+ '		} else {\n'
		+ '			if (tr.t > dur) tr.t = dur;\n'
		+ '			if (tr.t < 0) tr.t = 0;\n'
		+ '		}\n'
		+ '		var a = keys[0]; var b = keys[0]; var u = 1.0;\n'
		+ '		if (tr.t > keys[0].t) {\n'
		+ '			if (tr.t >= keys[keys.length-1].t) { a = keys[keys.length-1]; b = a; }\n'
		+ '			else {\n'
		+ '				for (i in 0...keys.length-1) {\n'
		+ '					if (tr.t >= keys[i].t && tr.t <= keys[i+1].t) {\n'
		+ '						a = keys[i]; b = keys[i+1];\n'
		+ '						var span = b.t - a.t;\n'
		+ '						u = span <= 0 ? 1.0 : (tr.t - a.t) / span;\n'
		+ '						if (a.ease != null) u = a.ease(u);\n'
		+ '						break;\n'
		+ '					}\n'
		+ '				}\n'
		+ '			}\n'
		+ '		}\n'
		+ '		o.x = a.x + (b.x - a.x) * u;\n'
		+ '		o.y = a.y + (b.y - a.y) * u;\n'
		+ '		o.angle = a.angle + (b.angle - a.angle) * u;\n'
		+ '		if (Reflect.hasField(o, "scale")) o.scale.set(a.sx + (b.sx - a.sx) * u, a.sy + (b.sy - a.sy) * u);\n'
		+ '		if (Reflect.hasField(o, "alpha")) o.alpha = a.alpha + (b.alpha - a.alpha) * u;\n'
		+ '	}\n'
		+ '}\n';

	function insertScriptCall(src:String, fn:String, call:String, args:String):String {
		if (src.contains(call)) return src;
		var i = src.indexOf('function ' + fn);
		if (i == -1)
			return src + '\nfunction $fn($args) {\n\t$call\n}\n';
		var j = src.indexOf('{', i);
		if (j == -1) return src;
		return src.substring(0, j + 1) + '\n\t' + call + src.substring(j + 1);
	}

	// ============ END STATE EDITOR ============

	public function figureOutObjectName(packageName:String, parent:Dynamic, object:FlxBasic) {
		if (object == null) return "Null Member";
		if (editorNames.exists(object)) return editorNames.get(object);
		if (!cachedInstanceFields.exists(packageName)) {
			cachedInstanceFields.set(packageName, Type.getInstanceFields(Type.getClass(parent)));
		}
		var instanceFields:Array<String> = cachedInstanceFields.get(packageName);
		var uselessFields:Array<String> = [];
		for (field in instanceFields) {
			if (field == "members") {
				uselessFields.push(field);
				continue;
			}

			var fieldObj:Dynamic = Reflect.getProperty(parent, field);
			if (fieldObj != null) {
				if (fieldObj is FlxBasic) {
					if (object == fieldObj) {
						return field;
					} else if (fieldObj is Stage) {
						var stage:Stage = cast fieldObj;
						for (name => stageObj in stage.stageSprites) {
							if (object == stageObj) return name;
						}
						for (name => posObj in stage.characterPoses) {
							if (object == posObj) return name;
						}
					}
				} else if (fieldObj is Array) {
					var arr:Array<Dynamic> = cast fieldObj;
					var firstMember = arr[0];
					if (firstMember != null && firstMember is FlxBasic) {
						for (index => arrayObj in arr) {
							if (object == arrayObj) {
								return field + "[" + index + "]";
							}
						}
					}
				} else {
					uselessFields.push(field);
				}
			}
		}
		if (uselessFields.length > 0) { //these aren't flxbasic
			for (field in uselessFields) {
				instanceFields.remove(field);
			}
			cachedInstanceFields.set(packageName, instanceFields);
		}

		var scriptPacksToCheck:Array<ScriptPack> = [];
		if (parent is MusicBeatState) {
			var state:MusicBeatState = cast parent;
			scriptPacksToCheck.push(state.stateScripts);
		}
		if (parent is PlayState) {
			var playstate:PlayState = cast parent;
			for (strumLineIndex => strumLine in playstate.strumLines.members) {
				for (charIndex => char in strumLine.characters) {
					if (object == char) {
						return "strumLines[" + strumLineIndex + "].characters[" + charIndex + "] (" + char.curCharacter + ")";
					}
				}
			}
			scriptPacksToCheck.push(playstate.scripts);
		}
		
		for (pack in scriptPacksToCheck) {
			
			for (script in pack.scripts) {
				if (script is HScript) {
					var hscript:HScript = cast script;
					for (name => scriptObj in hscript.interp.variables) {
						if (scriptObj is FlxBasic) {
							if (scriptObj == object) return name;
						} else if (scriptObj is Array) {
							var arr:Array<Dynamic> = cast scriptObj;
							var firstMember = arr[0];
							if (firstMember != null && firstMember is FlxBasic) {
								for (index => arrayObj in arr) {
									if (object == arrayObj) {
										return name + "[" + index + "]";
									}
								}
							}
						}
					}
				}
			}
		}

		return "Unknown" + object.ID;
	}
	#end
}

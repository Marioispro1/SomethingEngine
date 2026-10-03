package funkin.backend.system.console.inspector;

//WIP

import openfl.Lib;
import flixel.FlxState;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup;
import flixel.text.FlxText;
import funkin.backend.FunkinText;
import funkin.backend.assets.IModsAssetLibrary;
import funkin.backend.assets.ModsFolder;
import funkin.backend.assets.ModsFolderLibrary;
import funkin.backend.scripting.HScript;
import funkin.backend.scripting.ModState;
import funkin.backend.scripting.Script;
import funkin.backend.scripting.ScriptPack;
import funkin.game.Stage;

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

/** mode: 0 = once, 1 = loop, 2 = pingpong, 3 = reverse-once */
typedef InspectorTrack = {keys:Array<InspectorKeyframe>, mode:Int, playing:Bool, t:Float, dir:Int, sel:Int};

class ConsoleInspector {

	var hscript:ConsoleHscript;
	var cachedInstanceFields:Map<String, Array<String>> = [];
	public function new(hscript:ConsoleHscript) {
		this.hscript = hscript;
		#if IMGUI_ENABLED
		objectProperties.inspector = this;
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

	/** Custom hscript behavior attached to objects (onClick / update). */
	var objectHooks:Map<FlxBasic, {updateCode:String, clickCode:String, code:String, script:Script}> = [];

	/** Animation operations performed on sprites (method-call bodies, emitted per object). */
	var animOps:Map<FlxBasic, Array<String>> = [];

	/** Draw-order changes: object, its group and the member index it was moved to. */
	var moveOps:Array<{obj:FlxBasic, parent:FlxGroup, index:Int}> = [];

	/** Freeform code snippets appended to the patch (phase 0 = create, 1 = update). */
	var patchSnippets:Array<{code:String, phase:Int}> = [];

	/** Keyframe animation tracks per object. */
	public var keyTracks:Map<FlxBasic, InspectorTrack> = [];

	/** Object awaiting a click-in-scene keyframe placement. */
	public var clickCaptureFor:FlxBasic = null;

	var easeNames:Array<String> = null;

	var addKind = new ImGuiIntPtr(0);
	var addImagePath = new ImGuiStringPtr("");
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
				if (ImGui.menuItem("Reload State Scripts")) reloadStateScripts();
				if (ImGui.menuItem("Save Patch", "writes data/states/<State>.hx")) savePatch();
				ImGui.endMenu();
			}
			if (ImGui.beginMenu("Add")) {
				var kinds = ["Sprite", "Text", "Button", "Group", "Custom (code)"];
				for (i => k in kinds)
					if (ImGui.menuItem(k)) { addKind.value = i; jumpToTab = 1; }
				ImGui.endMenu();
			}
			if (ImGui.beginMenu("Help")) {
				ImGui.menuItem("Q/W/E/R - none/move/rotate/scale gizmo", null, false, false);
				ImGui.menuItem("Ctrl while dragging - snap", null, false, false);
				ImGui.menuItem("F3 - console, F4 - this window", null, false, false);
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

	public function displayUI() {
		
		updateObjects();

		FlxG.mouse.visible = true; //TODO: rework this, temp force on
		
		ImGui.setNextWindowPos(ImGuiUtil.getWindowSpaceX(), ImGuiUtil.getWindowSpaceY(), ImGuiCond.FirstUseEver);
		ImGui.setNextWindowSize(320, Lib.application.window.height, ImGuiCond.FirstUseEver);
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
					ImGui.unindent();
					ImGui.separatorText("Scene Tree");
					for (index => member in currentStateObjects) {
						var nodeID = member.name + index;
						var flags = ImGuiTreeNodeFlags.DefaultOpen;
						if (member.obj == selectedObject) flags |= ImGuiTreeNodeFlags.Selected;
						if (ImGui.treeNodeEx(nodeID, flags, member.name + " (" + member.type + ")")) {
							if (ImGui.isItemClicked()) {
								selectObject(member.obj);
							}
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

		tickKeyTracks(FlxG.elapsed);
		runObjectHooks();
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

	function generateTreeForMembers(id:String, object:InspectorObject) {
		for (index => member in object.members) {
			var valid = member.obj != null;
			var nodeID = id + object.name + index;
			var flags = ImGuiTreeNodeFlags.None;
			if (member.members.length == 0) flags |= ImGuiTreeNodeFlags.Leaf;
			if (valid && member.obj == selectedObject) flags |= ImGuiTreeNodeFlags.Selected;
			if (ImGui.treeNodeEx(nodeID, flags, member.name + (valid ? " (" + member.type + ")" : ""))) {
				if (valid && ImGui.isItemClicked()) {
					selectObject(member.obj);
				}
				if (valid && member.members.length > 0) {
					generateTreeForMembers(nodeID, member);
				}
				ImGui.treePop();
			}
		}
	}

	function selectObject(obj:Dynamic) {
		if (selectedObject != obj) {
			selectedObject = obj;
			justChangedObject = true;
		}
	}

	// ============ STATE EDITOR METHODS ============

	/** Marks a pre-existing object as edited so it gets written to the patch on save. */
	public function markEdited(obj:FlxBasic) {
		if (obj != null) editedObjects.set(obj, true);
	}

	public function getOrCreateHooks(obj:FlxBasic) {
		var h = objectHooks.get(obj);
		if (h == null)
			objectHooks.set(obj, h = {updateCode: "", clickCode: "", code: null, script: null});
		return h;
	}

	function getEditParent():FlxGroup {
		if (selectedObject is FlxGroup) return cast selectedObject;
		if (selectedObjectData != null && selectedObjectData.groupParent != null && selectedObjectData.groupParent.obj is FlxGroup)
			return cast selectedObjectData.groupParent.obj;
		return cast FlxG.state; // FlxState is a group
	}

	function createInspectorObject() {
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

	/** Records an animation operation for patch export. */
	public function recordAnimOp(sprite:FlxBasic, op:String) {
		var ops = animOps.get(sprite);
		if (ops == null) animOps.set(sprite, ops = []);
		ops.push(op);
		markEdited(sprite);
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
		markEdited(obj);
	}

	public function sortTrack(tr:InspectorTrack) {
		tr.keys.sort(function(a, b) return a.t < b.t ? -1 : (a.t > b.t ? 1 : 0));
	}

	public function armClickCapture(obj:FlxBasic) {
		clickCaptureFor = clickCaptureFor == obj ? null : obj;
	}

	function trackDuration(tr:InspectorTrack):Float {
		return tr.keys.length == 0 ? 0 : tr.keys[tr.keys.length - 1].t;
	}

	public function playTrack(tr:InspectorTrack) {
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
		tr.t += elapsed * tr.dir;
		switch (tr.mode) {
			case 1:
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
		var keys = tr.keys;
		if (keys.length == 0 || !(obj is FlxObject)) return;
		var o:FlxObject = cast obj;
		var a = keys[0];
		var b = keys[0];
		var u = 1.0;
		if (tr.t > keys[0].t) {
			if (tr.t >= keys[keys.length - 1].t) {
				a = b = keys[keys.length - 1];
			} else {
				for (i in 0...keys.length - 1) {
					if (tr.t >= keys[i].t && tr.t <= keys[i + 1].t) {
						a = keys[i];
						b = keys[i + 1];
						var span = b.t - a.t;
						u = span <= 0 ? 1.0 : (tr.t - a.t) / span;
						if (a.ease != null) {
							var ef = Reflect.field(flixel.tweens.FlxEase, a.ease);
							if (ef != null) u = ef(u);
						}
						break;
					}
				}
			}
		}
		o.x = a.x + (b.x - a.x) * u;
		o.y = a.y + (b.y - a.y) * u;
		o.angle = a.angle + (b.angle - a.angle) * u;
		if (obj is FlxSprite) {
			var s:FlxSprite = cast obj;
			s.scale.set(a.scaleX + (b.scaleX - a.scaleX) * u, a.scaleY + (b.scaleY - a.scaleY) * u);
			s.alpha = a.alpha + (b.alpha - a.alpha) * u;
		}
	}

	/** Runs live keyframe playback + click-to-place capture. Called each frame while the editor is open. */
	function tickKeyTracks(elapsed:Float) {
		if (clickCaptureFor != null && FlxG.mouse.justPressed && !ImGuiIO.wantCaptureMouse) {
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
			if (tr.playing) {
				advanceTrack(tr, elapsed);
				applyTrack(obj, tr);
			}
		}
		if (dead != null)
			for (o in dead) keyTracks.remove(o);
	}

	public function deleteInspectorObject(obj:FlxBasic) {
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
		sys.io.File.saveContent(path, content);
	}

	// Keyframe player emitted into patches when any object has a track.
	static var TRACK_PLAYER_SRC = 'var __sneKeyTracks = [];\n'
		+ 'function __snePlayKeys(o, keys, mode) {\n'
		+ '	var t = (mode == 3) ? (keys.length == 0 ? 0.0 : keys[keys.length-1].t) : 0.0;\n'
		+ '	__sneKeyTracks.push({o: o, keys: keys, mode: mode, t: t, dir: (mode == 3) ? -1 : 1});\n'
		+ '}\n'
		+ 'function __sneAnimateKeys(elapsed) {\n'
		+ '	for (tr in __sneKeyTracks) {\n'
		+ '		var keys = tr.keys; var o = tr.o;\n'
		+ '		if (o == null || o.exists == false || keys.length == 0) continue;\n'
		+ '		var dur = keys[keys.length-1].t;\n'
		+ '		if (dur <= 0) continue;\n'
		+ '		tr.t += elapsed * tr.dir;\n'
		+ '		if (tr.mode == 1) { tr.t = tr.t % dur; if (tr.t < 0) tr.t += dur; }\n'
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
package funkin.backend.system.console;
import funkin.backend.scripting.ModState;
import funkin.menus.credits.CreditsMain;
import funkin.editors.stage.StageEditor;
import funkin.game.Stage;
import funkin.game.Character;
import funkin.editors.character.CharacterEditor;
import funkin.options.OptionsMenu;
import funkin.editors.charter.Charter;
import funkin.backend.chart.Chart;
import funkin.menus.TitleState;
import funkin.menus.MainMenuState;
import funkin.menus.FreeplayState;
import funkin.menus.StoryMenuState;
import funkin.backend.system.console.ConsoleCommand;
import funkin.backend.utils.HttpUtil;
import funkin.backend.utils.native.HiddenProcess;
import flixel.input.keyboard.FlxKey;
#if sys
import funkin.backend.utils.ZipUtil;
#end


class BuiltInCommands {
	static var help = new FuncCommand("help", "[object]", "(Shows full list of commands or list of fields on an object or class)", function(args) {
		if (args.length == 0) {
			var strBuf:StringBuf = new StringBuf();
			strBuf.add("\nCommands:");
			for (cmdName in ConsoleCommandManager.commandsStringList) { //use list to go in order
				var cmd = ConsoleCommandManager.getCommand(cmdName);
				strBuf.add("\n\t");
				strBuf.add(cmd.name);
				strBuf.add(" ");
				strBuf.add(cmd.argsDesc);
				strBuf.add("\n\t\t");
				strBuf.add(cmd.desc);
			}
			Logs.infos(strBuf.toString());
		} else {
			@:privateAccess
			var fields = ConsoleUI.instance.consoleHscript.tryGetFields(args[0]);
			if (fields.length == 0) {
				Logs.infos("Failed to find fields for: " + args[0]);
				return;
			}
			var strBuf:StringBuf = new StringBuf();
			strBuf.add("\n");
			strBuf.add(args[0]);
			strBuf.add(":");
			for (f in fields) {
				strBuf.add("\n\t");
				strBuf.add(f.name);
				strBuf.add(":");
				strBuf.add(f.type);
				if (f.value != "") {
					strBuf.add(" = ");
					strBuf.add(f.value);
				}
			}
			Logs.infos(strBuf.toString());
		}
	});
	static var clear = new FuncCommand("clear", "", "(Clears the console log)", function(args) { @:privateAccess ConsoleUI.instance.clearConsole(); });
	static var binds = new FuncCommand("binds", "[filter]", "(Lists the keyboard keys bound to each control)", function(args) {
		var filter = args.length > 0 ? args[0].toUpperCase() : null;
		var strBuf:StringBuf = new StringBuf();
		strBuf.add("\nKeybinds:");
		for (control in Type.allEnums(funkin.backend.system.Controls.Control)) {
			var name = control.getName();
			if (filter != null && name.indexOf(filter) == -1) continue;
			var p1:Array<Dynamic> = Reflect.field(Options, 'P1_$name') ?? [];
			var p2:Array<Dynamic> = Reflect.field(Options, 'P2_$name') ?? [];
			var p1Str = [for (k in p1) '$k'].join(", ");
			var p2Str = [for (k in p2) '$k'].join(", ");
			strBuf.add('\n\t$name  P1=[$p1Str]  P2=[$p2Str]');
		}
		strBuf.add("\n\n\t(keycodes - 113=F2 114=F3 115=F4 116=F5 55=7 56=8 9=TAB)");
		Logs.infos(strBuf.toString());
	});
	static var resetBinds = new FuncCommand("resetbinds", "", "(Clears all saved keybind overrides - defaults come back on restart)", function(args) {
		try {
			var data:Dynamic = Options.__save.data;
			var removed = 0;
			for (f in Reflect.fields(data)) {
				if (f.startsWith("P1_") || f.startsWith("P2_")) {
					Reflect.deleteField(data, f);
					removed++;
				}
			}
			Options.__save.flush();
			Logs.infos('Cleared $removed saved keybinds - restart to restore defaults.');
		} catch (e:Dynamic) Logs.error('Could not clear keybinds: $e');
	});
	static var pause = new FuncCommand("pause", "", "(Toggles pause on game)", function(args) { 
		var game:FunkinGame = cast FlxG.game;
		game.toggleManualPause();
	});
	static var loadSong = new FuncCommand("loadSong", "[song] [diff] [variation] [opponentMode] [coopMode]", "(Loads a new song and switches to PlayState)", function(args) {
		if (args.length == 0) {
			Logs.error("Can't load a song with no name!");
			return;
		}

		var name:String = args[0];
		var diff:String = args[1];
		var variation:String = args[2] != null ? (args[2] == "default" ? null : args[2]) : null;

		var chartPath:String = Paths.chart(name, diff, variation);
		if (Assets.exists(chartPath)) {
			PlayState.loadSong(name, diff, variation, args[3] != null ? args[3] == "true" : false, args[4] != null ? args[4] == "true" : false);
			FlxG.switchState(new PlayState());
		} else {
			Logs.error('Chart for song $name at "$chartPath" was not found.');
		}
	});
	static var endSong = new FuncCommand("endSong", "", "(Ends the current song if in PlayState)", function(args) {
		if (PlayState.instance != null) {
			PlayState.instance.endSong();
		}
	});
	static var loadWeek = new FuncCommand("loadWeek", "[name] [diff]", "(Loads a new week and switches to PlayState)", function(args) {
		if (args.length == 0) return;
		var weeklist = StoryWeeklist.get(true, false);
		for (w in weeklist.weeks) {
			if (args[0] == w.id) {
				var diff = args[1] != null ? args[1] : w.difficulties[w.difficulties.length-1];
				if (w.difficulties.contains(diff)) {
					PlayState.loadWeek(w, diff);
					FlxG.switchState(new PlayState());
					return;
				}
				Logs.error('Difficulty $diff for week ${w.id} was not found.');
				return;
			}
		}
		Logs.error('Week with id ${args[0]} was not found.');
	});
	static var switchMod = new FuncCommand("switchMod", "[name]", "(Switches to another mod, inputting nothing will disable mod)", function(args) { funkin.backend.assets.ModsFolder.switchMod(args[0]); });
	static var reloadMod = new FuncCommand("reloadMod", "", "(Reload current mod)", function(args) { funkin.backend.assets.ModsFolder.reloadMods(); });
	static var preloadShaders = new FuncCommand("preloadShaders", "[name]", "(Pre-compiles one shader, or every shader in shaders/ with no args, to avoid first-use hitching)", function(args) {
		if (args.length == 0 || args[0] == null) {
			funkin.backend.shaders.ShaderPreload.preloadAll();
		} else if (funkin.backend.shaders.ShaderPreload.preload(args[0]) == null) {
			Logs.error('Shader ${args[0]} was not found.');
		}
	});

	static var reloadState = new FuncCommand("reloadState", "", "(Reload current state)", function(args) { FlxG.resetState(); });
	static var goToPlayState = new FuncCommand("goToPlayState", "", "(switches state to PlayState, only works if a song is already loaded)", function(args) { if (PlayState.SONG != null) FlxG.switchState(new PlayState()); });
	static var goToMainMenu = new FuncCommand("goToMainMenu", "", "(switches state to MainMenuState)", function(args) { FlxG.switchState(new MainMenuState()); });
	static var goToStoryMode = new FuncCommand("goToStoryMode", "", "(switches state to StoryMenuState)", function(args) { FlxG.switchState(new StoryMenuState()); });
	static var goToFreeplay = new FuncCommand("goToFreeplay", "[song]", "(switches to FreeplayState; with a song name, pre-selects it)", function(args) {
		if (args[0] != null && args[0] != "") Options.freeplayLastSong = args[0];
		FlxG.switchState(new FreeplayState());
	});
	static var goToOptions = new FuncCommand("goToOptions", "", "(switches state to OptionsMenu)", function(args) { FlxG.switchState(new OptionsMenu()); });
	static var goToCredits = new FuncCommand("goToCredits", "", "(switches state to CreditsMain)", function(args) { FlxG.switchState(new CreditsMain()); });
	static var goToTitle = new FuncCommand("goToTitle", "[reset]", "(switches state to TitleState)", function(args) {
		@:privateAccess
		if (args[0] != null && args[0] == "true") TitleState.initialized = false;
		FlxG.switchState(new TitleState());
	});
	static var goToModState = new FuncCommand("goToModState", "[name]", "(switches state to a custom ModState)", function(args) {
		FlxG.switchState(new ModState(args[0]));
	});
	static var goToState = new FuncCommand("goToState", "[class]", "(switches to any state by class name, e.g. goToState PlayState or funkin.menus.MainMenuState)", function(args) {
		var name = args[0];
		if (name == null || name == "") {
			Logs.error("Usage: goToState <className>");
			return;
		}
		var cls:Class<Dynamic> = Type.resolveClass(name);
		if (cls == null)
			for (p in ["funkin.menus.", "funkin.game.", "funkin.editors.", "funkin.backend.system."]) {
				cls = Type.resolveClass(p + name);
				if (cls != null) break;
			}
		if (cls == null) {
			Logs.error('No state class found for "$name".');
			return;
		}
		try {
			FlxG.switchState(cast Type.createInstance(cls, []));
		} catch(e) {
			Logs.error('Could not switch to $name: $e');
		}
	});

	static var timeScale = new FuncCommand("timeScale", "[scale]", "(sets game speed - 0.5 = half, 2 = double)", function(args) {
		if (args[0] == null || args[0] == "") {
			Logs.trace('timeScale = ${FlxG.timeScale}');
			return;
		}
		var v = Std.parseFloat(args[0]);
		if (Math.isNaN(v) || v <= 0) {
			Logs.error("Usage: timeScale <positive number>");
			return;
		}
		FlxG.timeScale = v;
		Logs.trace('timeScale set to ${FlxG.timeScale}');
	});

	static var botplay = new FuncCommand("botplay", "[on/off]", "(toggles CPU control of all strumlines, PlayState only)", function(args) {
		if (!(FlxG.state is PlayState)) {
			Logs.error("botplay only works in PlayState.");
			return;
		}
		var ps:PlayState = cast FlxG.state;
		var want:Bool;
		if (args[0] == "on" || args[0] == "true") want = true;
		else if (args[0] == "off" || args[0] == "false") want = false;
		else want = !ps.strumLines.members[0].cpu;
		for (s in ps.strumLines.members) s.cpu = want;
		ps.canDie = ps.canDadDie = !want;
		Logs.trace('botplay ${want ? "on" : "off"}');
	});

	static var perf = new FuncCommand("perf", "", "(toggles the performance overlay: frame times, fps, memory)", function(args) {
		#if IMGUI_ENABLED
		@:privateAccess ConsoleUI.instance.consoleInspector.showPerf = !@:privateAccess ConsoleUI.instance.consoleInspector.showPerf;
		#else
		Logs.error("No imgui overlay on this build.");
		#end
	});

	static var skipTo = new FuncCommand("skipTo", "<ms>", "(jumps the song to a position, reseeks audio, drops earlier notes)", function(args) {
		if (!(FlxG.state is PlayState)) {
			Logs.error("skipTo only works in PlayState.");
			return;
		}
		var ms = Std.parseFloat(args[0]);
		if (Math.isNaN(ms) || ms < 0) {
			Logs.error("Usage: skipTo <milliseconds>");
			return;
		}
		(cast FlxG.state : PlayState).skipTo(ms);
		Logs.trace('skipped to ${Math.round(ms / 10) / 100}s');
	});

	static var practice = new FuncCommand("practice", "[on/off]", "(practice mode: no death, F8 respawns at the last measure)", function(args) {
		if (!(FlxG.state is PlayState)) {
			Logs.error("practice only works in PlayState.");
			return;
		}
		var ps:PlayState = cast FlxG.state;
		var want:Bool;
		if (args[0] == "on" || args[0] == "true") want = true;
		else if (args[0] == "off" || args[0] == "false") want = false;
		else want = !ps.practice;
		ps.practice = want;
		ps.canDie = !want;
		Logs.trace(want ? "practice on - F8 restarts at the last measure" : "practice off");
	});

	static var reloadChart = new FuncCommand("reloadChart", "", "(re-parses the chart from disk and restarts the song)", function(args) {
		if (PlayState.SONG == null) {
			Logs.error("No song loaded.");
			return;
		}
		try {
			Chart.parse(PlayState.SONG.meta.name, PlayState.difficulty, PlayState.variation);
		}
		catch (e:Dynamic) {
			Logs.error('Chart reload failed, staying on the current one: $e');
			return;
		}
		FlxG.resetState();
	});

	static var reloadScripts = new FuncCommand("reloadScripts", "", "(safe reload of the current state's scripts; reports errors instead of crashing)", function(args) {
		if (!(FlxG.state is funkin.backend.MusicBeatState)) {
			Logs.error("Current state has no scripts to reload.");
			return;
		}
		try {
			(cast FlxG.state : funkin.backend.MusicBeatState).stateScripts.reload();
			Logs.trace("State scripts reloaded (F5 works too)");
		}
		catch (e:Dynamic) Logs.error('Script reload failed: $e');
	});

	static var toggleScripts = new FuncCommand("toggleScripts", "", "(enables/disables all of the current state's scripts - live patch toggle)", function(args) {
		if (!(FlxG.state is funkin.backend.MusicBeatState)) {
			Logs.error("Current state has no scripts.");
			return;
		}
		var scripts = (cast FlxG.state : funkin.backend.MusicBeatState).stateScripts.scripts;
		var anyOn = false;
		for (s in scripts) if (s.active) { anyOn = true; break; }
		for (s in scripts) s.active = !anyOn;
		Logs.trace('state scripts ${anyOn ? "disabled" : "enabled"} (${scripts.length})');
	});

	static var mods = new FuncCommand("mods", "", "(lists loaded mod libraries in resolution order; first wins)", function(args) {
		var libs = funkin.backend.assets.ModsFolder.getLoadedModsLibs();
		var buf = new StringBuf();
		buf.add('\nMods (current: ${funkin.backend.assets.ModsFolder.currentModFolder ?? "none"}):');
		for (l in libs) buf.add('\n\t${l.libName ?? l.prefix ?? "?"}  -  ${l.basePath}');
		Logs.infos(buf.toString());
	});

	static var scripts = new FuncCommand("scripts", "", "(lists scripts attached to the current state and their status)", function(args) {
		if (!(FlxG.state is funkin.backend.MusicBeatState)) {
			Logs.error("Current state has no scripts.");
			return;
		}
		var buf = new StringBuf();
		buf.add("\nScripts:");
		for (s in (cast FlxG.state : funkin.backend.MusicBeatState).stateScripts.scripts)
			buf.add('\n\t${s.fileName ?? s.path}  active=${s.active}  loaded=${@:privateAccess s.didLoad}');
		Logs.infos(buf.toString());
	});

	static var findasset = new FuncCommand("findasset", "<text>", "(greps data/ across all loaded asset libraries for references)", function(args) {
		#if sys
		var needle = args[0];
		if (needle == null || needle == "") {
			Logs.error("Usage: findasset <text>");
			return;
		}
		var hits = 0;
		function scan(dir:String, lib:String) {
			if (hits >= 25 || !sys.FileSystem.exists(dir)) return;
			for (f in sys.FileSystem.readDirectory(dir)) {
				if (hits >= 25) break;
				var p = '$dir/$f';
				if (sys.FileSystem.isDirectory(p)) scan(p, lib);
				else if (StringTools.endsWith(f.toLowerCase(), ".hx") || StringTools.endsWith(f.toLowerCase(), ".xml")
					|| StringTools.endsWith(f.toLowerCase(), ".json") || StringTools.endsWith(f.toLowerCase(), ".txt")) {
					try {
						var lines = sys.io.File.getContent(p).split("\n");
						for (i => line in lines)
							if (line.indexOf(needle) >= 0) {
								Logs.trace('[$lib] $p:${i + 1}: ${StringTools.trim(line)}');
								if (++hits >= 25) break;
							}
					}
					catch (e:Dynamic) {}
				}
			}
		}
		for (l in funkin.backend.assets.ModsFolder.getLoadedModsLibs()) scan('${l.basePath}/data', l.libName ?? l.basePath);
		if (hits == 0) Logs.trace('no references to "$needle" found in data/');
		else if (hits >= 25) Logs.trace("(results capped at 25)");
		#else
		Logs.error("findasset needs a sys target.");
		#end
	});

	static var findstate = new FuncCommand("findstate", "<name>", "(resolves a fuzzy name to state class names you can pass to goToState)", function(args) {
		var name = args[0];
		if (name == null || name == "") {
			Logs.error("Usage: findstate <name>");
			return;
		}
		var found = [];
		for (c in [name, '${name}State', 'funkin.menus.$name', 'funkin.menus.${name}State',
				'funkin.game.$name', 'funkin.editors.$name', 'funkin.editors.${name}Editor',
				'funkin.backend.system.$name'])
			if (!found.contains(c) && Type.resolveClass(c) != null) found.push(c);
		if (found.length > 0) Logs.infos('found: ${found.join(", ")}');
		else Logs.error('no state class matches "$name" - try goToModState for scripted states');
	});

	static var clean = new FuncCommand("clean", "[dir]", "(wipes generated dirs: renders/, exports/, crash/ - or one given name)", function(args) {
		#if sys
		var targets = (args[0] != null && args[0] != "") ? [args[0]] : ["renders", "exports", "crash"];
		for (dir in targets) {
			if (!sys.FileSystem.exists(dir)) continue;
			var n = 0;
			for (f in sys.FileSystem.readDirectory(dir)) {
				var p = '$dir/$f';
				if (sys.FileSystem.isDirectory(p)) continue;
				try { sys.FileSystem.deleteFile(p); n++; } catch (e:Dynamic) {}
			}
			Logs.trace('cleaned $n file(s) from $dir/');
		}
		#else
		Logs.error("clean needs a sys target.");
		#end
	});

	static var resetEditor = new FuncCommand("resetEditor", "", "(wipes saved editor settings + console history)", function(args) {
		try {
			FlxG.save.data.sneEditor = null;
			FlxG.save.data.sneConsoleHistory = null;
			FlxG.save.flush();
			Logs.trace("editor settings wiped - reopen the editor to start fresh");
		}
		catch (e:Dynamic) Logs.error('resetEditor failed: $e');
	});

	static var version = new FuncCommand("version", "", "(prints engine build info for bug reports)", function(args) {
		Logs.infos('${funkin.backend.system.Flags.VERSION_MESSAGE} - API ${funkin.backend.system.Flags.CURRENT_API_VERSION}');
	});

	static var watch = new FuncCommand("watch", "[expression]", "(toggles the watch window; with an expression, adds it as a watched value)", function(args) {
		#if IMGUI_ENABLED
		@:privateAccess var ins = ConsoleUI.instance.consoleInspector;
		if (ins == null) {
			Logs.error("Open the inspector (F4) once first so the watch window exists.");
			return;
		}
		if (args.length > 0 && args[0] != "") {
			var expr = args.join(" ");
			if (!ins.watchList.contains(expr)) ins.watchList.push(expr);
			if (!ins.showWatch) { ins.showWatch = true; @:privateAccess ins.showWatchPtr.value = true; }
			Logs.trace('watching: $expr');
		}
		else ins.showWatch = !ins.showWatch;
		#else
		Logs.error("No imgui overlay on this build.");
		#end
	});

	static var crashes = new FuncCommand("crashes", "", "(lists saved crash logs in crash/ - view one with opencrash <n>)", function(args) {
		#if sys
		if (!sys.FileSystem.exists("crash")) {
			Logs.trace("no crash logs - nothing has crashed yet, nice");
			return;
		}
		var files = [for (f in sys.FileSystem.readDirectory("crash")) if (f.endsWith(".log")) f];
		files.sort(function(a, b) return a > b ? -1 : 1);
		var buf = new StringBuf();
		buf.add('\nCrash logs (${files.length}):');
		for (i => f in files) buf.add('\n\t${i + 1}. $f');
		buf.add("\n\tuse `opencrash <n>` to view one");
		Logs.infos(buf.toString());
		#else
		Logs.error("crashes needs a sys target.");
		#end
	});

	static var opencrash = new FuncCommand("opencrash", "<n>", "(prints crash log #n from the crashes list into the console)", function(args) {
		#if sys
		if (!sys.FileSystem.exists("crash")) {
			Logs.error("no crash logs found.");
			return;
		}
		var files = [for (f in sys.FileSystem.readDirectory("crash")) if (f.endsWith(".log")) f];
		files.sort(function(a, b) return a > b ? -1 : 1);
		var n = Std.parseInt(args[0]);
		if (n == null || n < 1 || n > files.length) {
			Logs.error('Usage: opencrash <1-${files.length}>');
			return;
		}
		var content = sys.io.File.getContent('crash/${files[n - 1]}');
		var lines = content.split("\n");
		Logs.infos('\n--- ${files[n - 1]} ---');
		for (i in 0...Std.int(Math.min(lines.length, 60))) Logs.infos(lines[i]);
		if (lines.length > 60) Logs.infos('... (${lines.length - 60} more lines, open the file for the rest)');
		#else
		Logs.error("opencrash needs a sys target.");
		#end
	});

	static var downloadFFmpeg = new FuncCommand("downloadFFmpeg", "", "(downloads ffmpeg next to the exe so the video renderer works, ~100MB)", function(args) {
		#if (sys && windows)
		Logs.trace("Downloading ffmpeg - this can take a minute on a slow connection...");
		sys.thread.Thread.create(function() {
			var exeDir = haxe.io.Path.directory(Sys.programPath());
			var zipPath = '$exeDir/.ffmpeg-download.zip';
			try {
				var mirrors = [
					"https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip",
					"https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
				];
				var extracted = 0;
				for (url in mirrors) {
					try {
						// curl (bundled in Windows 10+) handles CDN redirects properly; fall back to haxe.Http
						var ok = false;
						try {
							var proc = new HiddenProcess("curl", ["-sSL", "-f", "-o", zipPath, url]);
							var code = proc.exitCode();
							proc.close();
							ok = code == 0;
						}
						catch (e:Dynamic) {}
						if (!ok) {
							var bytes = HttpUtil.requestBytes(url);
							sys.io.File.saveBytes(zipPath, bytes);
						}
						if (!sys.FileSystem.exists(zipPath) || sys.FileSystem.stat(zipPath).size < 10000000) {
							Logs.trace('download from $url was suspiciously small, trying next mirror', WARNING);
							continue;
						}

						var zip = ZipUtil.openZip(zipPath);
						var gotHere = 0;
						for (entry in zip.read()) {
							var base = entry.fileName.toLowerCase().split("/").pop();
							if (base != "ffmpeg.exe" && base != "ffprobe.exe") continue;
							sys.io.File.saveBytes('$exeDir/$base', ZipUtil.unzip(entry));
							gotHere++;
						}
						if (gotHere > 0) {
							extracted = gotHere;
							break;
						}
						Logs.trace('archive from $url contained no ffmpeg.exe, trying next mirror', WARNING);
					}
					catch (e:Dynamic) Logs.trace('ffmpeg mirror failed ($url): $e', WARNING);
				}
				try sys.FileSystem.deleteFile(zipPath) catch (e:Dynamic) {}

				if (extracted > 0 && funkin.backend.system.VideoEncoder.recheck())
					Logs.trace("ffmpeg is ready next to the exe - the video renderer works now.");
				else
					Logs.error("Every ffmpeg mirror failed - check your internet connection.");
			}
			catch (e:Dynamic) {
				Logs.error('ffmpeg download failed: $e');
			}
		});
		#else
		Logs.error("downloadFFmpeg only works on Windows builds - grab it from ffmpeg.org or your package manager.");
		#end
	});

	static var recordInputs = new FuncCommand("recordInputs", "", "(restarts the state and records all inputs; stop with stopInputs)", function(args) {
		#if FLX_RECORD
		FlxG.vcr.startRecording(true);
		Logs.trace("Recording inputs - play through what you want to capture, then run stopInputs");
		#else
		Logs.error("Input recording requires the FLX_RECORD define.");
		#end
	});
	static var stopInputs = new FuncCommand("stopInputs", "[file]", "(stops input recording and saves it, default exports/replay.fgr)", function(args) {
		#if (FLX_RECORD && sys)
		var path = args[0] != null && args[0] != "" ? args[0] : "exports/replay.fgr";
		var data = FlxG.vcr.stopRecording(false);
		if (data == null) {
			Logs.error("Not currently recording.");
			return;
		}
		try {
			var dir = haxe.io.Path.directory(path);
			if (dir != "" && !sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
			sys.io.File.saveContent(path, data);
			Logs.trace('Saved input recording to $path');
		} catch(e) Logs.error('Could not save recording: $e');
		#else
		Logs.error("Input recording requires the FLX_RECORD define.");
		#end
	});
	static var playInputs = new FuncCommand("playInputs", "[file]", "(replays a recorded input file in the current state, default exports/replay.fgr)", function(args) {
		#if (FLX_RECORD && sys)
		var path = args[0] != null && args[0] != "" ? args[0] : "exports/replay.fgr";
		if (!sys.FileSystem.exists(path)) {
			Logs.error('No recording at $path - use recordInputs + stopInputs first.');
			return;
		}
		try {
			FlxG.vcr.loadReplay(sys.io.File.getContent(path));
			Logs.trace('Playing inputs from $path');
		} catch(e) Logs.error('Could not play recording: $e');
		#else
		Logs.error("Input recording requires the FLX_RECORD define.");
		#end
	});

	static var goToCharter = new FuncCommand("goToCharter", "[song] [diff] [variation]", "(opens chart editor, inputting nothing will load existing song)", function(args) {
		if (args.length == 0) {
			if (PlayState.SONG == null) {
				Logs.error("Charter doesn't have any song data loaded!");
			} else {
				@:privateAccess
				if (Charter.__song == null || (PlayState.SONG != null && PlayState.SONG.meta != null && PlayState.SONG.meta.name != Charter.__song) || PlayState.difficulty != Charter.__diff || PlayState.variation != Charter.__variant) {
					FlxG.switchState(new Charter(PlayState.SONG.meta.name, PlayState.difficulty, PlayState.variation)); //load fresh charter, can't load previous because PlayState.SONG probably changed
				} else {
					@:privateAccess
					FlxG.switchState(new Charter(Charter.__song, Charter.__diff, Charter.__variant, false));
				}
			}
			return;
		}

		var name:String = args[0];
		var diff:String = args[1];
		var variation:String = args[2] != null ? (args[2] == "default" ? null : args[2]) : null;

		var chartPath:String = Paths.chart(name, diff, variation);
		if (Assets.exists(chartPath)) {
			FlxG.switchState(new Charter(name, diff, variation));
		} else {
			Logs.error('Chart for song $name at "$chartPath" was not found.');
		}
	});

	static var goToCharacterEditor = new FuncCommand("goToCharacterEditor", "[name]", "(opens character editor)", function(args) {
		if (args.length == 0) {
			Logs.error("Can't load a character with no name!");
			return;
		}
		var name:String = args[0];
		var list = Character.getList(false, false, null, true);
		if (!list.contains(name)) {
			Logs.error('Character $name was not found.');
			return;
		}

		FlxG.switchState(new CharacterEditor(name));
	});

	static var goToStageEditor = new FuncCommand("goToStageEditor", "[name]", "(opens stage editor)", function(args) {
		if (args.length == 0) {
			Logs.error("Can't load a stage with no name!");
			return;
		}
		var name:String = args[0];
		var list = Stage.getList(false, true);
		if (!list.contains(name)) {
			Logs.error('stage $name was not found.');
			return;
		}

		FlxG.switchState(new StageEditor(name));
	});
}

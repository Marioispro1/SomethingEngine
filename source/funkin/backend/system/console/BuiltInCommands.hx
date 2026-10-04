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
	static var goToFreeplay = new FuncCommand("goToFreeplay", "", "(switches state to FreeplayState)", function(args) { FlxG.switchState(new FreeplayState()); });
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
							var proc = new sys.io.Process("curl", ["-sSL", "-f", "-o", zipPath, url]);
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
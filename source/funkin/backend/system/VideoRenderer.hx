package funkin.backend.system;

#if IMGUI_ENABLED
import lime.tools.imgui.ImGui;
import lime.tools.imgui.ImGuiFlags;
import lime.tools.imgui.ImGuiIO;
import lime.tools.imgui.ImGuiTypes;
#end

typedef VideoRenderSettings = {
	var fps:Float;

	var startMs:Float;

	var endMs:Float;

	var includeCountdown:Bool;

	var botplay:Bool;

	var uncapped:Bool;

	var encode:Bool;

	var width:Int;

	var height:Int;

	var gif:Bool;

	/** 0 = H.264, 1 = H.265, 2 = VP9, 3 = ProRes. */
	var codec:Int;

	var crf:Float;

	/** 0 = fastest .. 4 = slowest/best, mapped per codec. */
	var preset:Int;
}

typedef RenderResolution = {
	var name:String;
	var width:Int;
	var height:Int;
}

class VideoRenderer {
	public static var settings:VideoRenderSettings = defaultSettings();

	public static function defaultSettings():VideoRenderSettings
		return {
			fps: 60, startMs: 0, endMs: 0,
			includeCountdown: true, botplay: true, uncapped: true, encode: true,
			width: 0, height: 0, gif: false,
			codec: 0, crf: 18, preset: 2
		};

	static inline var maxLoopRate:Int = 1000;

	public static var requested:Bool = false;

	/** .fgr replay data consumed by PlayState on next create; set when rendering a recorded run. */
	public static var replayPending:String = null;

	public static var active(default, null):Bool = false;

	public static var armed(get, never):Bool;

	static inline function get_armed():Bool
		return requested || active;

	public static var fps:Float = 60;

	public static var frameIndex:Int = 0;

	public static var startMs:Float = 0;

	public static var endMs:Float = Math.POSITIVE_INFINITY;

	public static var startedAt(default, null):Float = 0;

	public static var audioAssets:Array<String> = [];

	public static var frameDelta(get, never):Float;

	static inline function get_frameDelta():Float
		return 1000 / fps;

	public static var songTime(get, never):Float;

	static inline function get_songTime():Float
		return startMs + frameIndex * frameDelta;

	public static var finished(get, never):Bool;

	static inline function get_finished():Bool
		return songTime >= endMs;

	public static var failed(get, never):Bool;

	static inline function get_failed():Bool
		return active && settings.encode && VideoEncoder.broken;

	public static var totalFrames(get, never):Int;

	static function get_totalFrames():Int
		return Math.isFinite(endMs) ? Std.int(Math.max(1, Math.ceil((endMs - startMs) / frameDelta))) : 0;

	public static var progress(get, never):Float;

	static function get_progress():Float {
		final total = totalFrames;
		return total <= 0 ? 0 : Math.min(1, frameIndex / total);
	}

	public static var elapsed(get, never):Float;

	static function get_elapsed():Float
		return startedAt <= 0 ? 0 : haxe.Timer.stamp() - startedAt;

	public static var eta(get, never):Float;

	static function get_eta():Float {
		final p = progress;
		return (p <= 0 || elapsed <= 0) ? -1 : elapsed * (1 - p) / p;
	}

	public static var realFps(get, never):Float;

	static function get_realFps():Float
		return elapsed <= 0 ? 0 : frameIndex / elapsed;

	static var prevUpdateFramerate:Int = 0;
	static var prevDrawFramerate:Int = 0;
	static var prevAutoPause:Bool = true;
	static var prevWindowWidth:Int = 0;
	static var prevWindowHeight:Int = 0;
	static var prevWindowX:Int = 0;
	static var prevWindowY:Int = 0;
	static var prevBorderless:Bool = false;

	/** Output label for the detached progress window. */
	public static var currentLabel:String = null;

	public static function begin(clockStartMs:Float, songEndMs:Float, ?outputName:String):Void {
		final s = settings;

		fps = s.fps > 0 ? s.fps : 60;
		startMs = clockStartMs;
		endMs = s.endMs > 0 ? s.endMs
			: (songEndMs > 0 && Math.isFinite(songEndMs) ? songEndMs : Math.POSITIVE_INFINITY);

		frameIndex = 0;
		framePending = false;
		active = true;
		startedAt = haxe.Timer.stamp();

		Conductor.timeSource = () -> songTime;

		prevUpdateFramerate = FlxG.updateFramerate;
		prevDrawFramerate = FlxG.drawFramerate;
		FlxG.fixedTimestep = true;

		prevAutoPause = FlxG.autoPause;
		FlxG.autoPause = false;

		setFramerates(Std.int(fps), Std.int(fps));
		if (s.uncapped) FlxG.stage.frameRate = maxLoopRate;

		FlxG.random.resetInitialSeed();

		applyOutputSize();

		currentLabel = outputName;

		// clean capture: hide the dev console + state editor so nothing but gameplay is on screen
		#if IMGUI_ENABLED
		try {
			var ui = funkin.backend.system.console.ConsoleUI.instance;
			if (ui != null) {
				if (@:privateAccess ui.active) ui.toggleUI();
				if (@:privateAccess ui.inspectorActive) ui.toggleInspector();
			}
		}
		catch (e:Dynamic) {}
		hookImgui();
		#end

		if (s.encode) {
			VideoEncoder.start(outputName != null ? outputName : "render", fps);
			VideoEncoder.note('settings: fps=${s.fps} start=${s.startMs}ms end=${s.endMs}ms countdown=${s.includeCountdown}'
				+ ' botplay=${s.botplay} uncapped=${s.uncapped} size=${s.width}x${s.height}'
				+ ' | clock ${startMs}ms..${endMs}ms');
		}
	}

	static final presetSizes:Array<Array<Int>> = [
		[854, 480], [1280, 720], [1600, 900], [1920, 1080],
		[2560, 1440], [3200, 1800], [3840, 2160], [5120, 2880], [7680, 4320]
	];

	static final modeScanAbove:Int = 1920 * 1080;

	static inline function window():lime.ui.Window
		return openfl.Lib.application != null ? openfl.Lib.application.window : null;

	static function currentDisplay():lime.system.Display {
		final win = window();
		var display = win != null ? win.display : null;

		if (display == null) {
			try {
				if (lime.system.System.numDisplays > 0) display = lime.system.System.getDisplay(0);
			}
			catch (e:Dynamic) {}
		}

		return display;
	}

	public static function captureScale():Float {
		final win = window();
		return win != null && win.scale > 0 ? win.scale : 1;
	}

	public static function maxOutputSize():RenderResolution {
		var w = 0, h = 0;

		final display = currentDisplay();
		if (display != null) {
			if (display.currentMode != null && display.currentMode.width > 0) {
				w = display.currentMode.width;
				h = display.currentMode.height;
			}
			else if (display.bounds != null) {
				w = Std.int(display.bounds.width);
				h = Std.int(display.bounds.height);
			}
		}

		final win = window();
		if ((w <= 0 || h <= 0) && win != null) {
			w = win.width;
			h = win.height;
		}

		if (w <= 0 || h <= 0) return {name: "1920 x 1080", width: 1920, height: 1080};

		final scale = captureScale();
		w = Std.int(w * scale);
		h = Std.int(h * scale);
		return {name: '$w x $h', width: w, height: h};
	}

	public static function resolutionOptions():Array<RenderResolution> {
		final max = maxOutputSize();
		final sizes:Array<RenderResolution> = [];

		function push(w:Int, h:Int):Void {
			if (w <= 0 || h <= 0 || w > max.width || h > max.height) return;
			for (size in sizes) if (size.width == w && size.height == h) return;
			sizes.push({name: '$w x $h', width: w, height: h});
		}

		for (preset in presetSizes) push(preset[0], preset[1]);

		final display = currentDisplay();
		if (display != null && display.supportedModes != null) {
			final scale = captureScale();
			for (mode in display.supportedModes) {
				final w = Std.int(mode.width * scale);
				final h = Std.int(mode.height * scale);
				if (w * h > modeScanAbove) push(w, h);
			}
		}

		push(max.width, max.height);

		sizes.sort((a, b) -> a.width * a.height - b.width * b.height);

		final options:Array<RenderResolution> = [
			{name: TU.translate("videoRender.res.window"), width: 0, height: 0}
		];

		for (size in sizes)
			options.push({
				name: size.width == max.width && size.height == max.height
					? '${size.name} ${TU.translate("videoRender.res.display")}'
					: size.name,
				width: size.width,
				height: size.height
			});

		return options;
	}

	public static function applyOutputSize():Void {
		final s = settings;
		if (s.width <= 0 || s.height <= 0) return;

		final win = window();
		if (win == null) return;

		final scale = captureScale();
		final winW = Math.round(s.width / scale);
		final winH = Math.round(s.height / scale);

		final display = win.display;
		final bounds = display != null ? display.bounds : null;

		final borderless = bounds != null && (winW >= bounds.width || winH >= bounds.height);

		if (win.width == winW && win.height == winH && win.borderless == borderless) return;

		if (prevWindowWidth <= 0) {
			prevWindowWidth = win.width;
			prevWindowHeight = win.height;
			prevWindowX = win.x;
			prevWindowY = win.y;
			prevBorderless = win.borderless;
		}

		if (win.borderless != borderless) win.borderless = borderless;
		win.resize(winW, winH);

		if (bounds != null) {
			if (borderless) win.move(Std.int(bounds.x), Std.int(bounds.y));
			else win.move(Std.int(bounds.x + (bounds.width - winW) / 2), Std.int(bounds.y + (bounds.height - winH) / 2));
		}
	}

	static var framePending:Bool = false;

	public static inline function advance():Void {
		frameIndex++;
		framePending = true;
	}

	public static function consumeFrame():Bool {
		if (!framePending) return false;
		framePending = false;
		return true;
	}

	public static function finish():Void {
		requested = false;

		if (!active) {
			restoreWindowSize();
			return;
		}
		active = false;

		VideoEncoder.stop(audioAssets, settings.startMs, settings.startMs - startMs, frameIndex);
		audioAssets = [];

		Conductor.timeSource = null;
		FlxG.fixedTimestep = false;
		FlxG.autoPause = prevAutoPause;

		if (prevUpdateFramerate > 0) {
			setFramerates(prevUpdateFramerate, prevDrawFramerate);
			prevUpdateFramerate = prevDrawFramerate = 0;
		}

		restoreWindowSize();
	}

	static function setFramerates(update:Int, draw:Int):Void {
		if (FlxG.updateFramerate < update) {
			FlxG.updateFramerate = update;
			FlxG.drawFramerate = draw;
		} else {
			FlxG.drawFramerate = draw;
			FlxG.updateFramerate = update;
		}
	}

	static function restoreWindowSize():Void {
		if (prevWindowWidth <= 0 || prevWindowHeight <= 0) return;

		final win = window();
		if (win != null) {
			if (win.borderless != prevBorderless) win.borderless = prevBorderless;

			win.resize(prevWindowWidth, prevWindowHeight);
			win.move(prevWindowX, prevWindowY);
		}

		prevWindowWidth = prevWindowHeight = 0;
		prevWindowX = prevWindowY = 0;
		prevBorderless = false;
	}

	public static function formatTime(ms:Float):String {
		if (ms < 0 || !Math.isFinite(ms)) return "--:--";

		final totalSeconds = Std.int(ms / 1000);
		final seconds = totalSeconds % 60;
		return '${Std.int(totalSeconds / 60)}:${seconds < 10 ? "0" : ""}$seconds';
	}

	#if IMGUI_ENABLED
	static var imguiHooked:Bool = false;

	static function hookImgui() {
		if (imguiHooked) return;
		imguiHooked = true;
		// multi-viewport on: the progress window opens as its own OS window next to the game
		ImGuiIO.configFlags |= ImGuiConfigFlags.ViewportsEnable;
		try lime.tools.imgui.ImGuiHandler.instance.addCallback(drawRenderWindow)
		catch (e:Dynamic) {}
	}

	/**
	 * Detached render-progress window. ImGui viewports are enabled, so once it lands outside the
	 * main viewport it becomes its own OS window; it's also drawn after the frame capture so it
	 * never shows up in the video.
	 */
	static function drawRenderWindow() {
		if (!active) return;
		var vp = ImGui.getMainViewport();
		ImGui.setNextWindowPos(vp.posX + vp.sizeX + 16, vp.posY + 32, ImGuiCond.FirstUseEver);
		ImGui.setNextWindowBGAlpha(0.85);
		var flags = ImGuiWindowFlags.AlwaysAutoResize | ImGuiWindowFlags.NoCollapse | ImGuiWindowFlags.NoNav;
		if (ImGui.begin('Video Render##progress', null, flags)) {
			ImGui.text(currentLabel ?? "render");
			var total = totalFrames;
			ImGui.progressBar(progress, 300, 16);
			ImGui.text(total > 0
				? '$frameIndex / $total frames   ${Std.int(progress * 100)}%'
				: '$frameIndex frames');
			var e = eta;
			if (e > 0 && total > 0)
				ImGui.text('ETA ${formatTime(e * 1000)}   -   '
					+ '${Math.round(realFps * 10) / 10} render fps   -   ${formatTime(elapsed * 1000)} elapsed');
			else
				ImGui.text('${formatTime(elapsed * 1000)} elapsed');
		}
		ImGui.end();
	}
	#end
}

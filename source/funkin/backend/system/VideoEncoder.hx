package funkin.backend.system;

import lime.utils.UInt8Array;

typedef VideoRenderResult = {
	var path:String;
	var frames:Int;
	var fps:Float;

	var seconds:Float;

	var gifPath:String;

	var error:String;
}

class VideoEncoder {
	public static inline var outputDir:String = "renders";



	public static var active(default, null):Bool = false;

	public static var outputPath(default, null):String = null;

	public static var framesWritten(default, null):Int = 0;

	public static var lastError(default, null):String = null;

	public static var lastResult:VideoRenderResult = null;

	public static var broken(default, null):Bool = false;

	static var startedStamp:Float = 0;
	static var outputFps:Float = 60;

	#if sys
	static var proc:sys.io.Process = null;
	static var pixels:UInt8Array = null;
	static var pixelBytes:haxe.io.Bytes = null;
	static var frameSize:Int = 0;
	static var width:Int = 0;
	static var height:Int = 0;

	static var silentPath:String = null;

	static var hooked:Bool = false;
	static var logTail:Array<String> = [];

	static var mismatchedFrames:Int = 0;

	static inline var mismatchGraceFrames:Int = 120;

	static var framerateWasVisible:Bool = true;

	static var ffmpegFound:Null<Bool> = null;
	#end

	/** Re-probes for ffmpeg - call after installing it so the renderer unlocks without a restart. */
	public static function recheck():Bool {
		#if sys
		ffmpegFound = null;
		#end
		return available();
	}

	public static function available():Bool {
		#if sys
		if (ffmpegFound != null) return ffmpegFound;

		try {
			var probe = new sys.io.Process("ffmpeg", ["-version"]);
			probe.exitCode();
			probe.close();
			ffmpegFound = true;
		}
		catch (e:Dynamic) ffmpegFound = false;

		return ffmpegFound;
		#else
		return false;
		#end
	}

	static var _gpuName:String = null;

	/** GL renderer string, e.g. "ANGLE (NVIDIA GeForce RTX 3060 ...)" - cached after first query. */
	public static function gpuName():String {
		#if sys
		if (_gpuName != null) return _gpuName;
		var name = "";
		try {
			var gl = FlxG.stage.window.context.webgl;
			if (gl != null) name = Std.string(gl.getParameter(gl.RENDERER));
		}
		catch (e:Dynamic) {}
		_gpuName = name;
		return name;
		#else
		return "";
		#end
	}

	/** "nvidia" | "amd" | "" - the vendor best suited to hardware encoding here. */
	public static function gpuVendor():String {
		var n = gpuName().toLowerCase();
		return n.contains("nvidia") ? "nvidia"
			: (n.contains("amd") || n.contains("ati")) ? "amd"
			: "";
	}

	/** Codec index best matched to the GPU: nvenc for NVIDIA, amf for AMD, else software h264. */
	public static function recommendedCodec():Int
		return switch (gpuVendor()) {
			case "nvidia": 4;
			case "amd": 6;
			default: 0;
		}

	static var mixing:Bool = false;

	/** Mixes inst+voices into a single mp3 in renders/ on a worker thread - no video render needed. */
	public static function exportAudioMix(audioAssets:Array<String>, outName:String):Void {
		#if sys
		if (active || mixing) { log('audio export skipped - encoder is busy', WARNING); return; }
		mixing = true;
		sys.thread.Thread.create(function() {
			try {
				var tracks = extractAudio(audioAssets);
				var outPath = haxe.io.Path.join([outputDir, outName + ".mp3"]);
				if (tracks.length == 0) {
					log('audio export: no audio assets found for $outName', WARNING);
				}
				else {
					var args = ["-y", "-hide_banner", "-loglevel", "error"];
					for (t in tracks) { args.push("-i"); args.push(t); }
					if (tracks.length > 1) {
						args.push("-filter_complex");
						args.push('amix=inputs=${tracks.length}:normalize=0');
					}
					for (a in ["-c:a", "libmp3lame", "-q:a", "2", outPath]) args.push(a);

					var code = -1;
					try {
						var p = new sys.io.Process("ffmpeg", args);
						var err = readAll(p.stderr);
						code = p.exitCode();
						p.close();
						if (code != 0) logTail = err.split("\n");
					}
					catch (e:Dynamic) {}

					if (code == 0 && sys.FileSystem.exists(outPath)) log('audio mix exported: $outPath');
					else log('audio mix failed ($code): ${logTail.join(" | ")}', ERROR);
				}
				for (t in tracks) remove(t);
			}
			catch (e:Dynamic) log('audio mix failed: $e', ERROR);
			mixing = false;
		});
		#end
	}

	/** Container extension for the selected codec: h264/h265/nvenc/amf -> mp4, vp9 -> webm, prores -> mov. */
	public static function codecExt():String
		return switch (VideoRenderer.settings.codec) {
			case 2: "webm";
			case 3: "mov";
			default: "mp4";
		}

	static function codecLabel():String
		return switch (VideoRenderer.settings.codec) {
			case 1: "h265";
			case 2: "vp9";
			case 3: "prores";
			case 4: "h264_nvenc";
			case 5: "hevc_nvenc";
			case 6: "h264_amf";
			case 7: "hevc_amf";
			case 8: "av1_nvenc";
			case 9: "av1_amf";
			default: "h264";
		}

	/** ffmpeg args for the chosen codec; preset index 0-4 maps to each encoder's speed/quality ladder. */
	static function codecArgs():Array<String> {
		var s = VideoRenderer.settings;
		var crf = Std.string(Math.round(s.crf));
		return switch (s.codec) {
			case 1: ["-c:v", "libx265",
				"-preset", ["ultrafast", "veryfast", "fast", "medium", "slow"][s.preset],
				"-crf", crf, "-tag:v", "hvc1", "-pix_fmt", "yuv420p"];
			case 2: ["-c:v", "libvpx-vp9",
				"-deadline", "realtime",
				"-cpu-used", ["8", "6", "4", "2", "0"][s.preset],
				"-crf", crf, "-b:v", "0", "-row-mt", "1", "-pix_fmt", "yuv420p"];
			case 3: ["-c:v", "prores_ks",
				"-profile:v", ["4", "4", "3", "2", "2"][s.preset],
				"-vendor", "apl0", "-pix_fmt", "yuv422p10le"];
			case 4: ["-c:v", "h264_nvenc",
				"-preset", ["p1", "p2", "p4", "p6", "p7"][s.preset],
				"-rc", "vbr", "-cq", crf, "-b:v", "0", "-pix_fmt", "yuv420p"];
			case 5: ["-c:v", "hevc_nvenc",
				"-preset", ["p1", "p2", "p4", "p6", "p7"][s.preset],
				"-rc", "vbr", "-cq", crf, "-b:v", "0", "-tag:v", "hvc1", "-pix_fmt", "yuv420p"];
			case 6: ["-c:v", "h264_amf",
				"-quality", ["speed", "speed", "balanced", "quality", "quality"][s.preset],
				"-rc", "cqp", "-qp_p", crf, "-qp_i", crf, "-pix_fmt", "yuv420p"];
			case 7: ["-c:v", "hevc_amf",
				"-quality", ["speed", "speed", "balanced", "quality", "quality"][s.preset],
				"-rc", "cqp", "-qp_p", crf, "-qp_i", crf, "-pix_fmt", "yuv420p"];
			case 8: ["-c:v", "av1_nvenc",
				"-preset", ["p1", "p2", "p4", "p6", "p7"][s.preset],
				"-rc", "vbr", "-cq", crf, "-b:v", "0", "-pix_fmt", "yuv420p"];
			case 9: ["-c:v", "av1_amf",
				"-quality", ["speed", "speed", "balanced", "quality", "quality"][s.preset],
				"-rc", "cqp", "-qp_p", crf, "-qp_i", crf, "-pix_fmt", "yuv420p"];
			default: ["-c:v", "libx264",
				"-preset", ["ultrafast", "veryfast", "fast", "medium", "slow"][s.preset],
				"-crf", crf, "-pix_fmt", "yuv420p"];
		}
	}

	public static function plannedPath(baseName:String):String
		return '$outputDir/${sanitize(baseName)}.${codecExt()}';

	public static function start(baseName:String, fps:Float):Bool {
		#if sys
		if (active) return false;

		lastError = null;
		lastResult = null;
		framesWritten = 0;
		broken = false;
		mismatchedFrames = 0;
		logTail = [];
		startedStamp = haxe.Timer.stamp();
		outputFps = fps;

		var window = FlxG.stage.window;
		if (window == null) return startFailed("There is no window to capture.");

		width = Std.int(window.width * window.scale);
		height = Std.int(window.height * window.scale);
		if (width <= 0 || height <= 0) return startFailed("The window has no size to capture.");

		frameSize = width * height * 4;
		pixels = new UInt8Array(frameSize);
		pixelBytes = pixels.buffer;

		try {
			if (!sys.FileSystem.exists(outputDir)) sys.FileSystem.createDirectory(outputDir);
		}
		catch (e:Dynamic) return startFailed('Could not create the $outputDir folder: $e');

		outputPath = uniquePath(sanitize(baseName));
		silentPath = outputPath.substr(0, outputPath.length - codecExt().length) + "video." + codecExt();

		var args = [
			"-y", "-hide_banner", "-loglevel", "error", "-nostats",
			"-f", "rawvideo", "-pix_fmt", "rgba",
			"-s", '${width}x${height}',
			"-r", Std.string(fps),
			"-i", "-",
			"-vf", "vflip,crop=trunc(iw/2)*2:trunc(ih/2)*2"
		].concat(codecArgs()).concat([silentPath]);

		try proc = new sys.io.Process("ffmpeg", args)
		catch (e:Dynamic) return startFailed('ffmpeg would not start ($e). Is it on PATH?');

		drain(proc.stderr, true);
		drain(proc.stdout, false);

		if (Main.framerateSprite != null) {
			framerateWasVisible = Main.framerateSprite.visible;
			Main.framerateSprite.visible = false;
		}

		@:privateAccess FlxG.stage.__forceRender = true;

		// capture at postDraw: the scene is fully rendered but dev overlays
		// (console, inspector, imgui windows) haven't drawn yet - they stay
		// on screen for the user without polluting the video.
		FlxG.signals.postDraw.add(captureFrame);
		hooked = true;
		active = true;

		log('--- start: $outputPath  ${width}x$height @ ${fps}fps ${codecLabel()}  window=${window.width}x${window.height} scale=${window.scale}'
			+ '  raw=${Math.round(frameSize / 1024 / 1024 * 10) / 10}MB/frame ---');
		return true;
		#else
		return startFailed("Video encoding needs a sys target.");
		#end
	}

	public static function stop(?audioAssets:Array<String>, audioSeekMs:Float = 0, audioDelayMs:Float = 0,
			expectedFrames:Int = 0):Void {
		#if sys
		if (!active) return;
		active = false;

		if (hooked) {
			FlxG.signals.postDraw.remove(captureFrame);
			@:privateAccess FlxG.stage.__forceRender = false;

			if (Main.framerateSprite != null) Main.framerateSprite.visible = framerateWasVisible;

			hooked = false;
		}

		if (expectedFrames > 0 && framesWritten != expectedFrames)
			log('WARN: simulated $expectedFrames frames but encoded $framesWritten', WARNING);

		var code = -1;
		if (proc != null) {
			try {
				proc.stdin.close();
				code = proc.exitCode();
			}
			catch (e:Dynamic) fail('ffmpeg did not shut down cleanly: $e');

			try proc.close() catch (e:Dynamic) {}
			proc = null;
		}

		pixels = null;
		pixelBytes = null;

		log('audio: seek=${audioSeekMs}ms delay=${audioDelayMs}ms tracks=${audioAssets == null ? 0 : audioAssets.length}');
		log('encoder closed: frames=$framesWritten expected=$expectedFrames ffmpegExit=$code');
		if (logTail.length > 0) log('ffmpeg said: ${logTail.join(" | ")}', code == 0 ? INFO : WARNING);

		var savedPath:String = null;
		var gifPath:String = null;
		if (framesWritten == 0) {
			fail("no frames reached the encoder");
			remove(silentPath);
		}
		else if (code != 0)
			fail('ffmpeg exited with code $code: ${logTail.join(" | ")}');
		else {
			savedPath = mux(audioAssets, audioSeekMs, audioDelayMs);
			if (savedPath != null && VideoRenderer.settings.gif)
				gifPath = makeGif(savedPath);
		}

		lastResult = {
			path: savedPath,
			frames: framesWritten,
			fps: outputFps,
			seconds: startedStamp > 0 ? haxe.Timer.stamp() - startedStamp : 0,
			gifPath: gifPath,
			error: lastError
		};
		#end
	}

	#if sys
	/** Two-pass palette GIF from the finished mp4; returns the gif path or null on failure. */
	static function makeGif(videoPath:String):Null<String> {
		var gifPath = videoPath.substr(0, videoPath.length - 4) + ".gif";
		var palPath = videoPath + ".pal.png";
		try {
			var p1 = new sys.io.Process("ffmpeg", ["-y", "-hide_banner", "-loglevel", "error", "-i", videoPath, "-vf", "palettegen", palPath]);
			var c1 = p1.exitCode();
			p1.close();
			if (c1 != 0) { remove(palPath); log('palettegen failed ($c1)', WARNING); return null; }
			var p2 = new sys.io.Process("ffmpeg", ["-y", "-hide_banner", "-loglevel", "error", "-i", videoPath, "-i", palPath,
				"-lavfi", 'fps=15,scale=trunc(iw/4)*2:-1:flags=lanczos[x];[x][1:v]paletteuse', gifPath]);
			var c2 = p2.exitCode();
			p2.close();
			remove(palPath);
			if (c2 == 0 && sys.FileSystem.exists(gifPath)) {
				log('GIF: $gifPath');
				return gifPath;
			}
			log('gif encode failed ($c2)', WARNING);
		}
		catch (e:Dynamic) {
			remove(palPath);
			log('gif encode failed: $e', WARNING);
		}
		return null;
	}
	#end

	#if sys
	static function shapeMatchesPipe():Bool {
		final win = FlxG.stage.window;
		if (win == null) return false;

		if (Std.int(win.width * win.scale) == width && Std.int(win.height * win.scale) == height) {
			if (mismatchedFrames > 0) {
				log('window back to ${width}x$height after $mismatchedFrames skipped frame(s) - resuming');
				mismatchedFrames = 0;
			}
			return true;
		}

		if (++mismatchedFrames == 1)
			log('window is ${Std.int(win.width * win.scale)}x${Std.int(win.height * win.scale)} but ffmpeg was told ${width}x$height'
				+ ' - skipping frames until it matches again', WARNING);

		VideoRenderer.applyOutputSize();

		if (mismatchedFrames > mismatchGraceFrames) {
			fail('the window stayed the wrong size for $mismatchedFrames frames; stopping before the video is corrupted');
			broken = true;
		}
		return false;
	}

	static function captureFrame():Void {
		if (!active || broken || proc == null) return;

		if (!shapeMatchesPipe()) return;

		if (!VideoRenderer.consumeFrame()) return;

		var gl = FlxG.stage.window.context.webgl;
		if (gl == null) return;

		gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, pixels);
		writeFrame();
	}

	static function writeFrame():Void {
		try {
			proc.stdin.writeFullBytes(pixelBytes, 0, frameSize);
			framesWritten++;
		}
		catch (e:Dynamic) {
			fail('ffmpeg stopped accepting frames: $e');
			broken = true;
		}
	}

	static function mux(audioAssets:Array<String>, seekMs:Float, delayMs:Float):String {
		var tracks = extractAudio(audioAssets);

		if (tracks.length == 0) {
			try sys.FileSystem.rename(silentPath, outputPath)
			catch (e:Dynamic) {
				fail('Could not rename the silent video: $e');
				return silentPath;
			}
			log('DONE: $framesWritten frames to $outputPath (no audio found)');
			return outputPath;
		}

		var seekSeconds = seekMs > 0 ? seekMs / 1000 : 0;
		var delay = delayMs > 0 ? Std.int(delayMs) : 0;

		var args = ["-y", "-hide_banner", "-loglevel", "error", "-i", silentPath];
		for (track in tracks) {
			if (seekSeconds > 0) {
				args.push("-ss");
				args.push(Std.string(seekSeconds));
			}
			args.push("-i");
			args.push(track);
		}

		var chains = [];
		var labels = [];
		for (i in 0...tracks.length) {
			var label = 'a$i';
			labels.push('[$label]');
			chains.push('[${i + 1}:a]' + (delay > 0 ? 'adelay=$delay:all=1' : 'anull') + '[$label]');
		}
		chains.push(labels.join("") + 'amix=inputs=${tracks.length}:normalize=0,apad[aout]');

		args = args.concat([
			"-filter_complex", chains.join(";"),
			"-map", "0:v:0", "-map", "[aout]",
			// webm can't hold aac - transcode to opus for it, keep aac for mp4/mov
			"-c:v", "copy",
			"-c:a", VideoRenderer.settings.codec == 2 ? "libopus" : "aac",
			"-b:a", "192k",
			"-shortest", outputPath
		]);

		var code = -1;
		try {
			var muxer = new sys.io.Process("ffmpeg", args);
			var err = readAll(muxer.stderr);
			code = muxer.exitCode();
			muxer.close();
			if (code != 0) logTail = err.split("\n");
		}
		catch (e:Dynamic) code = -1;

		for (track in tracks) remove(track);

		if (code != 0) {
			fail('Audio mux failed (code $code): ${logTail.join(" | ")}. The silent video is at $silentPath');
			return silentPath;
		}

		remove(silentPath);
		log('DONE: $framesWritten frames to $outputPath');
		return outputPath;
	}

	static function extractAudio(audioAssets:Array<String>):Array<String> {
		var tracks = [];
		if (audioAssets == null) return tracks;

		var seen = [];
		for (asset in audioAssets) {
			if (asset == null || seen.contains(asset) || !Assets.exists(asset)) continue;
			seen.push(asset);

			var ext = haxe.io.Path.extension(asset);
			var temp = '$outputDir/.render-audio-${tracks.length}.${ext == "" ? "ogg" : ext}';

			try {
				var bytes:haxe.io.Bytes = Assets.getBytes(asset);
				if (bytes == null || bytes.length == 0) continue;
				sys.io.File.saveBytes(temp, bytes);
				tracks.push(temp);
			}
			catch (e:Dynamic) log('WARN: could not extract $asset for muxing: $e', WARNING);
		}

		return tracks;
	}

	static function drain(input:haxe.io.Input, record:Bool):Void {
		sys.thread.Thread.create(() -> {
			try {
				while (true) {
					var line = input.readLine();
					if (line == null) break;
					if (!record) continue;

					logTail.push(line);
					if (logTail.length > 12) logTail.shift();
				}
			}
			catch (e:Dynamic) {}
		});
	}

	static function readAll(input:haxe.io.Input):String {
		var out = new StringBuf();
		try while (true) out.add(input.readLine() + "\n") catch (e:Dynamic) {}
		return out.toString();
	}

	static function remove(path:String):Void {
		if (path == null) return;
		try if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path) catch (e:Dynamic) {}
	}

	static function uniquePath(base:String):String {
		var ext = codecExt();
		var path = '$outputDir/$base.$ext';
		var n = 2;
		while (sys.FileSystem.exists(path)) {
			path = '$outputDir/$base ($n).$ext';
			n++;
		}
		return path;
	}
	#end

	static function sanitize(name:String):String {
		var out = new StringBuf();
		for (i in 0...name.length) {
			var c = name.charAt(i);
			out.add("<>:\"/\\|?*".indexOf(c) == -1 && name.charCodeAt(i) > 31 ? c : "_");
		}
		var clean = StringTools.trim(out.toString());
		return clean == "" ? "render" : clean;
	}

	static function fail(message:String):Bool {
		lastError = message;
		log('FAIL: $message', ERROR);
		return false;
	}

	static function startFailed(message:String):Bool {
		broken = true;
		lastResult = {path: null, frames: 0, fps: outputFps, seconds: 0, gifPath: null, error: message};
		return fail(message);
	}

	public static inline function note(message:String):Void
		log(message);

	static function log(message:String, level:Level = INFO):Void {
		Logs.trace('VideoEncoder: $message', level);

		#if sys
		try {
			if (!sys.FileSystem.exists(outputDir)) sys.FileSystem.createDirectory(outputDir);

			var stamp = DateTools.format(Date.now(), "%H:%M:%S");
			var out = sys.io.File.append('$outputDir/render-log.txt', false);
			out.writeString('[$stamp] $message\n');
			out.close();
		}
		catch (e:Dynamic) {}
		#end
	}
}

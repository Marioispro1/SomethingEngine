package funkin.backend.system;

import lime.utils.UInt8Array;

typedef VideoRenderResult = {
	var path:String;
	var frames:Int;
	var fps:Float;

	var seconds:Float;

	var error:String;
}

class VideoEncoder {
	public static inline var outputDir:String = "renders";

	static inline var capturePriority:Int = -10000;

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

	public static function plannedPath(baseName:String):String
		return '$outputDir/${sanitize(baseName)}.mp4';

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
		silentPath = outputPath.substr(0, outputPath.length - 4) + ".video.mp4";

		var args = [
			"-y", "-hide_banner", "-loglevel", "error", "-nostats",
			"-f", "rawvideo", "-pix_fmt", "rgba",
			"-s", '${width}x${height}',
			"-r", Std.string(fps),
			"-i", "-",
			"-vf", "vflip,crop=trunc(iw/2)*2:trunc(ih/2)*2",
			"-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
			"-pix_fmt", "yuv420p",
			silentPath
		];

		try proc = new sys.io.Process("ffmpeg", args)
		catch (e:Dynamic) return startFailed('ffmpeg would not start ($e). Is it on PATH?');

		drain(proc.stderr, true);
		drain(proc.stdout, false);

		if (Main.framerateSprite != null) {
			framerateWasVisible = Main.framerateSprite.visible;
			Main.framerateSprite.visible = false;
		}

		@:privateAccess FlxG.stage.__forceRender = true;

		window.onRender.add(captureFrame, false, capturePriority);
		hooked = true;
		active = true;

		log('--- start: $outputPath  ${width}x$height @ ${fps}fps  window=${window.width}x${window.height} scale=${window.scale}'
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
			var window = FlxG.stage.window;
			if (window != null) window.onRender.remove(captureFrame);
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
		if (framesWritten == 0) {
			fail("no frames reached the encoder");
			remove(silentPath);
		}
		else if (code != 0)
			fail('ffmpeg exited with code $code: ${logTail.join(" | ")}');
		else
			savedPath = mux(audioAssets, audioSeekMs, audioDelayMs);

		lastResult = {
			path: savedPath,
			frames: framesWritten,
			fps: outputFps,
			seconds: startedStamp > 0 ? haxe.Timer.stamp() - startedStamp : 0,
			error: lastError
		};
		#end
	}

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

	static function captureFrame(context:lime.graphics.RenderContext):Void {
		if (!active || broken || proc == null) return;

		if (!shapeMatchesPipe()) return;

		if (!VideoRenderer.consumeFrame()) return;

		var gl = context.webgl;
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
			"-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
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
		var path = '$outputDir/$base.mp4';
		var n = 2;
		while (sys.FileSystem.exists(path)) {
			path = '$outputDir/$base ($n).mp4';
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
		lastResult = {path: null, frames: 0, fps: outputFps, seconds: 0, error: message};
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

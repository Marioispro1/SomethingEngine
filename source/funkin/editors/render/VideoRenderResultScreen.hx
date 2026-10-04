package funkin.editors.render;

import funkin.backend.system.VideoEncoder;
import funkin.backend.system.VideoRenderer;

class VideoRenderResultScreen extends UISubstateWindow {
	var result:VideoRenderResult;

	public var openButton:UIButton;
	public var closeButton:UIButton;

	public function new(result:VideoRenderResult) {
		super();
		this.result = result;
	}

	public override function create() {
		var failed = result.error != null;
		var partial = failed && result.path != null;
		var lost = failed && !partial;

		winTitle = TU.translate(lost ? "videoRenderResult.titleFailed"
			: partial ? "videoRenderResult.titleIncomplete" : "videoRenderResult.title");
		winWidth = 620;
		winHeight = partial ? 360 : 300;

		super.create();

		var left = windowSpr.x + 24;

		var heading = new UIText(left, windowSpr.y + 30 + 16, windowSpr.bWidth - 48,
			lost ? TU.translate("videoRenderResult.failed") : fileName(), 22,
			lost ? 0xFFFF6666 : partial ? 0xFFFFAA55 : 0xFF88CC88);
		add(heading);

		var body = new UIText(left, heading.y + heading.height + 14, windowSpr.bWidth - 48,
			lost ? result.error : summary() + (partial ? '\n\n' + result.error : ""), 15, 0xFFDDDDDD);
		add(body);

		closeButton = new UIButton(windowSpr.x + windowSpr.bWidth - 24 - 140, windowSpr.y + windowSpr.bHeight - 16 - 32,
			TU.translate("editor.close"), close, 140);
		add(closeButton);

		openButton = new UIButton(closeButton.x - 20 - 170, closeButton.y,
			TU.translate("videoRenderResult.openFolder"), openFolder, 170);
		add(openButton);

		openButton.selectable = !lost;
		openButton.alpha = openButton.field.alpha = openButton.selectable ? 1 : 0.4;

		var copyButton = new UIButton(openButton.x - 16 - 130, closeButton.y, "Copy path", copyPath, 130);
		copyButton.selectable = result.path != null;
		copyButton.alpha = copyButton.field.alpha = copyButton.selectable ? 1 : 0.4;
		add(copyButton);

		if (!lost) {
			try FlxG.sound.play(Paths.sound(Assets.exists(Paths.sound("confirmMenu")) ? "confirmMenu" : "freakyMenu")) catch (e:Dynamic) {}
		}
	}

	function copyPath() {
		try {
			openfl.desktop.Clipboard.generalClipboard.setData(openfl.desktop.ClipboardFormats.TEXT_FORMAT,
				#if sys sys.FileSystem.absolutePath(result.path) #else result.path #end);
		}
		catch (e:Dynamic) {}
	}

	function openFolder() {
		#if sys
		try {
			var full = sys.FileSystem.absolutePath(VideoEncoder.outputDir);
			CoolUtil.browsePath(full);
		}
		catch (e:Dynamic) {}
		#end
	}

	inline function fileName():String
		return result.path == null ? "?" : haxe.io.Path.withoutDirectory(result.path);

	function summary():String {
		var length = result.fps > 0 ? result.frames / result.fps : 0;

		var size = "";
		#if sys
		try {
			if (result.path != null && sys.FileSystem.exists(result.path)) {
				var mb = sys.FileSystem.stat(result.path).size / (1024 * 1024);
				size = '   -   ${Math.round(mb * 10) / 10} MB';
			}
		}
		catch (e:Dynamic) {}
		#end

		return 'in ${VideoEncoder.outputDir}/\n\n'
			+ '${result.frames} frames at ${result.fps} fps   -   ${VideoRenderer.formatTime(length * 1000)} long$size\n'
			+ 'took ${VideoRenderer.formatTime(result.seconds * 1000)}'
			+ (result.gifPath != null ? '\n+ GIF: ${haxe.io.Path.withoutDirectory(result.gifPath)}' : "");
	}
}

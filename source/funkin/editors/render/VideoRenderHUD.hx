package funkin.editors.render;

import flixel.group.FlxSpriteGroup;
import funkin.backend.FunkinText;
import funkin.backend.system.VideoEncoder;
import funkin.backend.system.VideoRenderer;
import funkin.backend.utils.WindowUtils;

class VideoRenderHUD extends FlxSpriteGroup {
	static inline var barHeight:Int = 6;
	static inline var panelHeight:Int = 112;

	static inline var refreshInterval:Float = 0.25;

	public var hudCamera:FlxCamera;

	var titleText:FunkinText;
	var pathText:FunkinText;
	var statsText:FunkinText;
	var rateText:FunkinText;
	var bar:FlxSprite;

	var nextRefresh:Float = 0;

	public function new(songName:String, difficulty:String) {
		super();

		buildPanel(songName, difficulty);
		refresh();
	}

	function buildPanel(songName:String, difficulty:String) {
		hudCamera = new FlxCamera();
		hudCamera.bgColor = 0;
		FlxG.cameras.add(hudCamera, false);
		cameras = [hudCamera];

		var top = FlxG.height - panelHeight;

		var panel = new FlxSprite(0, top).makeGraphic(1, 1, 0xFF000000);
		panel.scale.set(FlxG.width, panelHeight);
		panel.updateHitbox();
		panel.setPosition(0, top);
		panel.alpha = 0.72;
		add(panel);

		titleText = new FunkinText(24, top + 8, FlxG.width - 48,
			(VideoEncoder.active ? 'RENDERING   ' : 'PREVIEWING RENDER   ') + '$songName  [$difficulty]', 20);
		titleText.color = VideoEncoder.active ? 0xFFFF5555 : 0xFFFFAA55;
		add(titleText);

		pathText = new FunkinText(24, top + 34, FlxG.width - 48, "", 14);
		add(pathText);

		statsText = new FunkinText(24, top + 56, FlxG.width - 48, "", 18);
		add(statsText);

		rateText = new FunkinText(24, top + 82, FlxG.width - 48, "", 15);
		rateText.color = 0xFFBBBBBB;
		add(rateText);

		var barBG = new FlxSprite(0, FlxG.height - barHeight).makeGraphic(1, 1, 0xFF1A1A1A);
		barBG.scale.set(FlxG.width, barHeight);
		barBG.updateHitbox();
		barBG.setPosition(0, FlxG.height - barHeight);
		add(barBG);

		bar = new FlxSprite(0, FlxG.height - barHeight).makeGraphic(1, 1, 0xFF3FA9F5);
		bar.scale.set(0, barHeight);
		bar.origin.set(0, 0);
		add(bar);

		for (member in members) if (member != null) member.scrollFactor.set();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		var now = haxe.Timer.stamp();
		if (now >= nextRefresh) {
			nextRefresh = now + refreshInterval;
			refresh();
		}
	}

	function refresh() {
		hudCamera.visible = !VideoEncoder.active;

		var total = VideoRenderer.totalFrames;
		var progress = VideoRenderer.progress;
		var eta = VideoRenderer.eta;
		var percent = total > 0 ? '${Math.round(progress * 100)}%' : "?%";
		var etaText = eta < 0 ? "--:--" : VideoRenderer.formatTime(eta * 1000);

		WindowUtils.prefix = '[RENDERING $percent - eta $etaText] ';

		if (VideoEncoder.lastError != null) {
			pathText.text = 'PROBLEM: ${VideoEncoder.lastError}';
			pathText.color = 0xFFFF6666;
		}
		else if (VideoEncoder.active) {
			pathText.text = '-> ${VideoEncoder.outputPath}';
			pathText.color = 0xFF88CC88;
		}
		else {
			pathText.text = "NOT ENCODING";
			pathText.color = 0xFFFFAA55;
		}

		bar.scale.x = FlxG.width * progress;

		statsText.text = 'frame ${VideoRenderer.frameIndex} / ${total > 0 ? Std.string(total) : "?"}'
			+ ' - ${VideoRenderer.formatTime(VideoRenderer.songTime)} / ${VideoRenderer.formatTime(VideoRenderer.endMs)}'
			+ ' - $percent';

		rateText.text = 'elapsed ${VideoRenderer.formatTime(VideoRenderer.elapsed * 1000)}'
			+ ' - eta $etaText'
			+ ' - ${Math.round(VideoRenderer.realFps * 10) / 10} frames/sec'
			+ (VideoEncoder.active ? ' - encoded ${VideoEncoder.framesWritten}' : "")
			+ ' - ESC to stop';
	}

	override function destroy() {
		super.destroy();

		WindowUtils.resetAffixes();

		if (hudCamera != null) {
			if (FlxG.cameras.list.contains(hudCamera)) FlxG.cameras.remove(hudCamera);
			hudCamera = null;
		}
	}
}

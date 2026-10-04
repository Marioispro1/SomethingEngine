package funkin.editors.render;

import funkin.backend.chart.Chart;
import funkin.backend.system.VideoEncoder;
import funkin.backend.system.VideoRenderer;
import funkin.backend.system.VideoRenderer.RenderResolution;

typedef QueuedRender = {
	var song:String;
	var diff:String;
	var variant:String;
	var fps:Float;
	var startMs:Float;
	var endMs:Float;
	var countdown:Bool;
	var botplay:Bool;
	var uncapped:Bool;
	var width:Int;
	var height:Int;
	var gif:Bool;
	var useReplay:Bool;
};

class VideoRenderSettingsScreen extends UISubstateWindow {
	public static var renderQueue:Array<QueuedRender> = [];
	public var songName:String;
	public var difficulty:String;
	public var variant:String;

	var fpsStepper:UINumericStepper;
	var resDropDown:UIDropDown;
	var startStepper:UINumericStepper;
	var endStepper:UINumericStepper;
	var countdownCheckbox:UICheckbox;
	var botplayCheckbox:UICheckbox;
	var uncappedCheckbox:UICheckbox;
	var gifCheckbox:UICheckbox;
	var replayCheckbox:UICheckbox;
	var queueText:UIText;
	var problemText:UIText;
	var outputText:UIText;
	var renderButton:UIButton;
	var closeButton:UIButton;

	public function new(songName:String, difficulty:String, ?variant:String) {
		super();
		this.songName = songName;
		this.difficulty = difficulty;
		this.variant = variant;
	}

	inline function t(id:String, ?args:Array<Dynamic>):String
		return TU.translate('videoRender.$id', args);

	public override function create() {
		winTitle = t("title");
		winWidth = 620;
		winHeight = 600;

		super.create();

		function addLabelOn(ui:FlxSprite, text:String)
			add(new UIText(ui.x, ui.y - 22, 0, text));

		var s = VideoRenderer.settings;
		var left = windowSpr.x + 24;
		var right = windowSpr.x + windowSpr.bWidth - 24;

		var bpm:Float = 0;
		var endMs:Float = 0;
		try {
			var data = Chart.parse(songName, difficulty, variant);
			bpm = data.meta.bpm.getDefault(0);
			if (data.strumLines != null)
				for (line in data.strumLines)
					if (line.notes != null)
						for (n in line.notes)
							if (n.time + n.sLen > endMs) endMs = n.time + n.sLen;
		}
		catch (e:Dynamic) {}

		add(new UIText(left, windowSpr.y + 30 + 12, windowSpr.bWidth - 48,
			t("details", [bpm, VideoRenderer.formatTime(endMs)]), 16));

		var colY = windowSpr.y + 30 + 12 + 54;

		fpsStepper = new UINumericStepper(left, colY, s.fps, 1, 0, 1, 1000, 120);
		add(fpsStepper);
		addLabelOn(fpsStepper, t("fps"));

		var maxRes = VideoRenderer.maxOutputSize();
		resDropDown = new UIDropDown(fpsStepper.x + fpsStepper.bWidth + 60, colY, 320, 32,
			[for (r in VideoRenderer.resolutionOptions()) {label: r.name, value: r}]);
		add(resDropDown);
		addLabelOn(resDropDown, t("resolution") + ' (' + t("resolutionHint", [maxRes.width, maxRes.height]) + ')');

		colY += 74;
		startStepper = new UINumericStepper(left, colY, s.startMs / 1000, 0.1, 2, 0, null, 120);
		add(startStepper);
		addLabelOn(startStepper, t("start"));

		endStepper = new UINumericStepper(startStepper.x + startStepper.bWidth + 60, colY, s.endMs / 1000, 0.1, 2, 0, null, 120);
		add(endStepper);
		addLabelOn(endStepper, t("end") + ' (' + t("endHint") + ')');

		colY += 74;
		countdownCheckbox = new UICheckbox(left, colY, t("countdown"), s.includeCountdown, 0, true);
		add(countdownCheckbox);
		botplayCheckbox = new UICheckbox(left + 290, colY, t("botplay"), s.botplay, 0, true);
		add(botplayCheckbox);

		colY += 28;
		uncappedCheckbox = new UICheckbox(left, colY, t("uncapped"), s.uncapped, 0, true);
		add(uncappedCheckbox);
		gifCheckbox = new UICheckbox(left + 290, colY, "Also export GIF", false, 0, true);
		add(gifCheckbox);

		colY += 28;
		replayCheckbox = new UICheckbox(left, colY, "Use recorded inputs (exports/replay.fgr)", false, 0, true);
		add(replayCheckbox);

		colY += 34;
		var explainer = new UIText(left, colY, windowSpr.bWidth - 48, t("explainer"), 13, 0xFFBBBBBB);
		add(explainer);

		colY += explainer.height + 12;
		outputText = new UIText(left, colY, windowSpr.bWidth - 48,
			t("output", [VideoEncoder.plannedPath(songName)]), 13, 0xFF888888);
		add(outputText);

		colY += outputText.height + 10;
		problemText = new UIText(left, colY, windowSpr.bWidth - 48, "", 14, 0xFFFF6666);
		add(problemText);

		closeButton = new UIButton(right - 125, windowSpr.y + windowSpr.bHeight - 16 - 32, TU.translate("editor.close"), close, 125);
		add(closeButton);

		renderButton = new UIButton(closeButton.x - 20 - 140, closeButton.y, t("render"), startRender, 140);
		add(renderButton);

		var queueButton = new UIButton(renderButton.x - 12 - 140, closeButton.y, "Queue", queueCurrent, 140);
		add(queueButton);
		queueText = new UIText(left, closeButton.y + 6, 300,
			renderQueue.length > 0 ? '${renderQueue.length} render(s) queued - starts after this one' : "", 13, 0xFFAAAAAA);
		add(queueText);
	}

	function captureConfig():QueuedRender {
		var res:RenderResolution = cast resDropDown.value;
		return {
			song: songName, diff: difficulty, variant: variant,
			fps: fpsStepper.value,
			startMs: startStepper.value * 1000,
			endMs: endStepper.value * 1000,
			countdown: countdownCheckbox.checked,
			botplay: botplayCheckbox.checked,
			uncapped: uncappedCheckbox.checked,
			width: res != null ? res.width : 0,
			height: res != null ? res.height : 0,
			gif: gifCheckbox.checked,
			useReplay: replayCheckbox.checked
		};
	}

	function queueCurrent() {
		UIUtil.confirmUISelections(this);
		renderQueue.push(captureConfig());
		queueText.text = '${renderQueue.length} render(s) queued - starts after this one';
	}

	/** Starts a queued render: applies its settings, optionally loads the recorded inputs, then plays the song. */
	public static function launch(item:QueuedRender) {
		var s = VideoRenderer.settings;
		s.fps = item.fps;
		s.startMs = item.startMs;
		s.endMs = item.endMs;
		s.includeCountdown = item.countdown;
		s.botplay = item.botplay;
		s.uncapped = item.uncapped;
		s.encode = VideoEncoder.available();
		s.width = item.width;
		s.height = item.height;
		s.gif = item.gif;
		VideoRenderer.applyOutputSize();

		VideoRenderer.replayPending = null;
		#if (sys && FLX_RECORD)
		if (item.useReplay) {
			try {
				var p = 'exports/replay.fgr';
				if (sys.FileSystem.exists(p)) VideoRenderer.replayPending = sys.io.File.getContent(p);
			}
			catch (e:Dynamic) Logs.error('Could not read replay file: $e');
		}
		#end

		VideoRenderer.requested = true;
		PlayState.loadSong(item.song, item.diff, item.variant);
		MusicBeatState.skipTransIn = MusicBeatState.skipTransOut = true;
		FlxG.switchState(new PlayState());
	}

	public static function launchNextQueued() {
		var item = renderQueue.shift();
		if (item != null) launch(item);
	}

	public override function update(elapsed:Float) {
		var problem = "";
		if (fpsStepper.value <= 0) problem = t("problems.fps");
		else if (endStepper.value > 0 && endStepper.value <= startStepper.value) problem = t("problems.range");
		else if (!VideoEncoder.available()) problem = t("problems.ffmpeg");

		if (problemText.text != problem) problemText.text = problem;
		renderButton.selectable = problem == "";
		renderButton.alpha = renderButton.field.alpha = problem == "" ? 1 : 0.4;

		super.update(elapsed);
	}

	function startRender() {
		UIUtil.confirmUISelections(this);
		launch(captureConfig());
	}
}

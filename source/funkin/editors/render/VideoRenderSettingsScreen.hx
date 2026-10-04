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
	var codec:Int;
	var crf:Float;
	var preset:Int;
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
	var codecDropDown:UIDropDown;
	var presetDropDown:UIDropDown;
	var crfStepper:UINumericStepper;
	var queueText:UIText;
	var estText:UIText;
	var clearQueueButton:UIButton;
	var songLenMs:Float = 0;
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
		winHeight = 680;

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
		songLenMs = endMs;

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
		var rec = VideoEncoder.recommendedCodec();
		if (s.codec == 0 && rec != 0) s.codec = rec;
		var codecOptions:Array<funkin.editors.ui.UIDropDown.DropDownItem> = [
			{label: "H.264 (mp4)", value: 0},
			{label: "H.265 (mp4)", value: 1},
			{label: "VP9 (webm)", value: 2},
			{label: "ProRes (mov)", value: 3},
			{label: "H.264 NVENC", value: 4},
			{label: "H.265 NVENC", value: 5},
			{label: "H.264 AMF", value: 6},
			{label: "H.265 AMF", value: 7},
			{label: "AV1 NVENC", value: 8},
			{label: "AV1 AMF", value: 9}
		];
		for (o in codecOptions) if (o.value == rec) o.label += " (Recommended)";
		codecDropDown = new UIDropDown(left, colY, 180, 32, codecOptions, s.codec);
		add(codecDropDown);
		var gpu = VideoEncoder.gpuName();
		addLabelOn(codecDropDown, "Codec" + (gpu != "" ? ' - $gpu' : ""));

		presetDropDown = new UIDropDown(codecDropDown.x + 196, colY, 170, 32, [
			{label: "Fastest", value: 0},
			{label: "Fast", value: 1},
			{label: "Balanced", value: 2},
			{label: "Quality", value: 3},
			{label: "Best", value: 4}
		], s.preset);
		add(presetDropDown);
		addLabelOn(presetDropDown, "Preset");

		crfStepper = new UINumericStepper(presetDropDown.x + 186, colY, s.crf, 1, 0, 0, 51, 80);
		add(crfStepper);
		addLabelOn(crfStepper, "CRF (lower = better)");

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

		colY += outputText.height + 4;
		estText = new UIText(left, colY, windowSpr.bWidth - 48, "", 13, 0xFF88AACC);
		add(estText);

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
		clearQueueButton = new UIButton(queueButton.x - 12 - 80, closeButton.y, "Clear", () -> renderQueue = [], 80);
		clearQueueButton.selectable = false;
		add(clearQueueButton);

		var mixButton = new UIButton(left, closeButton.y - 44, "Export audio mix", exportMix, 170);
		add(mixButton);
		var allButton = new UIButton(mixButton.x + 182, closeButton.y - 44, "Queue all songs", queueAll, 170);
		add(allButton);
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
			useReplay: replayCheckbox.checked,
			codec: codecDropDown.value,
			crf: crfStepper.value,
			preset: presetDropDown.value
		};
	}

	function queueCurrent() {
		UIUtil.confirmUISelections(this);
		renderQueue.push(captureConfig());
	}

	/** Queues one render per song in the freeplay list (first difficulty each) with the current settings. */
	function queueAll() {
		UIUtil.confirmUISelections(this);
		try {
			var songs = funkin.menus.FreeplayState.FreeplaySonglist.get(false, 'songs/', false).songs;
			var n = 0;
			for (s in songs) {
				if (s.name == null || s.name.endsWith("/")) continue;
				var cfg = captureConfig();
				cfg.song = s.name;
				cfg.diff = (s.difficulties != null && s.difficulties.length > 0) ? s.difficulties[0] : difficulty;
				renderQueue.push(cfg);
				n++;
			}
			Logs.trace('queued $n song renders');
		}
		catch (e:Dynamic) Logs.error('queue all failed: $e');
	}

	/** Mixes inst+voices to a single mp3 in renders/ - reuses the encoder's extraction pipeline, no video needed. */
	function exportMix() {
		var tracks:Array<String>;
		try {
			var data = Chart.parse(songName, difficulty, variant);
			tracks = [Paths.inst(data.meta.name, difficulty, data.meta.instSuffix)];
			if (data.meta.needsVoices)
				tracks.push(Paths.voices(data.meta.name, difficulty, data.meta.vocalsSuffix));
			if (data.strumLines != null)
				for (line in data.strumLines)
					if (line.vocalsSuffix != null && line.vocalsSuffix != "")
						tracks.push(Paths.voices(data.meta.name, difficulty, line.vocalsSuffix));
		}
		catch (e:Dynamic) {
			tracks = [Paths.inst(songName, difficulty)];
		}
		VideoEncoder.exportAudioMix(tracks, '$songName - $difficulty mix');
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
		s.codec = item.codec;
		s.crf = item.crf;
		s.preset = item.preset;
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

		// live estimate of the work the render will do
		var spanMs = (endStepper.value > 0 ? endStepper.value * 1000 : songLenMs) - startStepper.value * 1000;
		var frames = Math.max(0, Math.ceil(spanMs / 1000 * fpsStepper.value));
		var est = 'â‰ˆ $frames frames'
			+ (VideoEncoder.available() && VideoRenderer.realFps > 0 ? '  -  ~${VideoRenderer.formatTime(frames / VideoRenderer.realFps * 1000)} at last speed' : "");
		if (estText.text != est) estText.text = est;

		// queue state
		var hasQueue = renderQueue.length > 0;
		clearQueueButton.selectable = hasQueue;
		clearQueueButton.alpha = clearQueueButton.field.alpha = hasQueue ? 1 : 0.4;
		var qText = hasQueue ? '${renderQueue.length} render(s) queued - starts after this one' : "";
		if (queueText.text != qText) queueText.text = qText;

		super.update(elapsed);
	}

	function startRender() {
		UIUtil.confirmUISelections(this);
		launch(captureConfig());
	}
}

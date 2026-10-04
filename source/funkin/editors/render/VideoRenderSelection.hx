package funkin.editors.render;

import flixel.util.FlxColor;
import funkin.backend.chart.ChartData;
import funkin.backend.system.VideoEncoder;
import funkin.editors.EditorTreeMenu;
import funkin.menus.FreeplayState.FreeplaySonglist;
import funkin.options.type.*;

using StringTools;

class VideoRenderSelection extends EditorTreeMenu {
	var queueArmed:Bool = false;

	override function create() {
		super.create();
		DiscordUtil.call("onEditorTreeLoaded", ["Video Renderer"]);
		addMenu(new VideoRenderSelectionScreen());
	}

	override function createPost() {
		super.createPost();

		var res = VideoEncoder.lastResult;
		if (res != null) {
			VideoEncoder.lastResult = null;
			openSubState(new VideoRenderResultScreen(res));
		}
		queueArmed = VideoRenderSettingsScreen.renderQueue.length > 0;
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		// continue the render queue once the result screen has been dismissed
		if (queueArmed && subState == null) {
			queueArmed = false;
			VideoRenderSettingsScreen.launchNextQueued();
		}
	}
}

class VideoRenderSelectionScreen extends EditorTreeMenuScreen {
	public var freeplayList:FreeplaySonglist;

	inline function makeChartOption(s:ChartMetaData, d:String):TextOption {
		var isVariant = s.variant != null && s.variant != '';
		return new TextOption(d, getID('acceptDifficulty'),
			() -> parent.openSubState(new VideoRenderSettingsScreen(s.name, d, isVariant ? s.variant : null)));
	}

	inline function makeVariationOption(s:ChartMetaData):TextOption {
		return new TextOption(s.variant, getID('acceptVariation'), " >", () -> openSongOption(s, false));
	}

	public function openSongOption(s:ChartMetaData, first = true) {
		var isVariant = s.variant != null && s.variant != '';
		var screen = new EditorTreeMenuScreen((first || !isVariant) ? (~/(.*[\/])/g.map(s.name, _->'') + (isVariant ? ' (${s.variant})' : '')) : s.variant, getID('selectDifficulty'));

		for (d in s.difficulties) if (d != '') screen.add(makeChartOption(s, d));
		if (s.difficulties.length > 0 && s.variants.length > 0) screen.add(new Separator());
		for (v in s.variants) if (s.metas.get(v) != null) screen.add(makeVariationOption(s.metas.get(v)));

		parent.addMenu(screen);
	}

	public function makeSongOption(s:ChartMetaData):IconOption {
		var opt = new IconOption(~/(.*[\/])/g.map(s.name, _->''), getID('acceptSong'), s.icon, () -> openSongOption(s, true));
		opt.suffix = " >";
		opt.editorFlashColor = s.color.getDefault(FlxColor.WHITE);

		return opt;
	}

	public function new() {
		super('editor.render.name', 'videoRenderSelection.desc', 'videoRenderSelection.');
		freeplayList = FreeplaySonglist.get(false, 'songs/', false);

		function generateList(modsList:Array<ChartMetaData>, folderPath:String = ""):Array<FlxSprite> {
			var list:Array<FlxSprite> = [];

			for (char in modsList) {
				if (char.name.endsWith("/")) {
					var folderName = CoolUtil.getFilename(char.name.substr(0, char.name.length-1));

					list.push(new FolderOption(folderName + ' >', getID('acceptFolder'), () -> {
						var newModsList = FreeplaySonglist.get(false, 'songs/' + folderPath + folderName + '/', false).songs;
						var newList:Array<FlxSprite> = generateList(newModsList, folderPath + folderName + "/");
						parent.addMenu(new EditorTreeMenuScreen(folderName, translate('desc-folder', [folderPath + folderName + "/"]), newList));
					}));
				}
				else {
					list.push(makeSongOption(char));
				}
			}

			return list;
		}

		for (o in generateList(freeplayList.songs)) add(o);
	}
}

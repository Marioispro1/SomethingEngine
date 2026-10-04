package funkin.backend.system;

import funkin.backend.assets.ModsFolder;
import funkin.backend.assets.ModsFolderLibrary;
import funkin.backend.assets.Paths;
import flixel.group.FlxGroup;
import openfl.utils.Assets;

#if sys
import sys.FileSystem;
import sys.thread.Thread;
#end

/**
 * Watches asset folders for file changes while dev mode is on and hot-reloads them:
 * images get refreshed inside their existing FlxGraphic so every sprite using it updates
 * instantly (no state reset needed), and .hx files under assets/data reload state scripts.
 */
class AssetWatcher {
	public static var enabled:Bool = true;

	#if sys
	// worker thread owns this map - main thread never touches it
	static var mtimes:Map<String, Float> = new Map();
	static var inited:Bool = false;
	static var elapsed:Float = 0;
	static var changedInTick:Bool = false;
	static final INTERVAL:Float = 0.75;

	static var mainThread:Thread = null;
	static var scanRunning:Bool = false;

	public static function init() {
		if (inited) return;
		inited = true;
		mainThread = Thread.current();
		FlxG.signals.preUpdate.add(update);
		scanRunning = true;
		Thread.create(workerScan);
	}

	static function update():Void {
		if (!enabled || !Options.devMode) return;

		// apply whatever the worker thread finished scanning since last frame
		var msg:Dynamic = Thread.readMessage(false);
		while (msg != null) {
			scanRunning = false;
			for (c in (msg : Array<Dynamic>)) onChanged(c.path, c.id);
			msg = Thread.readMessage(false);
		}
		if (changedInTick) {
			Paths.assetsTree.resetAssetPathCache();
			Paths.tempFramesCache.clear();
			changedInTick = false;
		}

		elapsed += FlxG.elapsed;
		if (elapsed >= INTERVAL && !scanRunning) {
			elapsed = 0;
			scanRunning = true;
			Thread.create(workerScan);
		}
	}

	static inline function normDir(dir:String) {
		while (dir.endsWith("/")) dir = dir.substr(0, dir.length - 1);
		return dir;
	}

	/** Asset ids look like `assets/<path>` for both source and mod libraries. */
	static inline function assetId(dir:String, prefix:String, fullPath:String):String {
		return prefix + fullPath.substr(dir.length + 1);
	}

	static function collect(?out:Map<String, String>) {
		if (out == null) out = [];
		// base assets
		_collect(normDir(Paths.assetsTree.rootDirectory), 'assets/', out);
		#if MOD_SUPPORT
		// folder-based mod libraries (zips can't change on disk)
		for (l in ModsFolder.getLoadedModsLibs()) {
			var ml:ModsFolderLibrary = (l is ModsFolderLibrary) ? cast l : null;
			if (ml != null) _collect(normDir(ml.basePath), ml.prefix, out);
		}
		#end
		return out;
	}

	static function _collect(dir:String, prefix:String, out:Map<String, String>) {
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return;
		for (f in FileSystem.readDirectory(dir)) {
			var path = '$dir/$f';
			if (FileSystem.isDirectory(path)) {
				_collect(path, prefix, out);
			} else {
				out.set(path, assetId(dir, prefix, path));
				if (!mtimes.exists(path)) mtimes.set(path, FileSystem.stat(path).mtime.getTime());
			}
		}
	}

	/** Runs on a worker thread: walks every watched dir and stats each file. Sends back only the changed list. */
	static function workerScan() {
		var changes:Array<{path:String, id:String}> = [];
		try {
			var out = collect();
			for (path => id in out) {
				var mtime = FileSystem.stat(path).mtime.getTime();
				var old = mtimes.get(path);
				if (old != null && old != mtime) {
					mtimes.set(path, mtime);
					changes.push({path: path, id: id});
				}
			}
		}
		catch (e:Dynamic) {}
		mainThread.sendMessage(changes);
	}

	static function onChanged(path:String, id:String) {
		changedInTick = true;
		var ext = id.substr(id.lastIndexOf('.') + 1).toLowerCase();
		switch (ext) {
			case 'png', 'jpg', 'jpeg', 'webp':
				Assets.cache.removeBitmapData(id);
				var g = FlxG.bitmap.get(id);
				if (g != null) {
					g.refresh();
					Logs.trace('AssetWatcher: reloaded image $id', VERBOSE);
				}
			case 'hx':
				if (id.startsWith('assets/data/')) {
					var st = FlxG.state;
					while (st != null) {
						if (st is MusicBeatState) {
							(cast st : MusicBeatState).stateScripts.reload();
							break;
						}
						st = st.subState;
					}
					Logs.trace('AssetWatcher: reloaded scripts ($id)', VERBOSE);
				}
			case 'frag', 'vert', 'glsl':
				reloadLiveShaders(id);
			case 'ogg', 'wav', 'mp3':
				Assets.cache.removeSound(id);
			case 'ttf', 'otf':
				Assets.cache.removeFont(id);
			default:
		}
	}

	/**
	 * Re-reads a changed shader file and recompiles every live FunkinShader
	 * loaded from it (marking the source dirty recompiles on next draw).
	 */
	static function reloadLiveShaders(id:String) {
		var found = 0;
		function checkShader(s:Dynamic) {
			var fs:funkin.backend.shaders.FunkinShader = (s is funkin.backend.shaders.FunkinShader) ? cast s : null;
			if (fs != null) {
				@:privateAccess
				if (fs._fragmentFilePath == id || fs._vertexFilePath == id) {
					@:privateAccess fs._fromFile(fs._fragmentFilePath, fs._vertexFilePath, fs.glVersion);
					found++;
				}
			}
		}
		function visit(b:FlxBasic) {
			if (b is FlxGroup) {
				for (m in (cast b : FlxGroup).members) if (m != null) visit(m);
			} else if (b is FlxSprite) {
				checkShader((cast b : FlxSprite).shader);
			}
		}
		var st = FlxG.state;
		while (st != null) {
			if (st.members != null) for (m in st.members) if (m != null) visit(m);
			st = st.subState;
		}
		if (found > 0) Logs.trace('AssetWatcher: reloaded $found live shader(s) from $id', VERBOSE);
	}
	#end
}

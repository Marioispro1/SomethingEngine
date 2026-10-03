package funkin.backend.shaders;

import openfl.Lib;

/**
 * Compiles shader GL programs ahead of time so they don't hitch the game the
 * first time a shader is drawn.
 *
 * Programs are cached inside the GL context keyed by their sources, so warming
 * a shader once also makes every instance of the same shader created later
 * (including ones made by scripts with `FunkinShader.fromFile`) cheap to use.
 */
@:access(openfl.display.Shader)
class ShaderPreload {

	/** Shader instances warmed through `preload`/`get`, keyed by name. */
	public static var cache:Map<String, FunkinShader> = [];

	/**
	 * Returns a warmed `FunkinShader` for `shaders/<name>` (shared instance).
	 * Use `create` if you need a unique instance with its own uniforms.
	 */
	public static function get(name:String, ?library:String):FunkinShader {
		var s = cache.get(name);
		if (s == null) s = preload(name, library);
		return s;
	}

	/**
	 * Creates and warms a shader for `shaders/<name>`, caching the instance.
	 * Returns null if no shader source exists under that name.
	 */
	public static function preload(name:String, ?library:String):FunkinShader {
		var s = create(name, library);
		if (s != null) cache.set(name, s);
		return s;
	}

	/**
	 * Creates a fresh warmed `FunkinShader` for `shaders/<name>` without caching it.
	 * Supports `.frag`/`.vert` pairs as well as lone `.glsl` fragment sources.
	 * Returns null if no shader source exists under that name.
	 */
	public static function create(name:String, ?library:String):FunkinShader {
		var frag = Paths.fragShader(name, library);
		var vert = Paths.vertShader(name, library);
		if (!Assets.exists(frag) && !Assets.exists(vert)) {
			var glsl = Paths.getPath('shaders/$name.glsl', library);
			if (!Assets.exists(glsl)) return null;
			frag = glsl;
			vert = null;
		}
		var s = FunkinShader.fromFile(frag, vert);
		warm(s);
		return s;
	}

	/** True when a GL context exists and shaders can actually be compiled. */
	public static function canWarm():Bool
		return Lib.current != null && Lib.current.stage != null && Lib.current.stage.context3D != null;

	/**
	 * Forces `shader`'s GL program to compile & link now instead of on its first
	 * draw. Returns the shader, or null if it couldn't be warmed (missing shader
	 * or no GL context yet - it will then compile lazily on first use).
	 */
	public static function warm(shader:FunkinShader):FunkinShader {
		if (shader == null || !canWarm()) return null;
		try {
			if (shader.__context == null)
				shader.__context = Lib.current.stage.context3D;
			shader.__init();
			return shader;
		} catch(e:Dynamic) {
			Logs.warn('ShaderPreload: failed to warm ${shader.fileName}: $e');
			return null;
		}
	}

	/**
	 * Lists all shader names under `shaders/` (one subfolder deep), without their
	 * file extension. Vertex-only files are skipped.
	 */
	public static function list():Array<String> {
		var names:Array<String> = [];
		inline function scan(path:String) {
			var n = shaderNameFor(path);
			if (n != null && !names.contains(n)) names.push(n);
		}
		for (f in Paths.getFolderContent('shaders', true)) scan(f);
		for (dir in Paths.getFolderDirectories('shaders', true))
			for (f in Paths.getFolderContent(dir, true)) scan(f);
		return names;
	}

	static function shaderNameFor(path:String):String {
		if (!path.startsWith('shaders/')) return null;
		for (ext in ['.frag', '.glsl'])
			if (path.endsWith(ext)) return path.substr(8, path.length - 8 - ext.length);
		return null;
	}

	/**
	 * Pre-compiles every shader found under `shaders/` (one subfolder deep) and
	 * caches the instances. Returns how many shaders were warmed.
	 */
	public static function preloadAll():Int {
		if (!canWarm()) {
			Logs.warn('ShaderPreload: no GL context yet, skipping shader pre-compilation');
			return 0;
		}
		var count = 0;
		for (name in list()) {
			var s = create(name);
			if (s != null) {
				cache.set(name, s);
				count++;
			}
		}
		Logs.trace('ShaderPreload: warmed $count shader program${(count == 1) ? "" : "s"}', SUCCESS, GREEN);
		return count;
	}

	/** Drops cached shader instances. Compiled programs stay in the GL context. */
	public static function clear() cache.clear();
}

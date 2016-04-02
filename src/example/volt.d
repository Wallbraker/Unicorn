// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Example file that builds the volt compiler.
 *
 * Uses llvm-config to get info about llvm.
 */
module volt;

import std.string : toLower, format, endsWith;
import std.cstream : dout;

import uni.core.def : getMachine, getPlatform;
import uni.core.target : Instance, Target, Rule;
import uni.core.solver : build;
import uni.util.cmd : getOutput, CmdException;
import uni.util.env : findCmd, getEnv, getEnvSplit, isEnvSet, splitIntoArgs;
import uni.util.path : baseName, makeToOutput, listDir;

import dlang = uni.lang.d;


/*
 *
 * Config
 *
 */


/** often gcc on linux, dmc on windows */
__gshared string cmdCC = "gcc";

__gshared string cmdDMD = "gdmd";

__gshared string cmdRDMD = "rdmd";

__gshared string cmdLlvmConfig = "llvm-config";

__gshared string machine = getMachine();

__gshared string platform = getPlatform();

__gshared string target = "volt";

__gshared string sanity = "a.out";

__gshared string[] flagsD = [];

__gshared string[] flagsLD = [];

__gshared string objectEnding = ".o";

__gshared string ddepEnding = ".dd";

__gshared string sourceDir = "src";

__gshared string outputDir;

__gshared bool optionDmd = false;

__gshared bool debugPrint = false;


class Env
{
	Instance ins;

	string target;

	string rtDir;
	string wattDir;
	string teslaDir;
	string metalDir;
	string voltaDir;
	string diodeDir;
	string chargeDir;
	string sanityDir;
	string batteryDir;

	Target exe;
	Target rtHost;
	Target wattHost;

	Target[] rtDeps;
}

string getFileInVolta(Env env, string dir)
{
	return env.voltaDir is null ? dir : env.voltaDir ~ "/" ~ dir;
}


/**
 * Build the volt compiler.
 */
int buildVolt()
{
	/*
	 * First find the compilers.
	 */

	cmdCC = findCmd([cmdCC], "CC", cmdCC);
	cmdRDMD = findCmd([cmdRDMD], "RDMD", cmdRDMD);
	cmdDMD = dlang.findDmd();
	cmdLlvmConfig = findCmd([cmdLlvmConfig], "LLVM_CONFIG", cmdLlvmConfig);


	/*
	 * Work around some inconsistencies between platforms.
	 */

	version(Windows) {
		// XXX Actually check if this is needed.
		optionDmd = true;

		// On windows DMD requires this.
		objectEnding = ".obj";
	}
	auto str = toLower(baseName(cmdDMD));
	if (str == "dmd") {
		optionDmd = true;
	}

	/*
	 * Setup flags initial flags first.
	 */

	flagsD = ["-w"];
	flagsLD = [];


	/*
	 * LLVM setup.
	 */

	flagsLD ~= getLlvmFlagsLD();


	/*
	 * Platform specific settings.
	 */

	machine = getEnv("MACHINE", machine);
	platform = getEnv("PLATFORM", platform);

	switch(platform) {
	case "mac":
		flagsLD ~= ["-L-ldl"];
		break;

	case "linux":
		flagsLD ~= "-L-ldl";
		break;

	case "windows":
		target ~= ".exe";
		sanity ~= ".exe";
		break;

	default:
		dout.writefln("Unknown platform! %s", platform);
		return 2;
	}


	/*
	 * Pickup user specified flags.
	 */

	string debugFlag = optionDmd ? "-gc" : "-g";
	flagsD ~= getEnvSplit("DFLAGS", [debugFlag, "-debug"]);
	flagsLD ~= getEnvSplit("LDFLAGS", [debugFlag, "-debug"]);


	/*
	 * Output dir.
	 */

	outputDir = ".obj/" ~ platform ~ "-" ~ machine ~ "/";


	/*
	 * Done with config.
	 */

	if (debugPrint) {
		dout.writefln("CC: ", cmdCC);
		dout.writefln("DMD: ", cmdDMD);
		dout.writefln("DFLAGS: ", flagsD);
		dout.writefln("LDFLAGS: ", flagsLD);
		dout.writefln("PLATFORM: ", platform);
	}


	/*
	 * Create all the rules.
	 */

	auto env = new Env();
	env.ins = new Instance();
	env.voltaDir = getEnv("VOLTA_DIR", null);

	env.rtDir = env.getFileInVolta("rt");
	env.wattDir = getEnv("WATT_DIR", env.wattDir);
	env.teslaDir = getEnv("TESLA_DIR", env.teslaDir);
	env.diodeDir = getEnv("DIODE_DIR", env.diodeDir);
	env.metalDir = getEnv("METAL_DIR", env.metalDir);
	env.chargeDir = getEnv("CHARGE_DIR", env.chargeDir);
	env.batteryDir = getEnv("BATTERY_DIR", env.batteryDir);
	env.sanityDir = env.getFileInVolta("test");
	flagsD ~= ("-I" ~ env.getFileInVolta(sourceDir));

	Target[] targets;

	env.exe = createExeRule(env);

	auto rts = createRTs(env);

	auto test = createSanity(env);

	auto mega = env.ins.fileNoRule("__all");
	mega.deps = rts ~ test;

	if (env.wattDir !is null) {
		mega.deps ~= createWatts(env);
	}

	if (env.teslaDir !is null) {
		mega.deps ~= createBin(env, env.teslaDir, "runner");
	}

	if (env.diodeDir !is null) {
		mega.deps ~= createBin(env, env.diodeDir, "diode");
	}

	if (env.chargeDir !is null && false) {
		mega.deps ~= createBin(env, env.chargeDir, "charge", "-D", "DynamicSDL");
	}

	if (env.batteryDir !is null) {
		mega.deps ~= createBin(env, env.batteryDir, "battery");
	}


	/*
	 * And build.
	 */

	try {
		build(mega);
	} catch (CmdException ce) {
		dout.writefln("%s", ce.msg);
		return 1;
	} catch (Exception e) {
		dout.writefln("%s", e);
		return 2;
	}
	return 0;
}

/**
 * Calls llvm-config and extracts the needed ld flags.
 */
string[] getLlvmFlagsLD()
{
	string[] args = [
		"--system-libs",
		"--ldflags",
		"--libs",
		"core",
		"bitwriter",
		"bitreader",
		"linker",
		"target",
		"x86codegen"
	];

	auto output = getOutput(cmdLlvmConfig, args);
	string[] ret = splitIntoArgs(output);

	foreach(ref r; ret) {
		r = "-L" ~ r;
	}
	ret ~= "-L-lstdc++";

	return ret;
}


/*
 *
 * Building rules.
 *
 */

Target createSanity(Env env)
{
	auto name = env.getFileInVolta(sanity);
	auto src = env.ins.fileNoRule(env.sanityDir ~ "/test.volt");
	auto deps = [env.exe, src, env.rtHost];
	auto print = "  VOLT   " ~ name;
	auto cmd = env.exe.name;
	auto args = [
		"--no-stdlib",
		"-I", env.rtDir ~ "/src",
		env.rtHost.name,
		"-o", name,
		"-l", "gc",
		src.name];

	return createSimpleRule(env.ins, name, deps, cmd, args, print);
}

Target createBin(Env env, string dir, string exeName, string[] extraArgs...)
{
	auto name = dir ~ "/" ~ exeName;
	auto deps = [env.exe, env.rtHost, env.wattHost] ~ env.rtDeps;
	auto print = "  VOLT   " ~ name;
	auto cmd = env.exe.name;
	auto args = [
		"--no-stdlib",
		"-I", env.rtDir ~ "/src",
		"-I", env.wattDir ~ "/src",
		env.rtHost.name,
		env.wattHost.name,
		"-o", name,
		"-l", "gc",
		"-l", "dl"] ~ extraArgs;

	void func(Target t) {
		deps ~= t;
		args ~= t.name;
	}

	listDir(dir ~ "/src", "*.volt", env.ins, &func);

	return createSimpleRule(env.ins, name, deps, cmd, args, print);
}

Target[] createRTs(Env env)
{
	string rtSrcDir = env.rtDir ~ "/src";
	string[] flags = [
		"--no-stdlib",
		"-I", rtSrcDir
	];
	string[] srcs;
	Target[] deps;
	void func(Target t) {
		deps ~= t;

		if (t.name.endsWith("object.volt") ||
		    t.name.endsWith("defaultsymbols.volt")) {
			env.rtDeps ~= t;
		}
	}

	listDir(rtSrcDir, "*.volt", env.ins, &func);

	auto ret = createRules(env, flags, deps, env.rtDir ~ "/libvrt", true);
	env.rtHost = ret[0];
	return ret;
}

Target[] createWatts(Env env)
{
	string[] flags = [
		"--no-stdlib",
		"-I", env.rtDir ~ "/src"
	];
	string[] srcs;
	Target[] deps;
	void func(Target t) {
		deps ~= t;
	}

	listDir(env.wattDir ~ "/src", "*.volt", env.ins, &func);

	auto ret = createRules(env, flags, deps, env.wattDir ~ "/bin/libwatt", false);
	env.wattHost = ret[0];
	return ret;
}

Target[] createRules(Env env, string[] flags, Target[] srcs, string baseName, bool buildMetal)
{
	auto oArgs = flags ~ ["-c", "-o"];
	auto bcDeps = [env.exe] ~ srcs ~ env.rtDeps;
	auto bcArgs = flags ~ ["--emit-bitcode", "-o"];
	string[] bcSrcs;
	foreach (d; srcs) {
		bcSrcs ~= d.name;
	}

	Target[] bcTargets;
	Target[] oTargets;

	Target createHost() {
		auto name = baseName ~ "-host.bc";
		auto deps = bcDeps;
		auto cmd = env.exe.name;
		auto print = "  VOLT   " ~ name;
		auto args = bcArgs ~ name ~ bcSrcs;

		return createSimpleRule(env.ins, name, deps, cmd, args, print);
	}

	Target bcCreate(string arch, string platform) {
		auto name = baseName ~ "-" ~ arch ~ "-" ~ platform ~ ".bc";
		auto deps = bcDeps ~ env.exe;
		auto cmd = env.exe.name;
		auto print = "  VOLT   " ~ name;
		auto args = ["--arch", arch, "--platform", platform] ~
			bcArgs ~ name ~ bcSrcs;

		auto ret = createSimpleRule(env.ins, name, deps, cmd, args, print);
		bcTargets ~= ret;
		return ret;
	}

	Target oCreate(string arch, string platform) {
		auto rtbc = bcCreate(arch, platform);
		auto name = baseName ~ "-" ~ arch ~ "-" ~ platform ~ ".o";
		auto cmd = env.exe.name;
		auto dep = [rtbc, env.exe];
		auto print = "  VOLT   " ~ name;
		auto args = ["--arch", arch, "--platform", platform] ~
			oArgs ~ name ~ rtbc.name;

		auto ret = createSimpleRule(env.ins, name, dep, cmd, args, print);
		oTargets ~= ret;
		return ret;
	}

	bcCreate("le32", "emscripten");
	oCreate("x86_64", "msvc");
	if (buildMetal) {
		oCreate("x86", "metal");
		oCreate("x86_64", "metal");
	}
	oCreate("x86", "mingw");
	oCreate("x86_64", "mingw");
	oCreate("x86", "linux");
	oCreate("x86_64", "linux");
	oCreate("x86", "osx");
	oCreate("x86_64", "osx");

	return createHost() ~ bcTargets ~ oTargets;
}

Target[] createDDeps(Env env)
{
	string sourceDir = env.getFileInVolta(sourceDir);

	Target[] ret;
	void func(Target t) {
		ret ~= t;
	}
	listDir(sourceDir, "*.d", env.ins, &func);

	return ret;
}

Target createExeRule(Env env)
{
	auto targets = createDDeps(env);

	string name = env.getFileInVolta(target);
	string mainFile = env.getFileInVolta(sourceDir ~ "/main.d");

	Target ret = env.ins.fileNoRule(name);
	Rule rule = new Rule();

	ret.deps = targets.dup;
	ret.rule = rule;

	string[] args;
	args ~= "--build-only";
	args ~= ("--compiler=" ~ cmdDMD);
	args ~= flagsD;
	args ~= flagsLD;
	args ~= ("-of" ~ name);
	args ~= mainFile;

	rule.outputs = [ret];
	rule.cmd = cmdRDMD;
	rule.args = args;
	rule.print = "  RDMD   " ~ ret.name;
	rule.input = targets.dup;

	return ret;
}

Target createSimpleRule(
	Instance i, Target src,
	string dstName, string depName,
	string cmd, string[] args, string print)
{
	Target dst, dep;
	auto rule = new Rule();

	dst = i.fileNoRule(dstName);
	dst.deps = [src];
	dst.rule = rule;

	if (depName !is null) {
		dep = i.fileNoRule(depName);
		dep.deps = [src];
		dep.rule = rule;
		dlang.addDeps(i, dst, depName);
	}

	rule.cmd = cmd;
	rule.args = args;
	rule.print = print;
	rule.input = [src];
	rule.outputs = dep !is null ? [dst, dep] : [dst];

	return dst;
}

Target createSimpleRule(
	Instance i, string dstName, Target[] deps,
	string cmd, string[] args, string print)
{
	Target dst;
	auto rule = new Rule();

	dst = i.fileNoRule(dstName);
	dst.deps = deps.dup;
	dst.rule = rule;

	rule.cmd = cmd;
	rule.args = args;
	rule.print = print;
	rule.input = deps.dup;
	rule.outputs = [dst];

	return dst;
}

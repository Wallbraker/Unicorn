// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Example file that builds the volt compiler.
 *
 * Uses llvm-config to get info about llvm.
 */
module volt;

import std.string : toLower, format;
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

__gshared string cmdLlvmConfig = "llvm-config";

__gshared string machine = getMachine();

__gshared string platform = getPlatform();

__gshared string target = "volt";

__gshared string[] flagsD = [];

__gshared string[] flagsLD = [];

__gshared string objectEnding = ".o";

__gshared string ddepEnding = ".dd";

__gshared string sourceDir = "src";

__gshared string outputDir;

__gshared bool optionDmd = false;

__gshared bool debugPrint = false;


/**
 * Build the volt compiler.
 */
int buildVolt()
{
	/*
	 * First find the compilers.
	 */

	cmdCC = findCmd([cmdCC], "CC", cmdCC);
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

	flagsD = ["-c", "-w", "-I" ~ sourceDir];
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

	auto i = new Instance();

	Target[] targets;

	targets ~= createDRules(i);

	auto exe = createExeRule(i, targets);

	auto rts = createRTs(i, exe);

	// First rt is the host one.
	auto test = createTest(i, exe, rts[0]);

	auto mega = i.fileNoRule("__all");
	mega.deps = rts ~ test;

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

Target createTest(Instance ins, Target exe, Target rtHost)
{
	auto name = "a.out";
	auto src = ins.fileNoRule("test/test.volt");
	auto deps = [exe, src, rtHost];
	auto print = "  VOLT   " ~ name;
	auto cmd = exe.name;
	auto args = [
		"--no-stdlib",
		"-I", "rt/src",
		rtHost.name,
		"-o", name,
		"-l", "gc",
		src.name];

	return createSimpleRule(ins, name, deps, cmd, args, print);
}
	
Target[] createRTs(Instance ins, Target exe)
{
	Target[] rtDeps = [exe];
	string[] rtSrcs;
	string[] rtArgs = [
		"--no-stdlib",
		"-I",
		"rt/src",
		"--emit-bitcode",
		"-o"
	];
	string[] rtBinArgs = [
		"--no-stdlib",
		"-I",
		"rt/src",
		"-c",
		"-o"
	];

	void func(Target t) {
		rtSrcs ~= t.name;
		rtDeps ~= t;
	}

	listDir("rt/src", "*.volt", ins, &func);

	Target createHost() {
		auto name = "rt/libvrt-host.bc";
		auto deps = rtDeps;
		auto cmd = exe.name;
		auto print = "  VOLT   " ~ name;
		auto args = rtArgs ~ name ~ rtSrcs;

		return createSimpleRule(ins, name, deps, cmd, args, print);
	}

	Target createRT(string arch, string platform) {
		auto name = "rt/libvrt-" ~ arch ~ "-" ~ platform ~ ".bc";
		auto deps = rtDeps;
		auto cmd = exe.name;
		auto print = "  VOLT   " ~ name;
		auto args = ["--arch", arch, "--platform", platform] ~
			rtArgs ~ name ~ rtSrcs;

		return createSimpleRule(ins, name, deps, cmd, args, print);
	}

	Target createRTBin(string arch, string platform) {
		auto nameBase = "rt/libvrt-" ~ arch ~ "-" ~ platform;
		auto nameBc = nameBase ~ ".bc";
		auto name = nameBase ~ ".o";
		auto print = "  VOLT   " ~ name;
		auto cmd = exe.name;
		auto rtbc = ins.file(nameBc);
		auto args = ["--arch", arch, "--platform", platform] ~
			rtBinArgs ~ name ~ nameBc;
		auto dep = [rtbc, exe];

		return createSimpleRule(ins, name, dep, cmd, args, print);
	}

	return [createHost(),
		createRT("le32", "emscripten"),
		createRT("x86_64", "msvc"),
		createRT("x86", "mingw"),
		createRT("x86_64", "mingw"),
		createRT("x86", "linux"),
		createRT("x86_64", "linux"),
		createRT("x86", "osx"),
		createRT("x86_64", "osx"),
		createRTBin("x86_64", "msvc"),
		createRTBin("x86", "mingw"),
		createRTBin("x86_64", "mingw"),
		createRTBin("x86", "linux"),
		createRTBin("x86_64", "linux"),
		createRTBin("x86", "osx"),
		createRTBin("x86_64", "osx")
		];
}


Target[] createDRules(Instance i)
{
	Target[] ret;
	string[] args;

	args.length = flagsD.length + 3;
	args[0 .. flagsD.length] = flagsD[0 .. $];

	void func(Target t) {
		auto obj = makeToOutput(t.name, sourceDir, outputDir, ".d", objectEnding);
		auto dep = makeToOutput(t.name, sourceDir, outputDir, ".d", ddepEnding);
		auto print = "  DMD    " ~ t.name;
		auto objCmd = "-of" ~ obj;
		auto depCmd = "-deps=" ~ dep;

		args[$ - 1] = t.name;
		args[$ - 2] = objCmd;
		args[$ - 3] = depCmd;

		ret ~= createSimpleRule(i, t, obj, dep, cmdDMD, args.dup, print);
	}
	listDir(sourceDir, "*.d", i, &func);

	return ret;
}

Target createExeRule(Instance ins, Target[] targets)
{
	Target ret = ins.fileNoRule(target);
	Rule rule = new Rule();

	ret.deps = targets.dup;
	ret.rule = rule;

	string[] args; uint path;
	args.length = flagsLD.length + targets.length + 1;
	args[0 .. flagsLD.length] = flagsLD[0 .. $];
	args[flagsLD.length] = "-of" ~ target;
	for (int i, k = cast(int)flagsLD.length + 1; i < targets.length; i++, k++) {
		args[k] = targets[i].name;
	}

	rule.outputs = [ret];
	rule.cmd = cmdDMD;
	rule.args = args;
	rule.print = "  LD     " ~ target;
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

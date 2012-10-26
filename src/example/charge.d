// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Example file that builds the game Charged-Miners.
 *
 * http://charged-miners.com
 */
module example.charge;

import std.string : toLower, format;
import std.cstream : dout;

import uni.core.def : getMachine, getPlatform;
import uni.core.target : Instance, Target, Rule;
import uni.core.solver : build;
import uni.util.env : findCmd, getEnv, getEnvSplit, isEnvSet;
import uni.util.path : baseName, makeToOutput, listDir;

import dlang = uni.lang.d;


/*
 *
 * Config
 *
 */


/** often gcc on linux, dmc on windows */
__gshared string cmdCC = "gcc";

__gshared string cmdDMD = "gdmd-v1";

__gshared string machine = getMachine();

__gshared string platform = getPlatform();

__gshared string target = "Charge";

__gshared string[] flagsD = [];

__gshared string[] flagsC = [];

__gshared string[] flagsM = [];

__gshared string[] flagsLD = [];

__gshared string objectEnding = ".o";

__gshared string ddepEnding = ".dd";

__gshared string resDir = "res";

__gshared string sourceDir = "src";

__gshared string outputDir;

__gshared bool optionDmc = false;

__gshared bool optionDmd = false;

__gshared bool debugPrint = false;




void buildCharge()
{
	/*
	 * First find the compilers.
	 */

	cmdCC = findCmd([cmdCC], "CC", cmdCC);
	cmdDMD = findCmd(["dmd", cmdDMD, "gdmd"], "DMD", cmdDMD);


	/*
	 * Work around some inconsistencies between platforms.
	 */

	version(Windows) {
		// XXX Actually check if this is needed.
		optionDmc = true;
		optionDmd = true;

		// On windows DMD requires this.
		objectEnding = ".obj";
	}
	auto str = toLower(baseName(cmdDMD));
	if (str == "dmd")
		optionDmd = true;

	/*
	 * Setup flags initial flags first.
	 */

	flagsC = ["-c"];
	flagsD = ["-c", "-w",
	          "-I" ~ sourceDir,
	          "-J" ~ resDir ~ "/builtins",
	          "-J" ~ resDir ~ "/miners"];
	flagsM = ["-c"];
	flagsLD = [];


	/*
	 * Platform specific settings.
	 */

	machine = getEnv("MACHINE", machine);
	platform = getEnv("PLATFORM", platform);

	switch(platform) {
	case "mac":
		flagsC ~= ["-arch", "i386", "-arch", "x86_64"];
		flagsM ~= ["-arch", "i386", "-arch", "x86_64"];
		flagsLD ~= ["-L-ldl", "-L-framework", "-LCocoa"];
		break;

	case "linux":
		flagsLD ~= "-L-ldl";
		break;

	case "windows":
		target ~= ".exe";
		if (!optionDmd)
			flagsLD ~= ["-L-lgphobos", "-L-lws2_32"];
		break;

	default:
		dout.writefln("Unknown platform! %s", platform);
		return;
	}


	/*
	 * Optional components.
	 */
	if (isEnvSet("USE_SDL"))
		flagsLD ~= ["-L-lSDL"];
	else
		flagsD ~= ["-version=DynamicSDL"];

	if (isEnvSet("USE_ODE"))
		flagsLD ~= ["-L-L.", "-L-lode", "-L-lstdc++"];
	else
		flagsD ~= ["-version=DynamicODE"];


	/*
	 * Pickup user specified flags.
	 */

	string debugFlag = optionDmd ? "-gc" : "-g";
	flagsC ~= getEnvSplit("CFLAGS", ["-g"]);
	flagsD ~= getEnvSplit("DFLAGS", [debugFlag, "-debug"]);
	flagsLD ~= getEnvSplit("LDFLAGS", ["-quiet", debugFlag, "-debug"]);


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
		dout.writefln("CFLAGS: ", flagsC);
		dout.writefln("DFLAGS: ", flagsD);
		dout.writefln("LDFLAGS: ", flagsLD);
		dout.writefln("PLATFORM: ", platform);
	}


	/*
	 * Create all the rules.
	 */

	auto i = new Instance();

	Target[] targets;

	targets ~= createCRules(i);
	targets ~= createDRules(i);

	auto exe = createExeRule(i, targets);


	/*
	 * And build.
	 */

	build(exe);
}


/*
 *
 * Building rules.
 *
 */


Target[] createCRules(Instance i)
{
	Target[] ret;
	string[] args;

	args.length = flagsC.length + (optionDmc ? 2 : 3);
	args[0 .. flagsC.length] = flagsC[0 .. $];

	void func(Target t) {
		auto obj = makeToOutput(t.name, sourceDir, outputDir, ".c", objectEnding);
		auto print = "  CC     " ~ t.name;

		if (optionDmc) {
			args[$ - 2] = format(`-o"%s"`, obj);
		} else {
			args[$ - 3] = "-o";
			args[$ - 2] = obj;
		}

		args[$ - 1] = t.name;

		ret ~= createSimpleRule(i, t, obj, null, cmdCC, args.dup, print);
	}
	listDir(sourceDir, "*.c", i, &func);

	return ret;
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
	args[0 .. flagsLD.length] = flagsLD;
	args[flagsLD.length] = "-of" ~ target;
	for (int i, k = cast(int)flagsLD.length + 1; i < targets.length; i++, k++)
		args[k] = targets[i].name;

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

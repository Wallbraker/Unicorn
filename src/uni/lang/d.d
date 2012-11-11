// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Functions for interacting with D files during builds.
 */
module uni.lang.d;

import std.stdio : writefln;
import std.regex : regex, match;
import std.string : splitLines, indexOf, replace, split;
import std.file : read, exists;

import uni.util.cmd : getOutput;
import uni.util.env : getEnv, findCmd;
import uni.core.target : Instance, Target;


/**
 * Adds deps to target.
 *
 * Only adds the deps to the given target.
 */
void addDeps(Instance i, Target t, string dep)
{
	char[] str;
	try {
		str = cast(char[])read(dep);
	} catch (Exception e) {
		return;
	}

	void throwMalformed() {
		throw new Exception("Malformed d-dep file \"" ~ dep ~ "\"");
	}

	size_t findCheck(const(char)[] str, string sub) {
		auto pos = indexOf(str, sub);

		if (pos <= 0)
			throwMalformed();
		return cast(size_t)pos;
	}

	bool[string] added;

	foreach(l; splitLines(str)) {
		// Find the end of the fist () pair.
		auto pos = findCheck(l, ")");

		// After that find the second () pair.
		size_t start = findCheck(l[pos .. $], "(") + pos + 1;
		size_t end = findCheck(l[start .. $], ")") + start;

		auto tmp = l[start .. end];
		if (tmp in added)
			continue;

		string name = tmp.idup;
		// Keep track of which files are already added.
		added[name] = true;

		version(Windows)
			name = replace(l[start .. end], "\\\\", "\\").idup;

		t.deps ~= i.file(name);
	}
}

/**
 * Select D version in the findDmd command.
 */
enum DVersion
{
	D1 = 1,
	D2 = 2,
}

/**
 * Find DMD or GDC compiler.
 */
string findDmd(DVersion ver = DVersion.D2)
{
	auto reg = regex(ver == DVersion.D2 ? "DMD.*v2" : "DMD.*v1");
	string ret;

	version(Windows) {
		string pathSeperator = ";";
		string dmdBinary = "\\dmd.exe";
	} else version(Posix) {
		string pathSeperator = ":";
		string dmdBinary = "/dmd";
	} else {
		static assert(false);
	}

	// Try the DMD envar first then gdmd.
	ret = findCmd(ver == DVersion.D2 ? ["gdmd"] : ["gdmd-v1"], "DMD", null);
	if (ret !is null)
		return ret;

	// Look for a matching DMD version.
	auto path = getEnv("PATH");
	foreach(n; split(path, pathSeperator)) {
		try {
			auto exe = n ~ dmdBinary;
			if (!exists(exe))
				continue;

			auto l = splitLines(getOutput(exe, null));
			if (l.length == 0)
				continue;

			auto m = match(l[0], reg);
			if (!m.empty)
				return exe;

		} catch (Exception e) {
		}
	}

	if (ver == DVersion.D2)
		return "dmd";
	else
		return findCmd(["gdmd"], null, "dmd");
}

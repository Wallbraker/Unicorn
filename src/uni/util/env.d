// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Functions for querying the program environment.
 */
module uni.util.env;

version(Windows) {

	import std.string : split;
	import std.algorithm : endsWith;
	import std.file : exists;

} else version(Posix) {

	import core.sys.posix.stdio : FILE, fgets, fclose, popen;

} else {

	static assert(false);

}

import core.stdc.stdlib : alloca, getenv;
import std.conv : to;
import std.ascii : isWhite;
import std.string : format, splitLines, toStringz;

import uni.util.cmd : getOutput;


/**
 * Is the env variable set.
 */
bool isEnvSet(string name)
{
	auto namez = toStringz(name);
	return getenv(namez) !is null;
}

/**
 * Returns the env variable or null.
 */
string getEnv(string name)
{
	auto namez = toStringz(name);
	auto t = getenv(namez);

	if (t is null)
		return null;
	return to!string(t);
}

/**
 * Returns the env variable or @def.
 *
 * Does not split "" or splits whitespace.
 */
string getEnv(string name, string def)
{
	auto t = getEnv(name);

	return t is null ? def : t;
}

/**
 * Returns the env variable or @def, for both it is split
 * into multiple entries suitable for args to commands.
 */
string[] getEnvSplit(string name, string def)
{
	auto t = getEnv(name);

	return splitIntoArgs(t is null ? def : t);
}

/**
 * Returns the env variable or @def, for only the env variable
 * it is split into multiple entries suitable for args to commands.
 */
string[] getEnvSplit(string name, string[] def)
{
	auto t = getEnv(name);

	return t is null ? def : splitIntoArgs(t);
}

/**
 * Locate a command, similar to unix's which command.
 */
string findCmd(string[] names, string envName, string def)
{
	string ret;

	// First check if 
	if (envName !is null) {
		ret = getEnv(envName);
		if (ret !is null)
			return ret;
	}

	version(Windows) {
		auto lines = split(getEnv("PATH"), ";");

		foreach(n; names) {
			// Needs to add .exe at the end.
			if (!endsWith(n, ".exe"))
				n ~= ".exe";

			foreach(l; lines) {
				auto tmp = l ~ "\\" ~ n;

				if (exists(tmp))
					return tmp;
			}
		}
	} else { /* Linux/MacOSX */
		foreach(n; names) {
			// About as standard location as possible.
			auto r = getOutput("/usr/bin/which", [n]);

			if (r is null || r[0] == 0)
				continue;

			return splitLines(r)[0].idup;
		}
	}

	if (ret is null)
		ret = def;

	return ret;
}

/**
 * Split and escape a string as bash/make does.
 */
string[] splitIntoArgs(string str)
{
	char* ptr;
	char[] tmp;
	size_t pos;
	string[] ret;

	ptr = cast(char*)alloca(str.length);
	if (ptr is null)
		tmp.length = str.length;
	else
		tmp = ptr[0 .. str.length];

	enum State {
		WHITESPACE,
		NORMAL,
		ESCAPE, // \
		IGNORE, // Inside a " field.
	}

	State state = State.WHITESPACE;
	State stateOld = state;

	void escape() {
		stateOld = state;
		state = State.ESCAPE;
	}

	void add(char c) {
		tmp[pos++] = c;
	}

	void done() {
		if (pos == 0)
			return;
		ret ~= tmp[0 .. pos].idup;
		pos = 0;
	}

	foreach(c; str) {
		switch(state) {
		case State.WHITESPACE:
			if (isWhite(c)) {
				continue;
			} else if (c == '\\') {
				escape();
			} else if (c == '"') {
				state = State.IGNORE;
			} else {
				add(c);
				state = State.NORMAL;
			}
			break;
		case State.NORMAL:
			if (isWhite(c)) {
				done();
				state = State.WHITESPACE;
			} else if (c == '\\') {
				escape();
			} else if (c == '"') {
				state = State.IGNORE;
			} else {
				add(c);
			}
			break;
		case State.ESCAPE:
			add(c);
			if (stateOld == State.IGNORE)
				state = stateOld;
			else
				state = State.NORMAL;
			break;
		case State.IGNORE:
			if (c == '\\') {
				escape();
			} else if (c == '"') {
				state = State.NORMAL;
			} else {
				add(c);
			}
			break;
		default:
			assert(false);
		}
	}

	if (state == State.NORMAL ||
	    state == State.IGNORE)
		done();

	return ret;
}

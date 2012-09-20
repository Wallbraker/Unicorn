// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Functions for interacting with D files during builds.
 */
module uni.lang.d;

import std.string : splitlines, find, replace;
import std.file : read;

import uni.core.target : Instance, Target;


/**
 * Adds deps to target.
 *
 * Only adds the deps to the given target.
 */
void addDeps(Instance i, Target t, string dep)
{
	string str;
	try {
		str = cast(string)read(dep);
	} catch (Exception e) {
		return;
	}

	void throwMalformed() {
		throw new Exception("Malformed d-dep file \"" ~ dep ~ "\"");
	}

	size_t findCheck(string str, string sub) {
		auto pos = find(str, sub);

		if (pos <= 0)
			throwMalformed();
		return cast(size_t)pos;
	}

	bool[string] added;

	foreach(l; splitlines(str)) {
		// Find the end of the fist () pair.
		auto pos = cast(size_t)findCheck(l, ")");

		// After that find the second () pair.
		size_t start = findCheck(l[pos .. $], "(") + pos + 1;
		size_t end = findCheck(l[start .. $], ")") + start;

		auto tmp = l[start .. end];
		if (tmp in added)
			continue;

		// Keep track of which files are already added.
		added[tmp] = true;

		version(Windows)
			tmp = replace(l[start .. end], "\\\\", "\\");

		t.deps ~= i.file(tmp);
	}
}

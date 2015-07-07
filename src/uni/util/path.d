// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Function for manipulating paths.
 */
module uni.util.path;

import std.string : sformat, replace;
import std.file : exists, mkdir, DirEntry, dirEntries, SpanMode;
public import std.path;

import uni.core.target : Instance, Target;


/**
 * Searches @dir for files matching pattern, foreach found
 * creates a Target in @i and sets the time, saving one
 * stat per file.
 */
void listDir(string dir, string pattern,
             Instance i, void delegate(Target t) dg)
{
	foreach(ref DirEntry de; dirEntries(dir, SpanMode.breadth)) {
		if (de.isDir) {
			continue;
		} else if (!globMatch(de.name, pattern)) {
			continue;
		}

		auto t = i.file(de.name);
		t.mod = de.timeLastModified;
		if (t.status < Target.CHECKED) {
			t.status = Target.CHECKED;
		}
		dg(t);
	}
}

/**
 * Does the same as unix's "mkdir -p" command.
 */
void mkdirP(string name)
{
	if (name == "" || name is null)
		return;

	auto str = dirName(name);
	if (str != ".") {
		mkdirP(str);
	}

	if (!exists(name)) {
		mkdir(name);
	}
}

/**
 * Replaces @oldPrefix and @oldSufix with @newPrefix and @newSufix.
 *
 * Assumes that name starts and ends with @oldPrefix, @oldSufix.
 */
string makeToOutput(string name,
	string oldPrefix, string newPrefix,
	string oldSufix, string newSufix)
{
	// Should be enough for all platforms max pathlength.
	char[1024] data;
	char[] ret;
	size_t pos;

	// Poor mans buffered string writer.
	void add(string t) {
		auto tmp = sformat(data[pos .. $], "%s", t);
		pos += tmp.length;
	}

	add(newPrefix);

	add(name[oldPrefix.length + 1 .. $ - oldSufix.length]);

	add(newSufix);

	version(Windows) {
		ret = replace(data[0 .. pos], "/", "\\");
	} else {
		ret = data[0 .. pos].dup;
	}

	// Make sure we don't return a pointer to the stack.
	return ret.ptr == data.ptr ? ret.idup : cast(string)ret;
}

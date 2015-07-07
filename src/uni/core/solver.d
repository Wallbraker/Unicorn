// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Here is the main solver algorithm implementation used as
 * a backend for all builds. Uses uni.util.cmd to dispatch
 * compilers and other tasks.
 */
module uni.core.solver;

import std.cstream : dout;

import uni.core.target : Target, Rule;
import uni.util.path : mkdirP, dirName;
import uni.util.cmd : runCommand, CmdGroup;


/**
 * Builds a target, will throw exceptions on build failure.
 */
void build(Target t)
{
	auto g = new CmdGroup();

	auto built = build(t, g);
	if (built) {
		g.waitAll();
	}
}

/**
 * Internal recursive build function. Could be improved,
 * as every time the builder goes backup it waits for all
 * the children to complete building.
 */
private bool build(Target t, CmdGroup g)
{
	// This is needed for Windows.
	if (t.status < Target.CHECKED) {
		t.updateTime();
	}

	// Our work is allready done.
	if (t.status >= Target.BUILDING) {
		return t.status == Target.BUILDING ? true : false;
	}

	// Build all the dependancies.
	bool built;
	foreach(child; t.deps) {
		built = build(child, g) || built;
	}

	// XXX Figure out a better algorithm then this.
	if (built) {
		g.waitAll();
	}

	bool shouldBuild;
	foreach(d; t.deps) {
		// Kinda risky adding =,
		// but it avoids uneccasery recompiles.
		if (t.mod >= d.mod)
			continue;

		shouldBuild = true;
		break;
	}

	// All deps are older then this target, nothing to do.
	if (!shouldBuild) {
		return false;
	}

	/*
	 * Skip the file if we can't build it, in make this
	 * is an error, but that errors when you remove a
	 * file sometimes. If it actually is a error let the
	 * compiler warn about it.
	 */
	if (t.rule is null) {
		return false;
	}

	// Make sure the directory exist.
	mkdirP(dirName(t.name));

	// Print to console what we do.
	dout.writefln(t.rule.print);
	dout.flush();

	// The business end of the solver.
	t.status = Target.BUILDING;
	g.run(t.rule.cmd, t.rule.args, &t.built);

	return true;
}

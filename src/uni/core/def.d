// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).
module uni.core.def;


/**
 * Returns the current machine.
 *
 * Current possible values are:
 * - x86
 * - x86_64
 * - ppc
 */
string getMachine()
{
	version(X86)
		return "x86";
	else version(X86_64)
		return "x86_64";
	else version(PPC)
		return "ppc";
	else
		static assert(false);
}

/**
 * Returns the current platform.
 *
 * Current possible values are:
 * - mac
 * - linux
 * - windows
 */
string getPlatform()
{
	version(Darwin)
		return "mac";
	else version(linux)
		return "linux";
	else version(Windows)
		return "windows";
	else
		static assert(false);
}

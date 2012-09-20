// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * This will the frontend to the build system eventually.
 */
module main;

import std.stdio : writefln;
import uni.license;


int main(string[] args)
{
	foreach(license; licenseArray)
		writefln("%s", license);

	return 0;
}

// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * This will the frontend to the build system eventually.
 */
module main;

import std.string : find;
import std.stdio : writefln;
import std.file : getcwd;

import uni.license;

import example.charge : buildCharge;
import example.volt : buildVolt;


int main(string[] args)
{


	if (args.length > 1) {
		switch(args[2]) {
		case "--license":
			foreach(license; licenseArray)
				writefln("%s", license);
			return 0;
		case "charge":
			buildCharge();
			return 0;
		case "volt":
			buildVolt();
			return 0;
		default:
		}
	}

	auto pwd = getcwd();

	if (find(pwd, "charge") >= 0)
		buildCharge();
	else if (find(pwd, "volt") >= 0)
		buildVolt();

	return 0;
}

// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * This will be the frontend to the build system eventually.
 */
module main;

import std.string : indexOf, toLower;
import std.stdio : stderr, writefln;
import std.file : getcwd;

import uni.license;

import example.charge : buildCharge;
import example.volt : buildVolt;
import example.packetmaker : buildPacketMaker;


int main(string[] args)
{
	if (args.length > 1) {
		switch(toLower(args[2])) {
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
		case "maker":
		case "packet":
		case "packetmaker":
			buildPacketMaker();
			return 0;
		default:
		}
	}

	auto pwd = toLower(getcwd());

	if (indexOf(pwd, "charge") >= 0) {
		buildCharge();
	} else if (indexOf(pwd, "volt") >= 0) {
		buildVolt();
	} else {
		stderr.writefln("Could no figure out what builder to run!");
		return -1;
	}

	return 0;
}

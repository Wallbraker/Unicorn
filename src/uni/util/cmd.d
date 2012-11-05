// Copyright © 2012, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/uni/license.d (BOOST ver. 1.0 license).

/**
 * Classes and functions for launching programs.
 */
module uni.util.cmd;

version(Windows) {

	import core.sys.windows.windows :
		HANDLE, BOOL, WAIT_OBJECT_0,
		SECURITY_ATTRIBUTES,
		LPSECURITY_ATTRIBUTES,
		ReadFile,
		CloseHandle,
		WaitForSingleObject,
		WaitForMultipleObjects;

} else version(Posix) {

	import core.sys.posix.unistd : fork, pid_t;
	import core.sys.posix.sys.wait : waitpid;
	import core.stdc.stdio : FILE, fread;
	import core.stdc.stdlib : exit;
	import core.stdc.errno : errno;
	import std.c.process : execvp;

	// Couldn't find these in the standard headers.
	extern(C) FILE* popen(const(char)*, const(char)*);
	extern(C) void pclose(FILE*);

} else {
	static assert(false);
}

import std.string : format, sformat;


/**
 * Like std.process system, nicer syntax and handles
 * longer command lines.
 */
int system(string cmd, string[] args)
{
	version(Windows) {

		uint uRet;
		bool bRet;
		auto hProcess = _createProcess(cmd, args);

		scope(exit)
			CloseHandle(hProcess);

		uRet = WaitForSingleObject(hProcess, -1);
		if (uRet)
			throw new CmdException(cmd, args,
				"failed to wait for program");

		int result = -1;
		bRet = GetExitCodeProcess(hProcess, cast(uint*)&result);
		if (!bRet)
			throw new CmdException(cmd, args,
				"abnormal application termination");

		return result;

	} else version(Posix) {

		// Yay fork!
		pid_t pid = fork();

		// Child, does not return.
		if (!pid)
			_execvp(cmd, args);

		while(1) {
			int status;
			pid_t wpid = waitpid(pid, &status, 0);

			if (exited(status))
				return exitstatus(status);
			else if (signaled(status))
				return -termsig(status);
			else if (stopped(status))
				continue;
			else
				break;
		}

		// This is an error path.
		int errno = errno();
		throw new CmdException(cmd, args, errno);

	} else {
		static assert(false);
	}
}

/**
 * Run and wait for a command, simple wrapper around system.
 */
void runCommand(string cmd, string[] args)
{
	int result = system(cmd, args);

	if (result != 0)
		throw new CmdException(cmd, result);
}

/**
 * Run the given command and read back the output into a string.
 * Waits for the command to complete before returning.
 *
 * XXX: Currently limited max read data.
 */
string getOutput(string cmd, string[] args)
{
	char[1024*32] stack;
	size_t size;
	string ret;

	version(Windows) {

		SECURITY_ATTRIBUTES saAttr;
		PROCESS_INFORMATION pi;
		STARTUPINFO si;
		HANDLE hOut, hIn, hProcess;
		uint uRet;
		bool bRet;

		saAttr.nLength = cast(uint)saAttr.sizeof;
		saAttr.bInheritHandle = true;
		saAttr.lpSecurityDescriptor = null;

		bRet = cast(bool)CreatePipe(&hIn, &hOut, &saAttr, 0);
		if (!bRet)
			throw new CmdException(
				cmd, args, "Could not create pipe");
		scope(exit) {
			CloseHandle(hIn);
			CloseHandle(hOut);
		}


		// Ensure the read handle to the pipe for STDOUT is not inherited.
		bRet = cast(bool)SetHandleInformation(hIn, HANDLE_FLAG_INHERIT, 0);
		if (!bRet)
			throw new CmdException(
				cmd, args, "Failed to set hIn info");


		auto cmdPtr = writeArgsToStack(stack, cmd, args);
		si.cb = cast(uint)si.sizeof;
		si.dwFlags |= STARTF_USESTDHANDLES;
		si.hStdOutput = hOut;

		bRet = CreateProcessA(
			null,
			cmdPtr,
			null,
			null,
			true,
			0,
			null,
			null,
			&si,
			&pi);

		if (!bRet)
			throw new CmdException(cmd, args, "failed to start program");

		// Not interested in this.
		CloseHandle(pi.hThread);
		scope(exit)
			CloseHandle(pi.hProcess);


		// Wait for the process to close.
		uRet = WaitForSingleObject(pi.hProcess, -1);
		if (uRet)
			throw new CmdException(
				cmd, args, "Failed to wait for program");


		// Read data from file.
		bRet = cast(bool)ReadFile(
			hIn, stack.ptr, cast(uint)stack.length, &uRet, null);
		size = cast(size_t)uRet;

		// Check result of read.
		if (!bRet || size >= stack.length)
			throw new CmdException(
				cmd, args, "Failed to read from output file");

	} else version(Posix) {

		auto cmdPtr = writeArgsToStack(stack, cmd, args);
		auto f = popen(cmdPtr, "r");
		if (f is null)
			throw new CmdException(
				cmd, args, "Failed to launch the program");

		size = cast(size_t)fread(stack.ptr, 1, stack.length, f);
		if (size == stack.length)
			throw new CmdException(
				cmd, args, "To much data to read");

	} else {
		static assert(false);
	}

	ret = stack[0 .. size].idup;

	return ret;
}

/**
 * Writes command and args to the given stack allocation
 * and also writes a trailing 0.
 */
char* writeArgsToStack(char[] stack, string cmd, string[] args)
{
	size_t pos;

	void add(string c) {
		if (pos + c.length > stack.length)
			throw new CmdException(cmd, args, "Command line to long");
		stack[pos .. pos + c.length] = c;
		pos += c.length;
	}

	if (cmd[0] != '"') {
		add("\"");
		add(cmd);
		add("\"");
	} else {
		add(cmd);
	}

	foreach(a; args) {
		add(" ");
		add(a);
	}

	add("\0");

	return stack.ptr;
}

/**
 * Helper class to launch one or more processes
 * to run along side the main process.
 */
class CmdGroup
{
public:
	alias void delegate() DoneDg;

private:
	/// Number of simultanious jobs.
	uint maxWaiting;

	/**
	 * Small container representing a executed command, is recycled.
	 */
	class Cmd
	{
	public:
		/// In use.
		bool used;

		/// Executable.
		string cmd;

		/// Arguments to be passed.
		string[] args;

		/// Called when command has completed.
		DoneDg done;

	public:
		/**
		 * Initialize all the fields.
		 */
		void set(string cmd, string[] args, DoneDg dg)
		{
			used = true;
			this.cmd = cmd;
			this.args = args;
			this.done = dg;
		}

		/**
		 * Reset to a unused state.
		 */
		void reset()
		{
			used = false;
			cmd = null;
			args = null;
			done = null;
		}
	}

	Cmd[] cmdStore;

	version(Windows) {
		Cmd[HANDLE] waiting;
	} else version(Posix) {
		Cmd[pid_t] waiting;
	} else {
		static assert(false);
	}


public:
	this()
	{
		// Be more clever about this.
		maxWaiting = 9;

		cmdStore.length = maxWaiting;
		foreach(ref c; cmdStore)
			c = new Cmd();
	}

	void run(string cmd, string[] args, DoneDg dg)
	{
		version(Windows) {

			auto hProcess = _createProcess(cmd, args);

			waiting[hProcess] = newCmd(cmd, args, dg);

		} else version(Posix) {

			pid_t pid = fork();

			// Child, does not return.
			if (!pid)
				_execvp(cmd, args);

			waiting[pid] = newCmd(cmd, args, dg);

		} else {
			static assert(false);
		}

		if (waiting.length >= maxWaiting)
			waitOne();
	}

	void waitOne()
	{
		version(Windows) {

			uint uRet;
			bool bRet;
			auto keys = waiting.keys;
			auto ptr = cast(HANDLE*)keys.ptr;
			auto hCount = cast(uint)keys.length;

			// The code assumes this, so check for it.
			static assert(WAIT_OBJECT_0 == 0);

			uRet = WaitForMultipleObjects(hCount, ptr, false, -1);
			if (uRet < 0 && uRet >= hCount)
				throw new Exception("Wait failed");

			auto hProcess = cast(HANDLE)keys[uRet];
			keys = null;

			scope(exit)
				CloseHandle(hProcess);

			auto c = waiting[hProcess];
			waiting.remove(hProcess);

			// Need to use the done field
			scope(failure)
				c.reset();

			int result = -1;
			bRet = GetExitCodeProcess(hProcess, cast(uint*)&result);
			if (!bRet)
				throw new CmdException(c.cmd, c.args,
					"abnormal application termination");

		} else version(Posix) {

			int status, result;
			pid_t pid;

			if (waiting.length <= 0)
				return;

			// Because stopped processes doesn't count.
			while(true) {
				pid = waitpid(-1, &status, 0);

				if (exited(status))
					result = exitstatus(status);
				else if (signaled(status))
					result = -termsig(status);
				else if (stopped(status))
					continue;
				else
					result = errno();

				if ((pid in waiting) is null)
					continue;

				break;
			}

			auto c = waiting[pid];
			waiting.remove(pid);

			// Windows version needs this a bit earlier.
			scope(failure)
				c.reset();

		} else {
			static assert(false);
		}

		// Common code.
		if (result != 0)
			throw new CmdException(c.cmd, c.args, result);

		// But also reset it before calling the dg
		auto dg = c.done;

		c.reset();

		if (dg !is null)
			dg();
	}

	void waitAll()
	{
		while(waiting.length > 0)
			waitOne();
	}

private:
	Cmd newCmd(string cmd, string[] args, DoneDg dg)
	{
		foreach(c; cmdStore) {
			if (!c.used) {
				c.set(cmd, args, dg);
				return c;
			}
		}
		debug
			assert(false);
		else
			throw new Exception("assert");
	}
}

/**
 * Exception form and when execquting commands.
 */
class CmdException : Exception
{
	this(string cmd, string reason)
	{
		super("The below command failed due to: " ~ reason ~ "\n" ~ cmd);
	}

	this(string cmd, string[] args, string reason)
	{
		foreach(a; args)
			cmd ~= " " ~ a;
		this(cmd, reason);
	}

	this(string cmd, int result)
	{
		super(format(
			"The below command returned: %s \n%s",
			result, cmd));
	}

	this(string cmd, string[] args, int result)
	{
		foreach(a; args)
			cmd ~= " " ~ a;
		this(cmd, result);
	}
}


private:

version(Windows) {

	/**
	 * Works kind of like CreateProcess, only greatly simplified.
	 *
	 * And easier to use.
	 * Throws CmdException if it fails to launch the process.
	 */
	HANDLE _createProcess(string cmd, string[] args)
	{
		bool bRet;
		uint uRet;
		STARTUPINFO si;
		PROCESS_INFORMATION pi;

		char[1024*32] stack;
		auto cmdPtr = writeArgsToStack(stack, cmd, args);

		si.cb = cast(uint)si.sizeof;

		bRet = CreateProcessA(
			null,
			cmdPtr,
			null,
			null,
			false,
			0,
			null,
			null,
			&si,
			&pi);

		if (!bRet)
			throw new CmdException(cmd, args, "failed to start program");

		// Not interested in this.
		CloseHandle(pi.hThread);

		return pi.hProcess;
	}

	const uint STARTF_USESTDHANDLES = 0x00000100;
	const uint HANDLE_FLAG_INHERIT = 0x00000001;

	struct STARTUPINFO {
		uint  cb;
		void* lpReserved;
		void* lpDesktop;
		void* lpTitle;
		uint  dwX;
		uint  dwY;
		uint  dwXSize;
		uint  dwYSize;
		uint  dwXCountChars;
		uint  dwYCountChars;
		uint  dwFillAttribute;
		uint  dwFlags;
		short wShowWindow;
		short cbReserved2;
		void* lpReserved2;
		HANDLE hStdInput;
		HANDLE hStdOutput;
		HANDLE hStdError;
	}

	struct PROCESS_INFORMATION {
		HANDLE hProcess;
		HANDLE hThread;
		uint dwProcessId;
		uint dwThreadId;
	}

	extern(System) BOOL SetHandleInformation(
		HANDLE hObject,
		uint dwMask,
		uint dwFlags
	);

	extern(System) BOOL CreatePipe(
		HANDLE* hReadPipe,
		HANDLE* hWritePipe,
		LPSECURITY_ATTRIBUTES lpPipeAttributes,
		uint nSize
	);

	extern(System) bool CreateProcessA(
		const(char)* lpApplicationName,
		const(char)* lpCommandLine,
		void* lpProcessAttributes,
		void* lpThreadAttributes,
		bool bInheritHandles,
		uint dwCreationFlags,
		void* lpEnvironment,
		void* lpCurrentDirectory,
		STARTUPINFO* lpStartupInfo,
		PROCESS_INFORMATION* lpProcessInformation
	);

	extern(System) bool GetExitCodeProcess(
		HANDLE hHandle,
		uint* lpDword
	);

} else version(Posix) {

	void _execvp(string cmd, string[] args)
	{
		char[1024*32] data = void;
		char*[1024*8] argv = void;
		size_t pos;
		int i;

		char* add(string a) {
			auto ret = sformat(data[pos .. $], "%s\0", a);
			pos += ret.length;
			return ret.ptr;
		}

		argv[i++] = add(cmd);
		foreach(a; args)
			argv[i++] = add(a);
		argv[i] = null;

		execvp(argv[0], &argv[0]);
		exit(-1);
	}

	bool stopped(int status)  { return (status & 0xff) == 0x7f; }
	bool signaled(int status) { return ((((status & 0x7f) + 1) & 0xff) >> 1) > 0; }
	bool exited(int status)   { return (status & 0x7f) == 0; }

	int termsig(int status)    { return status & 0x7f; }
	int exitstatus(int status) { return (status & 0xff00) >> 8; }

} else {
	static assert(false);
}

///
module imap.system;

import core.sys.linux.termios;
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.errno;
import imap.sil : SILdoc;

///
termios getTerminalAttributes()
{
	import std.exception : enforce;
	import std.format : format;
	import std.string : fromStringz;
	termios t;
	enforce(tcgetattr(fileno(stdin), &t)==0, format!"getting terminal attributes: %s"(strerror(errno).fromStringz));
	return t;
}

///
void setTerminalAttributes(termios terminalAttributes, int optionalActions = TCSAFLUSH)
{
	import std.exception : enforce;
	import std.string : fromStringz;
	import std.format : format;
	enforce(tcsetattr(fileno(stdin), optionalActions, &terminalAttributes) ==0,
			format!"setting term attributes; %s\n"(strerror(errno).fromStringz));
}

@SILdoc("Enable character echoing.")
void enableEcho()
{
	termios t = getTerminalAttributes();
	t.c_lflag |= (ECHO);
	t.c_lflag &= ~(ECHONL);
	t.setTerminalAttributes(TCSAFLUSH);
}

@SILdoc("Enable character echoing.")
void disableEcho()
{
	termios t = getTerminalAttributes();
	t.c_lflag &= ~(ECHO);
	t.c_lflag |= (ECHONL);
	t.setTerminalAttributes(TCSAFLUSH);
}


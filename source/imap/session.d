///
module imap.session;
import imap.defines;
import imap.socket;

import core.stdc.stdio;
import core.stdc.string;
import core.stdc.errno;
import std.socket;
import core.time : Duration;

import deimos.openssl.ssl;
import deimos.openssl.err;
import deimos.openssl.sha;


struct SSL_
{
	SSL* handle;
	alias handle this;
}

///
struct Set(T)
{
	bool[T] values_;
	alias values_ this;

	bool has(T value)
	{
		return (value in values_) !is null;
	}

	T[] values()
	{
		import std.algorithm : filter, map;
		import std.array : array;
		import std.conv : to;
		return values_.keys.filter!(c => values_[c])
				.array;
	}
}

///
Set!T add(T)(Set!T set, T value)
{
	import std.algorithm : each;
	Set!T ret;
	set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
	ret.values_[value] = true;
	return ret;
}

///
Set!T remove(T)(Set!T set, T value)
{
	import std.algorithm : each;
	Set!T ret;
	set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
	ret.remove(value);
	return ret;
}

///
struct ImapServer
{
	string server = "imap.fastmail.com"; // localhost";
	string port = "993";
}

///
struct  ImapLogin
{
	string username = "laeeth@kaleidic.io";
	string password;
}

///
struct Options
{
	import core.time : Duration, seconds, minutes;

	bool debugMode = true;
	bool verboseOutput = false;
	bool interactive = false;
	bool namespace = false;
	bool cramMD5 = false;
	bool startTLS = false;
	bool tryCreate = false;
	bool recoverAll = true;
	bool recoverErrors = true;
	bool expunge = false;
	bool subscribe = false;
	bool wakeOnAny = true;
	Duration keepAlive = 60.minutes;
	string logFile;
	string configFile;
	string oneline;
	string trustStore = "/etc/ssl/certs";
	string trustFile = "/etc/ssl/certs/cert.pem";
	Duration timeout = 20.seconds;
}

///
struct Session
{
	import imap.defines : ImapStatus;
	import imap.namespace;
	Options options;
	ImapStatus status_;
	string server;
	string port;
	package AddressInfo addressInfo;
	string username;
	string password;
	Socket socket;
	ImapProtocol imapProtocol;
	Set!Capability capabilities;
	string namespacePrefix;
	char namespaceDelim = '\0';
	Mailbox selected;

	bool useSSL = true;
	bool noCerts = true;
	ProtocolSSL sslProtocol = ProtocolSSL.ssl3; // tls1_2;
	SSL* sslConnection;
	SSL_CTX* sslContext;

	this(ImapServer imapServer,ImapLogin imapLogin)
	{
		import std.exception : enforce;
		import std.process : environment;
		this.server = imapServer.server;
		this.port = imapServer.port;
		this.username = imapLogin.username;
		this.password = environment.get("IMAP_PASS",""); //imapLogin.password;
	}

	ref Session setSelected(Mailbox mailbox)
	{
		this.selected = mailbox;
		return this;
	}

	ref Session setStatus(ImapStatus status)
	{
		this.status_ = status;
		return this;
	}

	string status()
	{
		import std.conv : to;
		return status_.to!string;
	}
}


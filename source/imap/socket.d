module imap.socket;
version(SIL) import kaleidic.sil.lang.handlers : Handlers;
import imap.defines;

import core.stdc.stdio;
import core.stdc.string;
import core.stdc.errno;
import std.socket;
import core.time : Duration;

import deimos.openssl.ssl;
import deimos.openssl.err;
import deimos.openssl.sha;

version(SIL)
{
	void registerGrammar(ref Handlers handlers)
	{
		import pegged.grammar;
		import imap.grammar;
		handlers.registerHandler!parse;
		handlers.registerHandler!parseTest;
		handlers.registerType!ParseTree;
	}

	enum TestImap=`
	* 51235 EXISTS
	* 0 RECENT
	* FLAGS (\Answered \Flagged \Draft \Deleted \Seen $X-ME-Annot-2 $IsMailingList $IsNotification $HasAttachment $HasTD $IsTrusted Recent $NotJunk $client $kaleidic $Forwarded $has_cal Junk $nina $personal $symmetry $sym/feng $contacts $contacts/mf $research/macro $research NonJunk $Junk)
	* OK [PERMANENTFLAGS (\Answered \Flagged \Draft \Deleted \Seen $X-ME-Annot-2 $IsMailingList $IsNotification $HasAttachment $HasTD $IsTrusted Recent $NotJunk $client $kaleidic $Forwarded $has_cal Junk $nina $personal $symmetry $sym/feng $contacts $contacts/mf $research/macro $research NonJunk $Junk \*)] Ok
	* OK [UNSEEN 7] Ok
	* OK [UIDVALIDITY 1484418500] Ok
	* OK [UIDNEXT 70481] Ok
	* OK [HIGHESTMODSEQ 10835882] Ok
	* OK [URLMECH INTERNAL] Ok
	* OK [ANNOTATIONS 65536] Ok
	D1004 OK [READ-WRITE] Completed
	`;

	auto parseTest()
	{
		import imap.grammar;
		import std.stdio;
		auto results = Imap(TestImap);
		writeln(results);
		results = results.tee;
		writeln(results);
		return results;
	}


	auto parse(string arg)
	{
		import imap.grammar;
		return Imap(arg).tee;
	}


	void registerImap(ref Handlers handlers)
	{
		import imap.system;
		import imap.request;
		import imap.response;
		import imap.namespace;
		import core.sys.linux.termios;
		import std.meta : AliasSeq;
		import imap.ssl;
		import deimos.openssl.ssl;
		import deimos.openssl.err;
		import deimos.openssl.x509;
		import deimos.openssl.pem;
		import deimos.openssl.evp;
		import std.stdio : File;

		handlers.openModule("imap");
		scope(exit) handlers.closeModule();
		handlers.registerGrammar();
		/+
			SSL_library_init();
			OpenSSL_add_all_algorithms();	
			OpenSSL_add_all_ciphers();
			OpenSSL_add_all_digests();
			SSL_load_error_strings();
			//SSL_load_crypto_strings();
		+/
		static foreach(T; AliasSeq!( Session, AddressInfo, Socket,termios,ProtocolSSL,ImapServer,ImapLogin))
			handlers.registerType!T;

		handlers.registerType!(Set!Capability)("Capabilities");
		handlers.registerHandler!(add!Capability)("addCapability");
		handlers.registerHandler!(remove!Capability)("removeCapability");

		static foreach(F; AliasSeq!(openConnection,closeConnection,socketRead,socketWrite,
						getTerminalAttributes,setTerminalAttributes,enableEcho,disableEcho,
						socketSecureRead,socketSecureWrite,closeSecureConnection,openSecureConnection,
		))
			handlers.registerHandler!F;

		// static int tag = 0x1000;

		static foreach(F; AliasSeq!(isLoginRequest, sendRequest, sendContinuation,noop,login,logout))
			handlers.registerHandler!F;

		static foreach(T; AliasSeq!(MailboxImapStatus, MailboxList,Mailbox,ImapResult,ImapStatus,Result!string,
					Status, FlagResult,SearchResult,
		))
			handlers.registerType!T;

		static foreach(F; AliasSeq!(select,close,expunge,list,lsub,search,fetchFast,fetchFlags,fetchDate,fetchSize,
					fetchStructure, fetchHeader,fetchText,fetchFields,fetchPart,logout,store,copy,create,
					delete_,rename,subscribe,unsubscribe, idle,))
			handlers.registerHandler!F;

		version(None)
		{
			static foreach(T; AliasSeq!(MailboxImapStatus, MailboxList))
				handlers.registerType!T;

			static foreach(F; AliasSeq!(status, append))
				handlers.registerHandler!F;
		}

		handlers.closeModule();

		handlers.openModule("ssl");
		static foreach(F; AliasSeq!(getPeerCertificate, getCert, checkCert, readX509,
					getDigest,getIssuerName,getSubject,asHex,printCert,getSerial,storeCert,
					getFilePath,
	))
		handlers.registerHandler!F;
		static foreach(T; AliasSeq!(Status, File,EVP_MD,X509,SSL_))
			handlers.registerType!T;
	}
}

struct SSL_
{
	SSL* handle;
	alias handle this;
}

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

Set!T add(T)(Set!T set, T value)
{
	import std.algorithm : each;
	Set!T ret;
	set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
	ret.values_[value] = true;
	return ret;
}

Set!T remove(T)(Set!T set, T value)
{
	import std.algorithm : each;
	Set!T ret;
	set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
	ret.remove(value);
	return ret;
}

struct ImapServer
{
	string server = "imap.fastmail.com"; // localhost";
	string port = "993";
}

struct  ImapLogin
{
	string username = "laeeth@kaleidic.io";
	string password;
}

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

extern(C) @nogc nothrow
{
	SSL_METHOD *TLS_method();
	SSL_METHOD *TLS_server_method();
	SSL_METHOD *TLS_client_method();
}

SSL_CTX* getContext(string caFile, string caPath, string certificateFile, string keyFile, bool asServer = false)
{
	import std.exception : enforce;
	import std.string : toStringz;
	import std.format : format;
	SSL_CTX* ret = SSL_CTX_new(asServer ? TLS_server_method() : TLS_client_method());
	enforce(ret !is null, "unable to create new SSL context");
	enforce(SSL_CTX_set_default_verify_paths(ret) == 1, "unable to set context default verify paths");
	if (caFile.length > 0 || caPath.length > 0)
		enforce(SSL_CTX_load_verify_locations(ret,caFile.toStringz,caPath.toStringz), "unable to load context verify locations");
	SSL_CTX_set_verify(ret,0,null);
	if(certificateFile.length > 0)
	{
		enforce(SSL_CTX_use_certificate_file(ret,certificateFile.toStringz, SSL_FILETYPE_PEM) > 0,
			format!"unable to set SSL certificate file as PEM to %s"(certificateFile));
	}
	if (keyFile.length > 0)
	{
		enforce(SSL_CTX_use_certificate_file(ret,keyFile.toStringz, SSL_FILETYPE_PEM) > 0,
			format!"unable to set SSL key file as PEM to %s"(keyFile));
	}
	//enforce(SSL_CTX_check_private_key(ret) > 0, "check private key failed");
	return ret;
}


//	Connect to mail server.
Session openConnection(ref Session session)
{
	import std.format : format;
	import std.exception : enforce;
	import std.range : front;
	auto addressInfos = getAddressInfo(session.server, session.port);
	enforce(addressInfos.length >=0, format!"unable to get address info for %s:%s"(session.server,session.port));
	session.addressInfo = addressInfos.front;
	// just use first address

	session.socket = new TcpSocket();
	session.socket.blocking(true);
	session.socket.connect(session.addressInfo.address);
	session.socket.blocking(false);
	enforce(session.socket.isAlive(), format!"connecting to %s:%s failed"(session.server, session.port));
	if (session.useSSL)
		return openSecureConnection(session);
	return session;
}

enum ProtocolSSL
{
	none,
	ssl3,
	tls1,
	tls1_1,
	tls1_2,
}

//	Initialize SSL/TLS connection.
ref Session openSecureConnection(ref Session session)
{
	import std.exception : enforce;
	import imap.ssl;
	int r;
	enforce(session.socket.isAlive, "trying to secure a disconnected socket");
	session.sslContext = getContext("/etc/ssl/cert.pem","/etc/ssl",null,null,false); // "cacert.pem","/etc/pki/CA",null,null,false);
	enforce(session.sslContext !is null, "unable to create new SSL context");
	session.sslConnection = SSL_new(session.sslContext);
	enforce(session.sslConnection !is null, "unable to create new SSL connection");
	enforce(session.socket.isAlive, "trying to secure a disconnected socket");
	SSL_set_fd(session.sslConnection, session.socket.handle);
	scope(failure)
		session.sslConnection = null;
	r = SSL_connect(session.sslConnection);
	if (isSSLError(r))
	{
		auto message = sslConnectionError(session,r);
		throw new Exception(message);
	}
	if(!session.noCerts)
	   getCert(session);
	return session;
}

bool isSSLError(int socketStatus)
{
	switch(socketStatus)
	{
			case 	SSL_ERROR_NONE,
					SSL_ERROR_WANT_CONNECT,
					SSL_ERROR_WANT_ACCEPT,
					SSL_ERROR_WANT_X509_LOOKUP,
					SSL_ERROR_WANT_READ,
					SSL_ERROR_WANT_WRITE:
						return false;

			case 	SSL_ERROR_SYSCALL,
					SSL_ERROR_ZERO_RETURN,
					SSL_ERROR_SSL:
						return true;

		default:
					return false;
	}
	assert(0);
}
string sslConnectionError(ref Session session, int socketStatus)
{
	import std.format : format;
	import std.string : fromStringz;
	auto result = SSL_get_error(session.sslConnection, socketStatus);
	switch(result)
	{
		case SSL_ERROR_SYSCALL:
			return format!"initiating SSL connection to %s; %s" ( session.server, sslConnectionSysCallError(result));

		case SSL_ERROR_ZERO_RETURN:
			return format!"initiating SSL connection to %s; connection has been closed cleanly"(session.server);

		case SSL_ERROR_SSL:
			return format!"initiating SSL connection to %s; %s\n"(session.server, ERR_error_string(ERR_get_error(), null).fromStringz);

			case 	SSL_ERROR_NONE,
					SSL_ERROR_WANT_CONNECT,
					SSL_ERROR_WANT_ACCEPT,
					SSL_ERROR_WANT_X509_LOOKUP,
					SSL_ERROR_WANT_READ,
					SSL_ERROR_WANT_WRITE:
						break;
		default:
			return "";
	}
	assert(0);
}

private string sslConnectionSysCallError(int socketStatus)
{
	import std.string : fromStringz;
	import std.format : format;
	auto e = ERR_get_error();
	if (e == 0 && socketStatus ==0)
		return format!"EOF in violation of the protocol";
	else if (e == 0 && socketStatus == -1)
		return strerror(errno).fromStringz.idup;
	return ERR_error_string(e, null).fromStringz.idup;
}

// Disconnect from mail server.
void closeConnection(ref Session session)
{
	version(SSL) closeSecureConnection(session);
	if (session.socket.isAlive)
	{
		session.socket.close();
	}
}

//	Shutdown SSL/TLS connection.
int closeSecureConnection(ref Session session)
{
	if (session.sslConnection)
	{
		SSL_shutdown(session.sslConnection);
		SSL_free(session.sslConnection);
		session.sslConnection = null;
	}

	return 0;
}

enum Status
{
	success,
	failure,
}

struct Result(T)
{
	Status status;
	T value;
}


auto result(T)(Status status, T value)
{
	return Result!T(status,value);
}

// Read data from socket.
Result!string socketRead(ref Session session, Duration timeout, bool timeoutFail = true)
{
	import std.experimental.logger : tracef;
	import std.exception : enforce;
	import std.format : format;
	import std.string : fromStringz;
	import std.conv : to;
	auto buf = new char[16384];
	
	int s;
	ssize_t r;

	r = 0;
	s = 1;

	scope(failure)
		closeConnection(session);

	auto socketSet = new SocketSet(1);
	socketSet.add(session.socket);
	auto selectResult = Socket.select(socketSet,null,null,timeout);
	if (session.sslConnection)
	{
		if (SSL_pending(session.sslConnection) > 0 || selectResult > 0)
		{
			r = SSL_read(session.sslConnection, cast(void*) buf.ptr, buf.length.to!int);
			enforce(r > 0, "error reading socket");
		}
	}
	if (!session.sslConnection)
	{
		if (selectResult > 0)
		{
			r = session.socket.receive(cast(void[])buf);

			enforce(r != -1, format!"reading data; %s"(strerror(errno).fromStringz));
			enforce(r != 0, "read returned no data");
		}
	}

	enforce(s != -1, format!"waiting to read from socket; %s"(strerror(errno).fromStringz));
	enforce (s != 0 || !timeoutFail, "timeout period expired while waiting to read data");
	tracef("socketRead: %s / %s",session.socket,buf);
	return result(Status.success,cast(string)buf);
}

bool isSSLReadError(ref Session session, int status)
{
	switch(SSL_get_error(session.sslConnection,status))
	{
		case SSL_ERROR_ZERO_RETURN,
			 SSL_ERROR_SYSCALL,
			 SSL_ERROR_SSL:
				 return true;

		case SSL_ERROR_NONE:
		case SSL_ERROR_WANT_READ:
		case SSL_ERROR_WANT_WRITE:
		case SSL_ERROR_WANT_CONNECT:
		case SSL_ERROR_WANT_ACCEPT:
		case SSL_ERROR_WANT_X509_LOOKUP:
				return false;
		
		default:
				return false;
	}
	assert(0);
}

bool isTryAgain(ref Session session, int status)
{
	if (status > 0)
		return false;
	if (session.isSSLReadError(status))
		return false;

	switch(status)
	{
		case SSL_ERROR_NONE:
		case SSL_ERROR_WANT_READ:
		case SSL_ERROR_WANT_WRITE:
		case SSL_ERROR_WANT_CONNECT:
		case SSL_ERROR_WANT_ACCEPT:
		case SSL_ERROR_WANT_X509_LOOKUP:
			return true;

		default:
			return true;
	}
}

// Read data from a TLS/SSL connection.
Result!string socketSecureRead(ref Session session)
{
	import std.experimental.logger : tracef;
	import std.exception : enforce;
	import std.conv : to;
	import std.format : format;
	import std.stdio: writefln,stderr;
	int res;
	auto buf = new char[16384*1024];
	scope(failure)
		SSL_set_shutdown(session.sslConnection, SSL_SENT_SHUTDOWN | SSL_RECEIVED_SHUTDOWN);
	do
	{
		res = SSL_read(session.sslConnection, cast(void*)buf.ptr, buf.length.to!int);
		enforce(!session.isSSLReadError(res), session.sslReadErrorMessage(res));
	} while(session.isTryAgain(res));
	enforce(res >0, format!"SSL_read returned %s and expecting a positive number of bytes"(res));
	tracef("socketSecureRead: %s / %s",session.socket,buf[0..res]);
	stderr.writefln("socketSecureRead: %s / %s",session.socket,buf[0..res]);
	return result(Status.success,buf[0..res].idup);
}

string sslReadErrorMessage(ref Session session, int status)
{
	import std.format : format;
	import std.string : fromStringz;
	import std.exception : enforce;
	enforce(session.isSSLReadError(status),"ssl error that is not an error!");
	switch (SSL_get_error(session.sslConnection, status))
	{
		case SSL_ERROR_ZERO_RETURN:
			return "reading data through SSL; the connection has been closed cleanly";

		case SSL_ERROR_SSL:
			return format!"reading data through SSL; %s\n"(ERR_error_string(ERR_get_error(), null).fromStringz);

		case SSL_ERROR_SYSCALL:
			auto e = ERR_get_error();
			if (e == 0 && status == 0)
				return "reading data through SSL; EOF in violation of the protocol";
			else if (e == 0 && status == -1)
				return format!"reading data through SSL; %s"(strerror(errno).fromStringz);
			else
				return format!"reading data through SSL; %s"(ERR_error_string(e, null).fromStringz);
		default:
			return "";
	}
	assert(0);
}

// Write data to socket.
ssize_t socketWrite(ref Session session, string buf)
{
	import std.experimental.logger : tracef;
	import std.exception : enforce;
	import std.format : format;
	import std.string : fromStringz;
	import std.conv : to;
	int s;
	ssize_t r, t;

	r = t = 0;
	s = 1;
	
	tracef("socketWrite: %s / %s",session.socket,buf);

	scope(failure)
		closeConnection(session);

	auto socketSet = new SocketSet(1);
	socketSet.add(session.socket);

	while(buf.length > 0)
	{
		s = Socket.select(socketSet,null,null,null);
		if (s> 0)
		{
			version(SSL)
			{
				if (session.sslConnection) {
					r = SSL_write(session.sslConnection, cast(const(void)*) buf.ptr, buf.length.to!int);
					enforce(r>0, "error writing to ssl socket");
				}
			}
			if (!session.sslConnection)
			{
				r = session.socket.send(cast(void[])buf);
				enforce(r != -1, format!"writing data; %s"(strerror(errno).fromStringz));
				enforce(r !=0, "unknown error");
			}

			if (r > 0) {
				enforce(r <= buf.length, "send to socket returned more bytes than we sent!");
				buf = buf[r .. $];
				t += r;
			}
		}
	}

	enforce(s != -1, format!"waiting to write to socket; %s"(strerror(errno).fromStringz));
	enforce(s != 0, "timeout period expired while waiting to write data");

	return t;
}

// Write data to a TLS/SSL connection.
auto socketSecureWrite(ref Session session, string buf)
{
	import std.experimental.logger : tracef;
	import std.string : fromStringz;
	import std.format : format;
	import std.conv : to;
	import std.exception : enforce;
	int r;
	size_t e;

	tracef("socketSecureWrite: %s / %s",session.socket,buf);
	enforce(session.sslConnection, "no SSL connection has been established");
	if (buf.length ==0)
		return 0;
	while(true)
	{
		if ((r = SSL_write(session.sslConnection, buf.ptr, buf.length.to!int)) > 0)
			break;
	
		scope(failure)
			SSL_set_shutdown(session.sslConnection, SSL_SENT_SHUTDOWN | SSL_RECEIVED_SHUTDOWN);

		switch (SSL_get_error(session.sslConnection, r))
		{
			case SSL_ERROR_ZERO_RETURN:
				throw new Exception("writing data through SSL; the connection has been closed cleanly");
			case SSL_ERROR_NONE:
			case SSL_ERROR_WANT_READ:
			case SSL_ERROR_WANT_WRITE:
			case SSL_ERROR_WANT_CONNECT:
			case SSL_ERROR_WANT_ACCEPT:
			case SSL_ERROR_WANT_X509_LOOKUP:
				break;
			case SSL_ERROR_SYSCALL:
				e = ERR_get_error();
				if (e == 0 && r == 0)
					throw new Exception("writing data through SSL; EOF in violation of the protocol");
				enforce( !(e==0 && r == -1),format!"writing data through SSL; %s\n"(strerror(errno).fromStringz.idup));
				enforce(true,format!"writing data through SSL; %s"(ERR_error_string(e, null).fromStringz.idup));
				break;
			case SSL_ERROR_SSL:
				enforce(true,format!"writing data through SSL; %s"(ERR_error_string(ERR_get_error(), null).fromStringz.idup));
				break;
			default:
				break;
		}
	}
	return r;
}


///
module kaleidic.sil.std.extra.imap.register;

version(SIL):

import kaleidic.sil.lang.handlers:Handlers;
import kaleidic.sil.lang.types : Variable,Function,SILdoc;
import std.meta:AliasSeq;
import imap.set;

version (SIL_Plugin)
{
	import kaleidic.sil.lang.plugin : pluginImpl;
	mixin pluginImpl!registerImap;
}


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
import arsd.email : MimeContainer;

///
void registerGrammar(ref Handlers handlers)
{
	import pegged.grammar;
	import imap.grammar;
	handlers.registerHandler!parse;
	handlers.registerHandler!parseTest;
	// handlers.registerType!ParseTree;
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


void writeBinary(string file, string data)
{
	import std.file;
	write(file,data);
}

struct X509_
{
	import deimos.openssl.x509;
    X509* handle;
}

struct MimeContainer_
{
    MimeContainer h;
    string contentType() { return h._contentType; }
    string boundary() { return h.boundary; }
    string[] headers() { return h.headers; }
    string content() {return h.content; }

    MimeContainer_[] stuff()
    {
        import std.algorithm : map;
        import std.array : array;
        return h.stuff.map!(s => MimeContainer_(s)).array;
    }

    this(MimeContainer h)
    {
        this.h = h;
    }
}

MimeContainer_ accessMimeContainer(MimeContainer mimeContainer)
{
    return MimeContainer_(mimeContainer);
}

///
void registerImap(ref Handlers handlers)
{
	import imap.session;
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
	import arsd.email : IncomingEmailMessage,RelayInfo,ToType,EmailMessage,MimePart;
	import std.process : pipeProcess, ProcessPipes, Redirect;
	//import std.file: wait, flush, close;
	import std.stdio : writeln, File;
	{
		handlers.openModule("imap");
		scope(exit) handlers.closeModule();
		handlers.registerGrammar();

		static foreach(T; AliasSeq!(MailboxImapStatus, MailboxList,Mailbox,ImapResult,ImapStatus,Result!string,
				Status, FlagResult,SearchResult,Status,Session,ProtocolSSL, ImapServer, ImapLogin,
				MailboxImapStatus, MailboxList,Mailbox,ImapResult,ImapStatus,Result!string,
				Status, FlagResult,SearchResult,Status,StatusResult,BodyResponse,
				IncomingEmailMessage,RelayInfo,ToType,EmailMessage,MimePart,MimeContainer_,MimePart,
				MimeAttachment, // proxy from imap not arsd
		))
			handlers.registerType!T;

		handlers.registerType!ProcessPipes;
		handlers.registerHandler!((string processName) => pipeProcess(processName, Redirect.stdout | Redirect.stdin | Redirect.stderr))("pipeProcess");
		handlers.registerType!File;
		handlers.registerHandler!((string s) => writeln(s))("writeln");



		handlers.registerType!(Set!Capability)("Capabilities");

		// FIXME - finish and add append	
		static foreach(F; AliasSeq!(noop,login,logout,status,examine,select,close,expunge,list,lsub,
					search,fetchFast,fetchFlags,fetchDate,fetchSize, fetchStructure, fetchHeader,
					fetchText,fetchFields,fetchPart,logout,store,copy,create, delete_,rename,subscribe,
					unsubscribe, idle, openConnection, closeConnection,raw,fetchRFC822,attachments,writeBinary,
		))
			handlers.registerHandler!F;
	}
	{
		handlers.openModule("imap.impl");
		scope(exit) handlers.closeModule();
		static foreach(T; AliasSeq!( AddressInfo, Socket,termios,ImapServer,ImapLogin,File
		))
			handlers.registerType!T;
		handlers.registerHandler!(add!Capability)("addCapability");
		handlers.registerHandler!(remove!Capability)("removeCapability");

		static foreach(F; AliasSeq!(socketRead,socketWrite,
						getTerminalAttributes,setTerminalAttributes,enableEcho,disableEcho,
						socketSecureRead,socketSecureWrite,closeSecureConnection,openSecureConnection,
						isLoginRequest, sendRequest, sendContinuation, 
		))
			handlers.registerHandler!F;
	}

	// FIXME - add current tag as SIL vairable - static int tag = 0x1000;

	{
		handlers.openModule("ssl");
		scope(exit) handlers.closeModule();
		static foreach(F; AliasSeq!(getPeerCertificate, getCert, checkCert, readX509,
					getDigest,getIssuerName,getSubject,asHex,printCert,getSerial,storeCert,
					getFilePath,
		))
		handlers.registerHandler!F;
		static foreach(T; AliasSeq!(EVP_MD,SSL_))
			handlers.registerType!T;
        handlers.registerType!X509_("X509");
	}
}




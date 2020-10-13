///
module kaleidic.sil.plugin.imap.register;
import imap.set;
version(SIL):

import kaleidic.sil.lang.handlers:Handlers;
import kaleidic.sil.lang.types : Variable,Function,SILdoc;
import std.meta:AliasSeq;

version (SIL_Plugin)
{
	import kaleidic.sil.lang.plugin : pluginImpl;
	mixin pluginImpl!registerImap;
}


import imap.defines;
import imap.socket;
import imap.session : Session;

import core.stdc.stdio;
import core.stdc.string;
import core.stdc.errno;
import std.socket;
import core.time : Duration;
import std.datetime : Date, DateTime, SysTime, TimeZone;

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


void writeBinaryString(string file, string data)
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

	{
		handlers.openModule("dates");
		handlers.registerHandler!add;
		handlers.openModule("imap");
		scope(exit) handlers.closeModule();
		handlers.registerGrammar();
		     
		static foreach(T; AliasSeq!(MailboxImapStatus, MailboxList,Mailbox,ImapResult,ImapStatus,Result!string,
				Status, FlagResult,SearchResult,Status,Session,ProtocolSSL, ImapServer, ImapLogin,
				MailboxImapStatus, MailboxList,Mailbox,ImapResult,ImapStatus,Result!string,
				Status, FlagResult,SearchResult,Status,StatusResult,BodyResponse,ListResponse,ListEntry,
				IncomingEmailMessage,RelayInfo,ToType,EmailMessage,MimePart, Options,
				MimeContainer_,MimePart,
				MimeAttachment, SearchQuery, UidRange,SearchResultType,StoreMode // proxy from imap not arsd
		))
			handlers.registerType!T;

		handlers.registerType!(Set!Capability)("Capabilities");
		handlers.registerType!(Set!ulong)("UidSet");
	    handlers.registerType!SysTime;
		handlers.registerType!TimeZone;
		handlers.registerType!Duration;

		handlers.registerHandler!(addSet!ulong)("addUidSet");
		handlers.registerHandler!(removeSet!ulong)("removeUidSet");
		// FIXME - finish and add append	
		static foreach(F; AliasSeq!(noop,login,logout,status,examine,select,close,expunge,list,lsub,
					search,fetchFast,fetchFlags,fetchDate,fetchSize, fetchStructure, fetchHeader,
					fetchText,fetchFields,fetchPart,logout,store,copy,create, delete_,rename,subscribe,
					unsubscribe, idle, openConnection, closeConnection,raw,fetchRFC822,attachments,writeBinaryString,
					createQuery,searchQuery,searchQueries, rfcDate,esearch,multiSearch,move,multiMove,moveUIDs,
					extractAddress,
		))
			handlers.registerHandler!F;
		handlers.registerType!Socket;

		import jmap : registerHandlersJmap;
		handlers.registerHandlersJmap();
	}
	/+
	{
		handlers.openModule("imap.impl");
		scope(exit) handlers.closeModule();
		version(linux)
		{
			handlers.registerType!termios;
			handlers.registerHandler!getTerminalAttributes;
			handlers.registerHandler!setTerminalAttributes;
			handlers.registerHandler!enableEcho;
			handlers.registerHandler!disableEcho;
		}

		static foreach(T; AliasSeq!( AddressInfo, Socket,ImapServer,ImapLogin,File
		))
			handlers.registerType!T;
		handlers.registerHandler!(add!Capability)("addCapability");
		handlers.registerHandler!(remove!Capability)("removeCapability");
		handlers.registerHandler!(addSet!Capability)("addCapabilities");
		handlers.registerHandler!(removeSet!Capability)("removeCapabilities");

		static foreach(F; AliasSeq!(socketRead,socketWrite,
						getTerminalAttributes,setTerminalAttributes,enableEcho,disableEcho,
						socketSecureRead,socketSecureWrite,closeSecureConnection,openSecureConnection,
						isLoginRequest, sendRequest, sendContinuation, 
		))
			handlers.registerHandler!F;
	}
	+/
	// FIXME - add current tag as SIL vairable - static int tag = 0x1000;

	{
		handlers.openModule("ssl");
		scope(exit) handlers.closeModule();
/+		
		static foreach(F; AliasSeq!(getPeerCertificate, getCert, checkCert, readX509,
					getDigest,getIssuerName,getSubject,asHex,printCert,getSerial,storeCert,
					getFilePath,
		))
		handlers.registerHandler!F; +/
		static foreach(T; AliasSeq!(EVP_MD,SSL_))
			handlers.registerType!T;
        handlers.registerType!X509_("X509");
	}
}

struct UidRange
{
	long start = -1;
	long end = -1;

	string toString()
	{
		import std.string: format;
		import std.conv : to;

		return format!"%s:%s"(
				(start == -1 ) ? 0 : start,
				(end == -1) ? "*" : end.to!string
		);
	}
}

struct SearchQuery
{
	@SILdoc("not flag if applied inverts the whole query")
	@("NOT")
	bool not;

	ImapFlag[] flags;

	@("FROM")
	string fromContains;

	@("CC")
	string ccContains;

	@("BCC")
	string bccContains;

	@("TO")
	string toContains;

	@("SUBJECT")
	string subjectContains;

	@("BODY")
	string bodyContains;

	@("TEXT")
	string textContains;

	@("BEFORE")
	Date beforeDate;

	@("HEADER")
	string[string] headerFieldContains;

	@("KEYWORD")
	string[] hasKeyword;

	@("SMALLER")
	ulong smallerThanBytes;

	@("LARGER")
	ulong largerThanBytes;
	
	@("NEW")
	bool isNew;

	@("OLD")
	bool isOld;

	@("ON")
	Date onDate;

	@("SENTBEFORE")
	Date sentBefore;

	@("SENTON")
	Date sentOn;

	@("SENTSINCE")
	Date sentSince;

	@("SINCE")
	Date since;

	@("UID")
	ulong[] uniqueIdentifiers;

	@("UID")
	UidRange[] uniqueIdentifierRanges;

	string applyNot(string s)
	{
		import std.string : join;

		return not ? ("NOT " ~ s) : s;
	}

	template isSILdoc(alias T)
	{
		enum isSILdoc = is(typeof(T) == SILdoc);
	}

	void toString(scope void delegate(const(char)[]) sink)
	{
		import std.range : dropOne;
		import std.string : toUpper;
		import std.conv : to;
		import std.meta : Filter, templateNot;
		import std.traits : isFunction;
		foreach(flag;flags)
		{
			sink(applyNot(flag.to!string.dropOne.toUpper));
		}
		static foreach(M; Filter!(templateNot!isFunction,__traits(allMembers,typeof(this))))
		{{
			enum udas = Filter!(templateNot!isSILdoc,__traits(getAttributes, __traits(getMember,this,M)));
			static if(udas.length > 0)
			{
				alias T = typeof( __traits(getMember,this,M));
				enum name = udas[0].to!string;
				auto v = __traits(getMember,this,M);
				static if (is(T==string))
				{
					if (v.length > 0)
					{
						sink(applyNot(name));
						sink(" \"");
						sink(v);
						sink("\" ");
					}
				}
				else static if (is(T==Date))
				{
					if (v != Date.init)
					{
						sink(applyNot(name));
						sink(" ");
						sink(__traits(getMember,this,M).rfcDate);
						sink(" ");
					}
				}
				else static if (is(T==bool) && (name != "NOT"))
				{
					if (v)
					{
						sink(applyNot(name));
						sink(" ");
					}
				}
				else static if (is(T==string[string]))
				{
					foreach(entry;__traits(getMember,this,M).byKeyValue)
					{
						sink(applyNot(name));
						sink(" ");
						sink(entry.key);
						sink(" \"");
						sink(entry.value);
						sink("\" ");
					}
				}
				else static if (is(T==string[]))
				{
					foreach(entry;__traits(getMember,this,M))
					{
						sink(applyNot(name));
						sink(" \"");
						sink(entry);
						sink("\" ");
					}
				}
				else static if (is(T==ulong[]))
				{
					if (v.length > 0)
					{
						sink(applyNot(name));
						sink(" ");
						auto len = __traits(getMember,this,M).length;
						foreach(i,entry;__traits(getMember,this,M))
						{
							sink(entry.to!string);
							if (i != len-1)
								sink(",");
						}
						static if (name == "UID")
						{
							if (len > 0 && uniqueIdentifierRanges.length > 0)
								sink(",");
							len = uniqueIdentifierRanges.length;
							foreach(i,entry;uniqueIdentifierRanges)
							{
								sink(entry.to!string);
								if (i != len-1)
									sink(",");
							}
						}
					}
				}
			}
		}}
	}
}

@SILdoc(`Generate query string to serch the selected mailbox according to the supplied criteria.
This string may be passed to imap.search.

The searchQueries are ORed together.  There is an implicit AND within a searchQuery
For NOT, set not within the query to be true - this applies to all the conditions within
the query.
`)
string createQuery(SearchQuery[] searchQueries)
{
	import std.range : chain, repeat;
	import std.algorithm : map;
	import std.string : join, strip;
	import std.conv : to;

	if (searchQueries.length == 0)
		return "ALL";

	return chain("OR".repeat(searchQueries.length - 1),
				searchQueries.map!(q => q.to!string.strip)).join(" ").strip;
}

@SILdoc(`Search selected mailbox according to the supplied search criteria.
There is an implicit AND within a searchQuery. For NOT, set not within the query
to be true - this applies to all the conditions within the query.
`)
auto searchQuery(ref Session session, string mailbox, SearchQuery searchQuery, string charset = null)
{
	import imap.namespace : Mailbox;
	import imap.request;
	select(session,Mailbox(mailbox));
	return search(session,createQuery([searchQuery]),charset);
}

@SILdoc(`Search selected mailbox according to the supplied search criteria.
The searchQueries are ORed together.  There is an implicit AND within a searchQuery
For NOT, set not within the query to be true - this applies to all the conditions within
the query.
`)
auto searchQueries(ref Session session, string mailbox, SearchQuery[] searchQueries, string charset = null)
{
	import imap.namespace : Mailbox;
	import imap.request;
	select(session,Mailbox(mailbox));
	return search(session,createQuery(searchQueries),charset);
}

@SILdoc("Convert a SIL date to an RFC-2822 / IMAP Date string")
string rfcDate(Date date)
{
	import std.format : format;
	import std.conv : to;
	import std.string : capitalize;
	return format!"%02d-%s-%04d"(date.day,date.month.to!string.capitalize,date.year);
}

@SILdoc("Extract email address from sender/recipient eg Laeeth <laeeth@nospam-laeeth.com>")
string extractAddress(string arg)
{
	import std.string : indexOf;
	auto i = arg.indexOf("<");
	auto j = arg.indexOf(">");
	if  ((i == -1) || (j == -1) || (j <= i))
		return "";
	return arg[i+1 .. j];
}

Variable add(Variable date, Duration dur)
{
	return Variable(date.get!DateTime + dur);
}

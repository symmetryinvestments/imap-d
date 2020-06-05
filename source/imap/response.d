///
module imap.response;
import imap.defines;
import imap.socket;
import imap.session;
import imap.set;
import imap.sil : SILdoc;

import std.typecons : tuple;
import core.time : Duration;
import arsd.email : IncomingEmailMessage;
import core.time: msecs;


/**
  		TODO:
			- add optional response code when parsing statuses
*/

///
alias Tag = int;

///
enum ImapResponse
{
	tagged,
	untagged,
	capability,
	authenticate,
	namespace,
	status,
	statusMessages,
	statusRecent,
	statusUnseen,
	statusUidNext,
	exists,
	recent,
	list,
	search,
	fetch,
	fetchFlags,
	fetchDate,
	fetchSize,
	fetchStructure,
	fetchBody,
}


@SILdoc("Read data the server sent")
auto receiveResponse(ref Session session, Duration timeout = Duration.init, bool timeoutFail = false)
{
	timeout = (timeout == Duration.init) ? session.options.timeout : timeout;
	//auto result = session.socketSecureRead(); // timeout,timeoutFail);
	auto result = session.socketRead(timeout,timeoutFail);
	if (result.status != Status.success)
		return tuple(Status.failure,result.value.idup);
	auto buf = result.value;

	if (session.options.debugMode)
	{
		import std.experimental.logger : infof;
		infof("getting response (%s):", session.socket);
		infof("buf: %s",buf);
	}
	return tuple(Status.success,buf.idup);
}


@SILdoc("Search for tagged response in the data that the server sent.")
ImapStatus checkTag(ref Session session, string buf, Tag tag)
{
	import std.algorithm : all, map, filter;
	import std.ascii : isHexDigit, isWhite;
	import std.experimental.logger;
	import std.format : format;
	import std.string: splitLines, toUpper,strip, split, startsWith;
	import std.array : array;
	import std.range : front;

	if (session.options.debugMode) tracef("checking for tag %s in buf: %s",tag,buf);
	auto r = ImapStatus.none;
	auto t = format!"D%04X"(tag);
	if (session.options.debugMode) tracef("checking for tag %s in buf: %s",t,buf);
	auto lines = buf.splitLines.map!(line => line.strip).array;
	auto relevantLines = lines
							.filter!(line => line.startsWith(t))
									// && line[t.length].isWhite)
							.array;

	foreach(line;relevantLines)
	{
		auto token = line.toUpper[t.length+1..$].strip.split.front;
		if (token.startsWith("OK"))
		{
			r = ImapStatus.ok;
			break;
		}
		if (token.startsWith("NO"))
		{
			r = ImapStatus.no;
			break;
		}
		if (token.startsWith("BAD"))
		{
			r = ImapStatus.bad;
			break;
		}
	}
	
	if(session.options.debugMode) tracef("tag result is status %s for lines: %s",r,relevantLines);

	if (r != ImapStatus.none && session.options.debugMode)
		tracef("S (%s): %s / %s", session.socket, buf,relevantLines);

	if (r == ImapStatus.no || r == ImapStatus.bad)
		errorf("IMAP (%s): %s / %s", session.socket, buf, relevantLines);

	return r;
}


@SILdoc("Check if server sent a BYE response (connection is closed immediately).")
bool checkBye(string buf)
{
	import std.string : toUpper;
	import std.algorithm : canFind;
	buf = buf.toUpper;
	return (buf.canFind("* BYE") && !buf.canFind(" LOGOUT "));
}


@SILdoc("Check if server sent a PREAUTH response (connection already authenticated by external means).")
int checkPreAuth(string buf)
{
	import std.string : toUpper;
	import std.algorithm : canFind;
	buf = buf.toUpper;
	return (buf.canFind("* PREAUTH"));
}

@SILdoc("Check if the server sent a continuation request.")
bool checkContinuation(string buf)
{
	import std.string: startsWith;
	return (buf.length >2 && (buf[0] == '+' && buf[1] == ' '));
}


@SILdoc("Check if the server sent a TRYCREATE response.")
int checkTryCreate(string buf)
{
	import std.string : toUpper;
	import std.algorithm : canFind;
	return buf.toUpper.canFind("[TRYCREATE]");
}

///
struct ImapResult
{
	ImapStatus status;
	string value;
}

@SILdoc("Get server data and make sure there is a tagged response inside them.")
ImapResult responseGeneric(ref Session session, Tag tag, Duration timeout = 2000.msecs)
{
	import std.typecons: Tuple;
	import std.array : Appender;
    import core.time: msecs;
	import std.datetime : MonoTime;
	Tuple!(Status,string) result;
	Appender!string buf;
	ImapStatus r;

	if (tag == -1)
		return ImapResult(ImapStatus.unknown,"");

	MonoTime before = MonoTime.currTime();
	do
	{
		result = session.receiveResponse(timeout,false);
		if (result[0] == Status.failure)
			return ImapResult(ImapStatus.unknown,buf.data ~ result[1].idup);
		buf.put(result[1].idup);

		if (checkBye(result[1]))
			return ImapResult(ImapStatus.bye,buf.data);

		r = session.checkTag(result[1],tag);
	} while (r == ImapStatus.none);

	if (r == ImapStatus.no && (checkTryCreate(result[1]) || session.options.tryCreate))
		return ImapResult(ImapStatus.tryCreate,buf.data);

	return ImapResult(r,buf.data);
}


@SILdoc("Get server data and make sure there is a continuation response inside them.")
ImapResult responseContinuation(ref Session session, Tag tag)
{
	import std.algorithm : any;
	import std.string : strip, splitLines;

	string buf;
	//ImapStatus r;
	import std.typecons: Tuple;
	Tuple!(Status,string) result;
	ImapStatus resTag = ImapStatus.ok;
	do
	{
		result = session.receiveResponse(Duration.init,false);
		if (result[0] == Status.failure)
			break;
		// return ImapResult(ImapStatus.unknown,"");
		buf ~= result[1];

		if (checkBye(result[1]))
			return ImapResult(ImapStatus.bye,result[1]);
		resTag = session.checkTag(result[1],tag);
	} while ((resTag != ImapStatus.none) && !result[1].strip.splitLines.any!(line => line.strip.checkContinuation));

	if (resTag == ImapStatus.no && (checkTryCreate(buf) || session.options.tryCreate))
		return ImapResult(ImapStatus.tryCreate,buf);

	if (resTag == ImapStatus.none)
		return ImapResult(ImapStatus.continue_,buf);

	return ImapResult(resTag,buf);
}


@SILdoc("Process the greeting that server sends during connection.")
ImapResult responseGreeting(ref Session session)
{
	import std.experimental.logger : tracef;

	auto res = session.receiveResponse(Duration.init, false);
	if (res[0] == Status.failure)
		return ImapResult(ImapStatus.unknown,"");

	if (session.options.debugMode) tracef("S (%s): %s", session.socket, res);

	if (checkBye(res[1]))
		return ImapResult(ImapStatus.bye,res[1]);

	if (checkPreAuth(res[1]))
		return ImapResult(ImapStatus.preAuth,res[1]);

	return ImapResult(ImapStatus.none,res[1]);
}

T parseEnum(T)(string val, T def = T.init)
{
	import std.traits : EnumMembers;
	import std.conv : to;
	static foreach(C;EnumMembers!T)
	{{
		enum name = C.to!string;
		enum udas = __traits(getAttributes, __traits(getMember,T,name));
		static if(udas.length > 0)
		{
			if (val == udas[0].to!string)
			{
				return C;
			}
		}
	}}
	return def;
}


@SILdoc("Process the data that server sent due to IMAP CAPABILITY client request.")
ImapResult responseCapability(ref Session session, Tag tag)
{
	import std.experimental.logger : infof, tracef;
	import std.string : splitLines, join, startsWith, toUpper, strip, split;
	import std.algorithm : filter, map;
	import std.array : array;
	import std.traits: EnumMembers;
	import std.conv : to;

	ImapProtocol protocol = session.imapProtocol;
	Set!Capability capabilities = session.capabilities;
	enum CapabilityToken = "* CAPABILITY ";

	auto res = session.responseGeneric(tag);
	if (res.status == ImapStatus.unknown || res.status == ImapStatus.bye)
		return res;

	auto lines = res.value
					.splitLines
					.filter!(line => line.startsWith(CapabilityToken) && line.length > CapabilityToken.length)
					.array
					.map!(line => line[CapabilityToken.length ..$].strip.split
								.map!(token => token.strip)
								.array)
					.join;

	foreach(token;lines)
	{
		auto capability = parseEnum!Capability(token,Capability.none);
		if (capability != Capability.none)
		{
			switch(token)
			{
				case "NAMESPACE":
					capabilities = capabilities.add(Capability.namespace);
					break;
				
				case "AUTH=CRAM-MD5":
					capabilities = capabilities.add(Capability.cramMD5);
					break;

				case "STARTTLS":
					capabilities = capabilities.add(Capability.startTLS);
					break;

				case "CHILDREN":
					capabilities = capabilities.add(Capability.children);
					break;

				case "IDLE":
					capabilities = capabilities.add(Capability.idle);
				break;

			case "IMAP4rev1":
				protocol = ImapProtocol.imap4Rev1;
				break;

			case "IMAP4":
				protocol = ImapProtocol.imap4;
				break;

			default:
				bool isKnown = false;
				static foreach(C;EnumMembers!Capability)
				{{
					enum name = C.to!string;
					enum udas = __traits(getAttributes, __traits(getMember,Capability,name));
					static if(udas.length > 0)
					{
						if (token == udas[0].to!string)
						{
							capabilities = capabilities.add(C);
							isKnown = true;
						}
					}
				}}
				if (!isKnown && session.options.debugMode)
				{
					infof("unknown capabilty: %s",token);
				}
				break;
			}
		}
	}

	if (capabilities.has(Capability.imap4Rev1))
		session.imapProtocol = ImapProtocol.imap4Rev1;
	else if (capabilities.has(Capability.imap4))
		session.imapProtocol = ImapProtocol.imap4;
	else
		session.imapProtocol = ImapProtocol.init;

	session.capabilities = capabilities;
	session.imapProtocol = protocol;
	if (session.options.debugMode)
	version(Trace)
	{
		tracef("session capabilities: %s",session.capabilities.values);
		tracef("session protocol: %s",session.imapProtocol);
	}
	return res;
}


@SILdoc("Process the data that server sent due to IMAP AUTHENTICATE client request.")
ImapResult responseAuthenticate(ref Session session, Tag tag)
{
	import std.string : splitLines, join, strip, startsWith;
	import std.algorithm : filter, map;
	import std.array : array;

	auto res = session.responseContinuation(tag);
	auto challengeLines = res.value
							.splitLines
							.filter!(line => line.startsWith("+ "))
							.array
							.map!(line => (line.length ==2) ? "" : line[2..$].strip)
							.array
							.join;
	if (res.status == ImapStatus.continue_ && challengeLines.length > 0)
		return ImapResult(ImapStatus.continue_,challengeLines);
	else
		return ImapResult(ImapStatus.none,res.value);
}

@SILdoc("Process the data that server sent due to IMAP NAMESPACE client request.")
ImapResult responseNamespace(ref Session session, Tag tag)
{
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return ImapResult(r.status,r.value);
	return r;
}


string coreUDA(string uda)
{
	import std.string : replace, strip;
	return uda.replace("# ","").replace(" #","").strip;
}


T getValueFromLine(T)(string line, string uda)
{
	import std.conv : to;
	import std.string : startsWith, strip, split;
	auto udaToken = uda.coreUDA();
	auto i = token.indexOf(token,udaToken);
	auto j = i + udaToken.length + 1;

	bool isPrefix = uda.startsWith("# ");
	if (isPrefix)
	{
		return token[0..i].strip.split.back.to!T;
	}
	else
	{
		return token[j .. $].strip.to!T;
	}
}

string getTokenFromLine(string line, string uda)
{
	return "";
}

version(None)
T parseStruct(T)(T agg, string line)
{
	import std.traits : Fields;
	import std.conv : to;
	static foreach(M;__traits(allMembers,T))
	{{
		enum name = M.to!string;
		enum udas = __traits(getAttributes, __traits(getMember,T,name));
		alias FT = typeof( __traits(getMember,T,name));
		static if(udas.length > 0)
		{
			enum uda = udas[0].to!string;
			if (token == uda.coreUDA)
			{
				__traits(getMember,agg,name) = getValueFromToken!FT(line,uda);
			}
		}
	}}
	return agg;
}

struct StatusResult
{
	ImapStatus status;
	string value;

	@("MESSAGES")
	int messages;

	@("RECENT")
	int recent;

	@("UIDNEXT")
	int uidNext;

	@("UNSEEN")
	int unseen;
}

T parseUpdateT(T)(T t, string name, string value)
{
	import std.format : format;
	import std.exception : enforce;
	import std.conv : to;

	bool isKnown = false;
	static foreach(M; __traits(allMembers,T))
	{{
		enum udas = __traits(getAttributes, __traits(getMember,T,M));
		static if(udas.length > 0)
		{
			if (name == udas[0].to!string)
			{
				alias FieldType = typeof(__traits(getMember,T,M));
				__traits(getMember,t,M) = value.to!FieldType;
				isKnown = true;
			}
		}
	}}
	enforce(isKnown, format!"unknown token for type %s parsing name = %s; value = %s"
					(__traits(identifier,T),name,value));
	return t;
}

private string extractMailbox(string line)
{
	import std.string : split, strip;
	auto cols = line.split;
	return (cols.length < 3) ? null : cols[2].strip;
}

private string[][] extractParenthesizedList(string line)
{
	import std.string : indexOf, lastIndexOf, strip, split;
	import std.format : format;
	import std.range : chunks;
	import std.exception : enforce;
	import std.array : array;
	import std.algorithm : map;

	auto i = line.indexOf("(");
	auto j = line.lastIndexOf(")");

	if (i == -1 || j == -1)
		return [][];

	enforce(j > i, format!"line %s should have a (parenthesized list) but it is malformed"(line));
	auto cols = line[i+1 .. j].strip.split;
	enforce(cols.length % 2 == 0, format!"tokens %s should have an even number of columns but they don't"(cols));
	return cols.chunks(2).map!(r => r.array).array;
}



@SILdoc("Process the data that server sent due to IMAP STATUS client request.")
StatusResult responseStatus(ref Session session, int tag, string mailboxName)
{
	import std.exception : enforce;
	import std.algorithm : map, filter;
	import std.array : array;
	import std.string : splitLines, split,strip,toUpper,indexOf, startsWith, isNumeric;
	import std.range : front;
	import std.conv : to;

	enum StatusToken = "* STATUS ";
	StatusResult ret;

	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return StatusResult(r.status,r.value);

	ret.status = r.status;
	ret.value = r.value;

	auto lists = r.value.splitLines
					.map!(line => line.strip)
					.filter!(line => line.startsWith(StatusToken) && line.extractMailbox == mailboxName)
					.map!(line => line.extractParenthesizedList)
					.array;

	foreach(list; lists)
	auto lines = r.value.extractLinesWithPrefix(StatusToken, StatusToken.length + mailboxName.length + 2);

	version(None)
	foreach(line;lines)
	{
		foreach(pair;list)
		{
			ret = parseUpdateT!StatusResult(ret, pair[0],pair[1]);
			auto key = cols[j*2];
			auto val = cols[j*2 +1];
			if (!val.isNumeric)
				continue;
			ret = ret.parseStruct(key.toUpper,val.to!int);
		}
	}
	return ret;
}

string[] extractLinesWithPrefix(string buf, string prefix, size_t minimumLength = 0)
{
	import std.string : splitLines, strip, startsWith;
	import std.algorithm : map, filter;
	import std.array : array;
	
	auto lines = buf.splitLines
					.map!(line => line.strip)
					.filter!(line => line.startsWith(prefix) && line.length > minimumLength)
					.map!(line => line[prefix.length .. $].strip)
					.array;
	return lines;
}

@SILdoc("Process the data that server sent due to IMAP EXAMINE client request.")
ImapResult responseExamine(ref Session session, int tag)
{
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return ImapResult(r.status,r.value);
	return r;
}

struct SelectResult
{
	ImapStatus status;
	string value;

	@("FLAGS (#)")
	ImapFlag[] flags;

	@("# EXISTS")
	int exists;

	@("# RECENT")
	int recent;

	@("OK [UNSEEN #]")
	int unseen;

	@("OK [PERMANENTFLAGS #]")
	ImapFlag[] permanentFlags;

	@("OK [UIDNEXT #]")
	int uidNext;

	@("OK [UIDVALIDITY #]")
	int uidValidity;
}


@SILdoc("Process the data that server sent due to IMAP SELECT client request.")
SelectResult responseSelect(ref Session session, int tag)
{
	import std.algorithm: canFind;
	import std.string : toUpper;
	SelectResult ret;
	auto r = session.responseGeneric(tag);
	ret.status = (r.value.canFind("OK [READ-ONLY] SELECT")) ? ImapStatus.readOnly : r.status;
	ret.value = r.value;

	if (ret.status == ImapStatus.unknown || ret.status == ImapStatus.bye)
		return ret;

	auto lines = r.value.extractLinesWithPrefix("* ", 3);
	version(None)
	foreach(line;lines)
	{
		ret = ret.parseStruct(line);
	}
	return ret;
}

@SILdoc("Process the data that server sent due to IMAP MOVE client request.")
ImapResult responseMove(ref Session session, int tag)
{
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return ImapResult(r.status,r.value);
	return r;
}



///
enum ListNameAttribute
{
	@(`\NoInferiors`)
	noInferiors,

	@(`\Noselect`)
	noSelect,

	@(`\Marked`)
	marked,

	@(`\Unmarked`)
	unMarked,
}


///
string stripQuotes(string s)
{
	import std.range : front, back;
	if (s.length < 2)
		return s;
	if (s.front == '"' && s.back == '"')
		return s[1..$-1];
	return s;
}

///
string stripBrackets(string s)
{
	import std.range : front, back;
	if (s.length < 2)
		return s;
	if (s.front == '(' && s.back == ')')
		return s[1..$-1];
	return s;
}

///
struct ListEntry
{
	ListNameAttribute[] attributes;
	string hierarchyDelimiter;
	string path;
}

///
struct ListResponse
{
	ImapStatus status;
	string value;
	ListEntry[] entries;
}

@SILdoc("Process the data that server sent due to IMAP LIST or IMAP LSUB client request.")
ListResponse responseList(ref Session session, Tag tag)
{
//			list:			"\\* (LIST|LSUB) \\(([[:print:]]*)\\) (\"[[:print:]]\"|NIL) " ~
//							  "(\"([[:print:]]+)\"|([[:print:]]+)|\\{([[:digit:]]+)\\} *\r+\n+([[:print:]]*))\r+\n+",

	//Mailbox[] mailboxes;
	//string[] folders;
	import std.array : array;
	import std.algorithm : map, filter;
	import std.string : splitLines, split, strip, startsWith;
	import std.traits : EnumMembers;
	import std.conv : to;


	auto result = session.responseGeneric(tag);
	if (result.status == ImapStatus.unknown || result.status == ImapStatus.bye)
		return ListResponse(result.status,result.value);

	ListEntry[] listEntries;

	foreach(line;result.value.splitLines
					.map!(line => line.strip)
					.array
					.filter!(line => line.startsWith("* LIST ") || line.startsWith("* LSUB"))
					.array
					.map!(line => line.split[2..$])
					.array)
	{
		ListEntry listEntry;

		static foreach(A;EnumMembers!ListNameAttribute)
		{{
			enum name = A.to!string;
			enum udas = __traits(getAttributes, __traits(getMember,ListNameAttribute,name));
			static if(udas.length > 0)
			{
				if (line[0].strip.stripBrackets() == udas[0].to!string)
				{
					listEntry.attributes ~=A;
				}
			}
		 }}
		
		listEntry.hierarchyDelimiter = line[1].strip.stripQuotes;
		listEntry.path = line[2].strip;
		listEntries ~= listEntry;
	}
	return ListResponse(ImapStatus.ok,result.value,listEntries);
}



///
struct SearchResult
{
	ImapStatus status;
	string value;
	long[] ids;
}

@SILdoc("Process the data that server sent due to IMAP SEARCH client request.")
SearchResult responseEsearch(ref Session session, int tag)
{
	return responseSearch(session,tag,"* ESEARCH ");
}

@SILdoc("Process the data that server sent due to IMAP SEARCH client request.")
SearchResult responseSearch(ref Session session, int tag, string searchToken = "* SEARCH ")
{
	import std.algorithm : filter, map, each;
	import std.array : array, Appender;
	import std.string : startsWith, strip, isNumeric, splitLines, split;
	import std.conv : to;

	SearchResult ret;
	Appender!(long[]) ids;
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return SearchResult(r.status,r.value);

	auto lines = r.value.splitLines.filter!(line => line.strip.startsWith(searchToken)).array
					.map!(line => line[searchToken.length -1 .. $]
									.strip
									.split
									.map!(token => token.strip)
									.filter!(token => token.isNumeric)
									.map!(token => token.to!long));

	lines.each!( line => line.each!(val => ids.put(val)));
	return SearchResult(r.status,r.value,ids.data);
}

@SILdoc("Process the data that server sent due to IMAP ESEARCH (really multi-search) client request.")
SearchResult responseMultiSearch(ref Session session, int tag)
{
	import std.algorithm : filter, map, each;
	import std.array : array, Appender;
	import std.string : startsWith, strip, isNumeric, splitLines, split;
	import std.conv : to;

	SearchResult ret;
	Appender!(long[]) ids;
	enum SearchToken = "* ESEARCH ";
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return SearchResult(r.status,r.value);

	auto lines = r.value.splitLines.filter!(line => line.strip.startsWith(SearchToken)).array
					.map!(line => line[SearchToken.length -1 .. $]
									.strip
									.split
									.map!(token => token.strip)
									.filter!(token => token.isNumeric)
									.map!(token => token.to!long));

	lines.each!( line => line.each!(val => ids.put(val)));
	return SearchResult(r.status,r.value,ids.data);
}

@SILdoc("Process the data that server sent due to IMAP FETCH FAST client request.")
ImapResult responseFetchFast(ref Session session, int tag)
{
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return ImapResult(r.status,r.value);
	return r;
}


///
struct FlagResult
{
	ImapStatus status;
	string value;
	long[]  ids;
	ImapFlag[] flags;
}

@SILdoc("Process the data that server sent due to IMAP FETCH FLAGS client request.")
FlagResult responseFetchFlags(ref Session session, Tag tag)
{
	import std.experimental.logger : infof;
	import std.string : splitLines, join, startsWith, toUpper, strip, split, isNumeric, indexOf;
	import std.algorithm : filter, map, canFind;
	import std.array : array;
	import std.traits: EnumMembers;
	import std.conv : to;
	import std.exception : enforce;

	enum FlagsToken = "* FLAGS ";

	long[] ids;
	ImapFlag[] flags;
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return FlagResult(r.status,r.value);

	auto lines = r.value
					.splitLines
					.map!(line => line.strip)
					.array
					.filter!(line => line.startsWith("* ") && line.canFind("FETCH (FLAGS ("))
					.array
					.map!(line => line["* ".length ..$].strip.split
								.map!(token => token.strip)
								.array);


	foreach(line;lines)
	{
		enforce(line[0].isNumeric);
		ids ~= line[0].to!long;
		enforce(line[1] == "FETCH");
		enforce(line[2].startsWith("(FLAGS"));
		auto token = line[3..$].join;
		auto i = token.indexOf(")");
		enforce(i!=-1);
		token = token[0..i+1].stripBrackets;
		bool isKnown = false;
		static foreach(F;EnumMembers!ImapFlag)
		{{
			enum name = F.to!string;
			enum udas = __traits(getAttributes, __traits(getMember,ImapFlag,name));
			static if(udas.length > 0)
			{
				if (token.to!string == udas[0].to!string)
				{
					flags ~= F;
					isKnown = true;
				}
			}
		}}
		if (!isKnown && session.options.debugMode)
		{
			infof("unknown flag: %s",token);
		}
	}
	return FlagResult(ImapStatus.ok, r.value,ids,flags);
}

///
ImapResult responseFetchDate(ref Session session, Tag tag)
{
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return ImapResult(r.status,r.value);
	return r;
}

///
struct ResponseSize
{
	ImapStatus status;
	string value;
}


@SILdoc("Process the data that server sent due to IMAP FETCH RFC822.SIZE client request.")
ImapResult responseFetchSize(ref Session session, Tag tag)
{
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return ImapResult(r.status,r.value);
	return r;
}


@SILdoc("Process the data that server sent due to IMAP FETCH BODYSTRUCTURE client request.")
ImapResult responseFetchStructure(ref Session session, int tag)
{
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return ImapResult(r.status,r.value);
	return r;
}

///
struct BodyResponse
{
	import arsd.email : MimePart, IncomingEmailMessage;
	ImapStatus status;
	string value;
	string[] lines;
	IncomingEmailMessage message;
    MimeAttachment[] attachments;
}

struct MimeAttachment
{
	string type;
	string filename;
	string content;
	string id;
}

@SILdoc("SIL cannot handle void[], so ...")
MimeAttachment[] attachments(IncomingEmailMessage message)
{
	import std.algorithm : map;
	import std.array : array;
	return message.attachments.map!(a => MimeAttachment(a.type,a.filename,cast(string)a.content.idup,a.id)).array;
}

///
BodyResponse responseFetchBody(ref Session session, Tag tag)
{
	import arsd.email : MimePart, IncomingEmailMessage;
	import std.string : splitLines, join;
	import std.exception : enforce;
	import std.range : front;
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return BodyResponse(r.status,r.value);
	auto parsed = r.value.extractLiterals;
	
	if (parsed[1].length >=2)
		return BodyResponse(r.status,r.value,parsed[1]);
	auto bodyText = (parsed[1].length==0) ? r.value: parsed[1][0];
	auto bodyLines = bodyText.splitLines;
	if (bodyLines.length > 0 && bodyLines.front.length ==0)
		bodyLines = bodyLines[1..$];
	//return BodyResponse(r.status,r.value,new IncomingEmailMessage(bodyLines));
	auto bodyLinesEmail = cast(immutable(ubyte)[][]) bodyLines.idup;
	auto incomingEmail = new IncomingEmailMessage(bodyLinesEmail,false);
    auto attach = attachments(incomingEmail);
	return BodyResponse(r.status,r.value,bodyLines,incomingEmail,attach);
}
/+
//	Process the data that server sent due to IMAP FETCH BODY[] client request,
//	 ie. FETCH BODY[HEADER], FETCH BODY[TEXT], FETCH BODY[HEADER.FIELDS (<fields>)], FETCH BODY[<part>].
ImapResult fetchBody(ref Session session, Tag tag)
{
	import std.experimental.logger : infof;
	import std.string : splitLines, join, startsWith, toUpper, strip, split;
	import std.algorithm : filter, map;
	import std.array : array;
	import std.traits: EnumMembers;
	import std.conv : to;

	enum FlagsToken = "* FLAGS ";

	Flag[] flags;
	auto r = session.responseGeneric(tag);
	if (r.status == ImapStatus.unknown || r.status == ImapStatus.bye)
		return ImapResult(r.status,r.value);

	auto lines = res.value
					.splitLines
					.filter!(line => line.startsWith(CapabilityToken) && line.length > CapabilityToken.length)
					.array
					.map!(line => line[CapabilityToken.length ..$].strip.split
								.map!(token => token.strip.stripBrackets.split)
}
+/


///
bool isTagged(ImapStatus status)
{
	return (status == ImapStatus.ok) || (status == ImapStatus.bad) || (status == ImapStatus.no);
}

@SILdoc("Process the data that server sent due to IMAP IDLE client request.")
ImapResult responseIdle(ref Session session, Tag tag)
{
	import std.experimental.logger : tracef;
	import std.string : toUpper, startsWith, strip;
	import std.algorithm : canFind;
	import std.typecons: Tuple;
	Tuple!(Status,string) result;
     //untagged:       "\\* [[:digit:]]+ ([[:graph:]]*)[^[:cntrl:]]*\r+\n+",
	while(true)
	{
		result = session.receiveResponse(session.options.keepAlive,false);
		result[1] = result[1].strip;
		//if (result[0] == Status.failure)
			//return ImapResult(ImapStatus.unknown,result[1]);

		if (session.options.debugMode) tracef("S (%s): %s", session.socket, result[1]);
		auto bufUpper = result[1].toUpper;

		if (checkBye(result[1]))
			return ImapResult(ImapStatus.bye,result[1]);

		auto checkedTag = session.checkTag(result[1],tag);
		if (checkedTag == ImapStatus.bad || ImapStatus.no)
		{
			return ImapResult(checkedTag,result[1]);
		}
		if (checkedTag == ImapStatus.ok && bufUpper.canFind("IDLE TERMINATED"))
			return ImapResult(ImapStatus.untagged,result[1]);

		bool hasNewInfo = (result[1].startsWith("* ") && result[1].canFind("\n"));
		if (hasNewInfo)
		{
			if(session.options.wakeOnAny)
				break;
			if (bufUpper.canFind("RECENT") || bufUpper.canFind("EXISTS"))
				break;
		}
	}

	return ImapResult(ImapStatus.untagged,result[1]);
}

bool isControlChar(char c)
{
	return(c >=1 && c < 32);
}

bool isSpecialChar(char c)
{
	import std.algorithm : canFind;
	return " ()%[".canFind(c);
}

bool isWhiteSpace(char c)
{
	return (c == '\t') || (c =='\r') || (c =='\n');
}

enum Backslash = '\\';
enum LSquare = '[';
enum RSquare = ']';
enum DoubleQuote = '"';

struct LiteralInfo
{
	ptrdiff_t i;
	ptrdiff_t j;
	ptrdiff_t length;
}

LiteralInfo findLiteral(string buf)
{
	import std.string : indexOf, isNumeric;
	import std.conv : to;
	ptrdiff_t i,j, len;
	bool hasLength;
	do
	{
		i = buf[j..$].indexOf("{");
		i = (i == -1) ? i : i+j;
		j = ((i == -1) || (i+1 == buf.length)) ? -1 : buf[i + 1 .. $].indexOf("}");
		j = (j == -1) ? j : (i + 1) + j;
		hasLength = (i !=-1 && j != -1) && buf[i+1 .. j].isNumeric;
		len = hasLength ? buf[i+1 .. j].to!ptrdiff_t : -1;
	} while (i != -1 && j !=-1 && !hasLength);
	return LiteralInfo(i,j,len);
}

auto extractLiterals(string buf)
{
	import std.array : Appender;
	import std.typecons : tuple;
	import std.stdio;

	Appender!(string[]) nonLiterals;
	Appender!(string[]) literals;
	LiteralInfo literalInfo;
	do
	{
		literalInfo= findLiteral(buf);
		if(literalInfo.length > 0)
		{
			string literal = buf[literalInfo.j+1.. literalInfo.j+1 + literalInfo.length];
			literals.put(literal);
			nonLiterals.put(buf[0 .. literalInfo.i]);
			buf = buf[literalInfo.j+2 + literalInfo.length .. $];
		}
		else
		{
			nonLiterals.put(buf);
			buf.length = 0;
		}
	} while (buf.length > 0 && literalInfo.length > 0);
	return tuple(nonLiterals.data,literals.data);
}
/+
"* 51045 FETCH (UID 70290 BODY[TEXT] {67265}

)
D1009 OK Completed (0.002 sec)
+/

///
module imap.request;

import imap.socket;
import imap.session;
import imap.namespace;
import imap.defines;
import imap.auth;
import imap.response;
import imap.sil : SILdoc;

/// Every IMAP command is preceded with a unique string
static int g_tag = 0x1000;


auto imapTry(alias F, Args...)(Session session, Args args) {
    import std.traits : isInstanceOf;
    import std.conv : to;
    enum noThrow = true;
    auto result = F(session, args);
    alias ResultT = typeof(result);
    static if (is(ResultT == int)) {
        auto status = result;
    } else static if (is(ResultT == ImapResult)) {
        auto status = result.status;
    } else static if (isInstanceOf!(Result, ResultT)) {
        auto status = result.status;
    } else static if (is(ResultT == ListResponse) || is(ResultT == FlagResult)) {
        auto status = result.status;
    } else { static assert(0, "unknown type :" ~ ResultT.stringof); }

    static if (is(ResultT == int)) {
        return result;
    } else {
        if (status == ImapStatus.unknown) {
            if (session.options.recoverAll || session.options.recoverErrors) {
                session.login();
                return F(session, args);
            } else {
                if (!noThrow)
                    throw new Exception("unknown result " ~ result.to!string);
                return result; // ImapResult(ImapStatus.unknown,"");
            }
        } else if (status == ImapStatus.bye) {
            session.closeConnection();
            if (session.options.recoverAll) {
                session.login();
                return F(session, args);
                // return ImapResult(ImapStatus.none,"");
            }
        } else {
            if (!noThrow)
                throw new Exception("IMAP error : " ~ result.to!string ~ "when calling " ~ __traits(identifier, F)  ~ " with args " ~ args.to!string);
            return result;
        }
    }
    assert(0);
}

bool isLoginRequest(string value) {
    import std.string : strip, toUpper, startsWith;
    return value.strip.toUpper.startsWith("LOGIN");
}

@SILdoc("Sends to server data; a command")
int sendRequest(Session session, string value) {
    import std.format : format;
    import std.exception : enforce;
    import std.experimental.logger : infof, tracef;
    import std.stdio;
    import std.string : endsWith;

    enforce(session.socket, "not connected to server");

    if (session.options.debugMode) {
        if (value.isLoginRequest) {
            infof("sending command (%s):\n\n%s\n\n", session.socket, value.length - session.imapLogin.password.length - "\"\"\r\n".length, value);
            tracef("C (%s): %s\n", session.socket, value.length, session.imapLogin.password.length - "\"\"\r\n".length, value);
        } else {
            infof("sending command (%s):\n\n%s\n", session.socket, value);
            tracef("C (%s): %s", session.socket, value);
        }
    }

    int tag = g_tag;
    g_tag++;
    if (g_tag > 0xffff)
        g_tag = 0x1000;

    auto taggedValue = format!"D%04X %s%s"(tag, value, value.endsWith("\n") ? "" : "\r\n");
    version (Trace) stderr.writefln("sending %s", taggedValue);
    if (session.socketWrite(taggedValue) == -1)
        return -1;

    return tag;
}

@SILdoc("Sends a response to a command continuation request.")
int sendContinuation(Session session, string data) {
    import std.exception : enforce;
    enforce(session.socket, "not connected to server");
    session.socketWrite(data ~ "\r\n");
    return 1;
}


@SILdoc("Reset any inactivity autologout timer on the server")
void noop(Session session) {
    auto t = session.sendRequest("NOOP");
    session.check!responseGeneric(t);
}

///
auto check(alias F, Args...)(Session session, Args args) {
    import std.exception : enforce;
    import std.format : format;
    import std.traits : isInstanceOf;
    import imap.response : ImapResult;

    auto v = F(session, args);
    alias ResultT = typeof(v);
    static if (is(ResultT == ImapStatus)) {
        auto status = v;
    } else static if (isInstanceOf!(ResultT, Result) || is(ResultT == ImapResult)) {
        auto status = v.status;
    } else {
        auto status = v;
    }
    if (status == ImapStatus.bye) {
        session.closeConnection();
    }
    enforce(status != -1 && status != ImapStatus.bye, format!"error calling %s"(__traits(identifier, F)));
    return v;
}


@SILdoc("Connect to the server, login to the IMAP server, get its capabilities, get the namespace of the mailboxes.")
Session login(Session session) {
    import std.format : format;
    import std.exception : enforce;
    import std.experimental.logger : errorf, infof;
    import std.string : strip;
    import std.stdio;

    int t;
    ImapResult res;
    ImapStatus rl = ImapStatus.unknown;
    auto login = session.imapLogin;

    scope (failure)
        closeConnection(session);
    if (session.socket is null || !session.socket.isAlive()) {
        if (session.options.debugMode) infof("login called with dead socket, so trying to reconnect");
        session = openConnection(session);
    }
    enforce(session.socket.isAlive(), "not connected to server");

    auto rg = session.check!responseGreeting();
    version (Trace) stderr.writefln("got login first stage: %s", rg);
    /+
    if (session.options.debugMode)
    {
        t = session.check!sendRequest("NOOP");
        session.check!responseGeneric(t);
    }
    +/
    t = session.check!sendRequest("CAPABILITY");
    version (Trace) stderr.writefln("sent capability request");
    res = session.check!responseCapability(t);
    version (Trace) stderr.writefln("got capabilities: %s", res);

    bool needsStartTLS =   (session.sslProtocol != ProtocolSSL.none)
        && session.capabilities.has(Capability.startTLS)
        && session.options.startTLS;
    if (needsStartTLS) {
        version (Trace) stderr.writeln("sending StartTLS");
        t = session.check!sendRequest("STARTTLS");
        version (Trace) stderr.writeln("checking for StartTLS response ");
        res = session.check!responseGeneric(t);
        // enforce(res.status == ImapStatus.ok, "received bad response: " ~ res.to!string);
        version (Trace) stderr.writeln("opening secure connection");
        session.openSecureConnection();
        version (Trace) stderr.writeln("opened secure connection; check capabilties");
        t = session.check!sendRequest("CAPABILITY");
        version (Trace) stderr.writeln("sent capabilties request");
        res = session.check!responseCapability(t);
        version (Trace) stderr.writeln("got capabilities response");
        version (Trace) stderr.writeln(res);
    }

    if (rg.status == ImapStatus.preAuth) {
        rl = ImapStatus.preAuth;
    } else {
        if (session.capabilities.has(Capability.cramMD5) && session.options.cramMD5) {
            version (Trace) stderr.writefln("cram");
            t = session.check!sendRequest("AUTHENTICATE CRAM-MD5");
            res = session.check!responseAuthenticate(t);
            version (Trace) stderr.writefln("authenticate cram first response: %s", res);
            enforce(res.status == ImapStatus.continue_, "login failure");
            auto hash = authCramMD5(login.username, login.password, res.value.strip);
            stderr.writefln("hhash: %s", hash);
            t = session.check!sendContinuation(hash);
            res = session.check!responseGeneric(t);
            version (Trace) stderr.writefln("response: %s", res);
            rl = res.status;
        }
        if (rl != ImapStatus.ok) {
            t = session.check!sendRequest(format!"LOGIN \"%s\" \"%s\""(login.username, login.password));
            res = session.check!responseGeneric(t);
            rl = res.status;
        }
        if (rl == ImapStatus.no) {
            auto err = format!"username %s or password rejected at %s\n"(login.username, session.server);
            if (session.options.debugMode) errorf("username %s or password rejected at %s\n", login.username, session.server);
            session.closeConnection();
            throw new Exception(err);
        }
    }

    t = session.check!sendRequest("CAPABILITY");
    res = session.check!responseCapability(t);

    if (session.capabilities.has(Capability.namespace) && session.options.namespace) {
        t = session.check!sendRequest("NAMESPACE");
        res = session.check!responseNamespace(t);
        rl = res.status;
    }

    if (session.capabilities.has(Capability.imap4Rev1)) {
        session.imapProtocol = ImapProtocol.imap4Rev1;
    } else if (session.capabilities.has(Capability.imap4)) {
        session.imapProtocol = ImapProtocol.imap4;
    } else {
        session.imapProtocol = ImapProtocol.init;
    }

    if (session.selected !is null) {
        t = session.check!sendRequest(format!"SELECT \"%s\""(session.selected.toString));
        auto selectResult = session.responseSelect(t);
        enforce(selectResult.status == ImapStatus.ok);
        rl = selectResult.status;
    }

    return session.setStatus(rl);
}


@SILdoc("Logout from the IMAP server and disconnect")
int logout(Session session) {

    if (responseGeneric(session, sendRequest(session, "LOGOUT")).status == ImapStatus.unknown) {
        // sessionDestroy(session);
    } else {
        closeConnection(session);
        // sessionDestroy(session);
    }
    return ImapStatus.ok;
}

@SILdoc("IMAP examine command for mailbox mbox")
auto examine(Session session, Mailbox mbox) {
    import std.format : format;
    auto request = format!`EXAMINE "%s"`(mbox);
    auto id = session.sendRequest(request);
    return session.responseExamine(id);
}


@SILdoc("Get mailbox status")
auto status(Session session, Mailbox mbox) {
    import std.format : format;
    import std.exception : enforce;
    enforce(session.imapProtocol == ImapProtocol.imap4Rev1, "status only implemented for Imap4Rev1 - try using examine");
    auto mailbox = mbox.toString();
    auto request = format!`STATUS "%s" (MESSAGES RECENT UNSEEN UIDNEXT)`(mailbox);
    auto id = session.sendRequest(request);
    return session.responseStatus(id, mailbox);
}

@SILdoc("Open mailbox in read-write mode.")
auto select(Session session, Mailbox mailbox) {
    import std.format : format;
    auto request = format!`SELECT "%s"`(mailbox.toString);
    auto id = session.sendRequest(request);
    auto ret = session.responseSelect(id);
    if (ret.status == ImapStatus.ok)
        session.selected = mailbox;
    return ret;
}


@SILdoc("Close examined/selected mailbox")
ImapResult close(Session session) {
    enum request = "CLOSE";
    auto id = sendRequest(session, request);
    auto response = responseGeneric(session, id);
    if (response.status == ImapStatus.ok) {
        session.selected = Mailbox.init;
    }
    return response;
}

@SILdoc("Remove all messages marked for deletion from selected mailbox")
ImapResult expunge(Session session) {
    enum request = "EXPUNGE";
    auto id = sendRequest(session, request);
    return session.responseGeneric(id);
}

///
struct MailboxList {
    string[] mailboxes;
    string[] folders;
}

@SILdoc(`List available mailboxes:
	The LIST command returns a subset of names from the complete set
	of all names available to the client.  Zero or more untagged LIST
	replies are returned, containing the name attributes, hierarchy
	delimiter, and name.

	The reference and mailbox name arguments are interpreted into a
	canonical form that represents an unambiguous left-to-right
	hierarchy. 

	Here are some examples of how references and mailbox names might
	be interpreted on a UNIX-based server:

	   Reference     Mailbox Name  Interpretation
	   ------------  ------------  --------------
	   ~smith/Mail/  foo.*         ~smith/Mail/foo.*
	   archive/      %             archive/%
	   #news.        comp.mail.*   #news.comp.mail.*
	   ~smith/Mail/  /usr/doc/foo  /usr/doc/foo
	   archive/      ~fred/Mail/*  ~fred/Mail/*

	The first three examples demonstrate interpretations in
	the context of the reference argument.  Note that
	"~smith/Mail" SHOULD NOT be transformed into something
	like "/u2/users/smith/Mail", or it would be impossible
	for the client to determine that the interpretation was
	in the context of the reference.

	The character "*" is a wildcard, and matches zero or more
	characters at this position.  The character "%" is similar to "*",
	but it does not match a hierarchy delimiter.  If the "%" wildcard
	is the last character of a mailbox name argument, matching levels
	of hierarchy are also returned.  If these levels of hierarchy are
	not also selectable mailboxes, they are returned with the
	\Noselect mailbox name attribute (see the description of the LIST
	response for more details).

	Params:
		session - current IMAP session
		referenceName
		mailboxName
`)
auto list(Session session, string referenceName = "", string mailboxName = "*") {
    import std.format : format;
    auto request = format!`LIST "%s" "%s"`(referenceName, mailboxName);
    auto id = session.sendRequest(request);
    return session.responseList(id);
}


@SILdoc("List subscribed mailboxes")
auto lsub(Session session, string refer = "", string name = "*") {
    import std.format : format;
    auto request = format!`LSUB "%s" "%s"`(refer, name);
    auto id = session.imapTry!sendRequest(request);
    return session.responseList(id);
}

@SILdoc("Search selected mailbox according to the supplied search criteria")
auto search(Session session, string criteria, string charset = null) {
    import std.format : format;
    string s;

    s = (charset.length > 0) ? format!`UID SEARCH CHARSET "%s" %s`(charset, criteria)
        : format!`UID SEARCH %s`(criteria);

    auto t = session.imapTry!sendRequest(s);
    auto r = session.responseSearch(t);
    return r;
}

enum SearchResultType {
    min,
    max,
    count,
    all,
}

string toString(SearchResultType[] resultTypes) {
    import std.string : toUpper, join;
    import std.format : format;
    import std.algorithm : map;
    import std.conv : to;
    import std.array : array;

    if (resultTypes.length == 0)
        return null;
    return format!"RETURN (%s) "(resultTypes.map!(t => t.to!string.toUpper).array.join(" "));
}

private string createSearchMailboxList(string[] mailboxes, string[] subtrees, bool subtreeOne = false) {
    import std.array : Appender;
    import std.algorithm : map;
    Appender!string ret;
    import std.format : format;
    import std.algorithm : map;
    import std.string : join, strip;
    auto subtreeTerm = subtreeOne ? "subtree-one" : "subtree";

    // FIXME = should add "subscribed", "inboxes" and maybe "selected" and "selected-delayed"
    if (mailboxes.length == 0 && subtrees.length == 0)
        return `IN ("personal") `;
    if (mailboxes.length > 0)
        ret.put(format!"mailboxes %s "(mailboxes.map!(m => format!`"%s"`(m)).join(" ")));
    if (subtrees.length > 0)
        ret.put(format!"%s %s "(subtreeTerm, subtrees.map!(t => format!`"%s"`(t)).join(" ")));
    return format!"IN (%s) "(ret.data.strip);
}


@SILdoc("Search selected mailbox according to the supplied search criteria.")
auto esearch(Session session, string criteria, SearchResultType[] resultTypes = [], string charset = null) {
    import std.format : format;
    import std.string : strip;
    string s;

    s = (charset.length > 0) ? format!`UID SEARCH %sCHARSET "%s" %s`(resultTypes.toString(), charset, criteria)
        : format!`UID SEARCH %s%s`(resultTypes.toString(), criteria);
    s = s.strip;
    import std.stdio;
    stderr.writeln(s);
    auto t = session.imapTry!sendRequest(s);
    auto r = session.responseEsearch(t);
    return r;
}

@SILdoc("Search selected mailboxes and subtrees according to the supplied search criteria.")
auto multiSearch(Session session, string criteria, SearchResultType[] resultTypes = [], string[] mailboxes = [], string[] subtrees = [], string charset = null, bool subtreeOne = false) {
    import std.format : format;
    import std.string : strip;
    string s;

    s = (charset.length > 0) ? format!`ESEARCH %s%sCHARSET "%s" %s`(
        createSearchMailboxList(mailboxes, subtrees, subtreeOne),
        resultTypes.toString(), charset, criteria)
        : format!`ESEARCH %s%s%s`(
            createSearchMailboxList(mailboxes, subtrees, subtreeOne),
            resultTypes.toString(), criteria);
    s = s.strip;
    auto t = session.imapTry!sendRequest(s);
    auto r = session.responseMultiSearch(t);
    return r;
}

private int sendFetchRequest(Session session, string id, string itemSpec) {
    import std.format : format;

    // Does the id start with '#'?
    if (id.length > 1 && id[0] == '#') {
        // A mailbox sequence id which should be in the range 1 to mailbox-message-count.
        return session.sendRequest(format!"FETCH %s %s"(id[1 .. $], itemSpec));
    }

    // Otherwise it's a mailbox uid.
    return session.sendRequest(format!"UID FETCH %s %s"(id, itemSpec));
}

@SILdoc("Fetch the FLAGS, INTERNALDATE and RFC822.SIZE of the messages")
auto fetchFast(Session session, string mesg) {
    auto t = session.imapTry!sendFetchRequest(mesg, "FAST");
    return session.responseFetchFast(t);
}

@SILdoc("Fetch the FLAGS of the messages")
auto fetchFlags(Session session, string mesg) {
    auto t = session.imapTry!sendFetchRequest(mesg, "FLAGS");
    return session.responseFetchFlags(t);
}

@SILdoc("Fetch the INTERNALDATE of the messages")
auto fetchDate(Session session, string mesg) {
    auto id = session.imapTry!sendFetchRequest(mesg, "INTERNALDATE");
    return session.responseFetchDate(id);
}

@SILdoc("Fetch the RFC822.SIZE of the messages")
auto fetchSize(Session session, string mesg) {
    auto id = session.imapTry!sendFetchRequest(mesg, "RFC822.SIZE");
    return session.responseFetchSize(id);
}

@SILdoc("Fetch the BODYSTRUCTURE of the messages")
auto fetchStructure(Session session, string mesg) {
    auto id = session.imapTry!sendFetchRequest(mesg, "BODYSTRUCTURE");
    return session.responseFetchStructure(id);
}

@SILdoc("Fetch the BODY[HEADER] of the messages")
auto fetchHeader(Session session, string mesg) {
    auto id  = session.imapTry!sendFetchRequest(mesg, "BODY.PEEK[HEADER]");
    return session.responseFetchBody(id);
}

@SILdoc("Fetch the entire message text, ie. RFC822, of the messages")
auto fetchRFC822(Session session, string mesg) {
    auto id  = session.imapTry!sendFetchRequest(mesg, "RFC822");
    return session.responseFetchBody(id);
}

@SILdoc("Fetch the text, ie. BODY[TEXT], of the messages")
auto fetchText(Session session, string mesg) {
    auto id  = session.imapTry!sendFetchRequest(mesg, "BODY.PEEK[TEXT]");
    return session.responseFetchBody(id);
}

@SILdoc("Fetch the specified header fields, ie. BODY[HEADER.FIELDS (<fields>)], of the messages.")
auto fetchFields(Session session, string mesg, string headerFields) {
    import std.format : format;
    auto itemSpec = format!`BODY.PEEK[HEADER.FIELDS (%s)]`(headerFields);
    auto id  = session.imapTry!sendFetchRequest(mesg, itemSpec);
    return session.responseFetchBody(id);
}

@SILdoc("Fetch the specified message part, ie. BODY[<part>], of the messages")
auto fetchPart(Session session, string mesg, string part) {
    import std.format : format;
    auto itemSpec = format!`BODY.PEEK[%s]`(part);
    auto id  = session.imapTry!sendFetchRequest(mesg, itemSpec);
    return session.responseFetchBody(id);
}

enum StoreMode {
    replace,
    add,
    remove,
}

private string modeString(StoreMode mode) {
    final switch (mode) with (StoreMode)
        {
            case replace: return "";
            case add: return "+";
            case remove: return "-";
        }
    assert(0);
}

private string formatRequestWithId(alias fmt, Args...)(string id, Args args) {
    import std.format : format;

    if (id.length > 1 && id[0] == '#') {
        return format!(fmt)(id[1 .. $], args);
    }
    return format!("UID " ~ fmt)(id, args);
}

@SILdoc("Add, remove or replace the specified flags of the messages.")
auto store(Session session, string mesg, StoreMode mode, string flags) {
    import std.format : format;
    import std.algorithm : canFind;
    import std.string : toLower, startsWith;
    import std.format : format;
    auto t = session.imapTry!sendRequest(formatRequestWithId!"STORE %s %sFLAGS.SILENT (%s)"(mesg, mode.modeString, flags));
    auto r = session.responseGeneric(t);

    if (canFind(flags, `\Deleted`) && mode != StoreMode.remove && session.options.expunge) {
        if (session.capabilities.has(Capability.uidPlus)) {
            t = session.imapTry!sendRequest(formatRequestWithId!"EXPUNGE %s"(mesg));
            session.responseGeneric(t);
        } else {
            t = session.imapTry!sendRequest("EXPUNGE");
            session.responseGeneric(t);
        }
    }
    return r;
}

@SILdoc("Copy the specified messages to another mailbox.")
auto copy(Session session, string mesg, Mailbox mailbox) {
    import std.format : format;

    auto t = session.imapTry!sendRequest(formatRequestWithId!`COPY %s "%s"`(mesg, mailbox.toString));
    auto r = session.imapTry!responseGeneric(t);
    if (r.status == ImapStatus.tryCreate) {
        t = session.imapTry!sendRequest(format!`CREATE "%s"`(mailbox.toString));
        session.imapTry!responseGeneric(t);
        if (session.options.subscribe) {
            t = session.imapTry!sendRequest(format!`SUBSCRIBE "%s"`(mailbox.toString));
            session.imapTry!responseGeneric(t);
        }
        t = session.imapTry!sendRequest(formatRequestWithId!`COPY %s "%s"`(mesg, mailbox.toString));
        r = session.imapTry!responseGeneric(t);
    }
    return r;
}

@SILdoc("Move the specified message to another mailbox.")
auto move(Session session, long uid, string mailbox) {
    import std.conv : text;
    return multiMove(session, text(uid), new Mailbox(session, mailbox));
}

@SILdoc("Move the specified messages to another mailbox.")
auto moveUIDs(Session session, long[] uids, string mailbox) {
    import std.conv : text;
    import std.algorithm : map;
    import std.array : array;
    import std.string : join;
    return multiMove(session, uids.map!(uid => text(uid)).array.join(","), new Mailbox(session, mailbox));
}

@SILdoc("Move the specified messages to another mailbox.")
auto multiMove(Session session, string mesg, Mailbox mailbox) {
    import std.exception : enforce;
    import std.format : format;
    import std.conv : to;
    version (MoveSanity) {
        auto t = session.imapTry!sendRequest(format!`UID MOVE %s %s`(mesg, mailbox.toString));
        auto r = session.imapTry!responseMove(t);
        if (r.status == ImapStatus.tryCreate) {
            t = session.imapTry!sendRequest(format!`CREATE "%s"`(mailbox.toString));
            session.imapTry!responseGeneric(t);
            if (session.options.subscribe) {
                t = session.imapTry!sendRequest(format!`SUBSCRIBE "%s"`(mailbox.toString));
                session.imapTry!responseGeneric(t);
            }
            t = session.imapTry!sendRequest(format!`UID MOVE %s %s`(mesg, mailbox.toString));
            r = session.imapTry!responseMove(t);
        }
        enforce(r.status == ImapStatus.ok, "imap error when moving : " ~ r.to!string);
        return r;
    } else {
        auto result = copy(session, mesg, mailbox);
        enforce(result.status == ImapStatus.ok, format!"unable to copy message %s to %s as first stage of move:%s"(mesg, mailbox, result));
        result = store(session, mesg, StoreMode.add, `\Deleted`);
        // enforce(result.status == ImapStatus.ok, format!"unable to set deleted flags for message %s as second stage of move:%s"(mesg,result));
        return result;
    }
    assert(0);
}

// NOTE: the date string must follow the standard grammar taken from the RFC, without the
// surrounding double quotes:
//
// date-time       = DQUOTE date-day-fixed "-" date-month "-" date-year SP time SP zone DQUOTE
// date-day-fixed  = (SP DIGIT) / 2DIGIT
// date-month      = "Jan" / "Feb" / "Mar" / "Apr" / "May" / "Jun" / "Jul" / "Aug" / "Sep" / "Oct" / "Nov" / "Dec"
// date-year       = 4DIGIT
// time            = 2DIGIT ":" 2DIGIT ":" 2DIGIT
// zone            = ("+" / "-") 4DIGIT
//
// e.g., " 5-Nov-2020 14:19:28 +1100"

@SILdoc(`Append supplied message to the specified mailbox.`)
auto append(Session session, Mailbox mbox, string[] mesgLines, string[] flags = [], string date = string.init)
{
    import std.format: format;
    import std.algorithm: fold;
    import std.array: join;

    string flagsStr = "";
    if (flags.length > 0) {
        flagsStr = " (" ~ join(flags, " ") ~ ")";
    }

    string dateStr = "";
    if (date) {
        dateStr = ` "` ~ date ~ `"`;
    }

    // TODO: We're making assumptions about the format of the data sent, i.e., '\r\n' suffixes for
    // lines, which should be better abstracted away.

    // Each line in the message has a 2 char '\r\n' suffix added when sent to the server.
    size_t mesgSize = fold!((size, line) => size + line.length + 2)(mesgLines, 0.size_t);
    int cmdTag = session.imapTry!sendRequest(format!`APPEND "%s"%s%s {%u}`(mbox, flagsStr, dateStr, mesgSize));

    auto resp = session.imapTry!responseContinuation(cmdTag);
    if (resp.status != ImapStatus.continue_) {
        return resp;
    }

    // Send each line individually -- the server will wait for exactly mesgSize bytes as the literal
    // string.  Then send an empty line (which will actually be '\r\n') to end the APPEND command.
    foreach (line; mesgLines) {
        session.sendContinuation(line);
    }
    session.sendContinuation("");

    return session.responseGeneric(cmdTag);
}

@SILdoc("Create the specified mailbox")
auto create(Session session, Mailbox mailbox) {
    import std.format : format;
    auto request = format!`CREATE "%s"`(mailbox.toString);
    auto id = session.sendRequest(request);
    return session.responseGeneric(id);
}


@SILdoc("Delete the specified mailbox")
auto delete_(Session session, Mailbox mailbox) {
    import std.format : format;
    auto request = format!`DELETE "%s"`(mailbox.toString);
    auto id = session.sendRequest(request);
    return session.responseGeneric(id);
}

@SILdoc("Rename a mailbox")
auto rename(Session session, Mailbox oldmbox, Mailbox newmbox) {
    import std.format : format;
    auto request = format!`RENAME "%s" "%s"`(oldmbox.toString, newmbox.toString);
    auto id = session.sendRequest(request);
    return session.responseGeneric(id);
}

@SILdoc("Subscribe to the specified mailbox")
auto subscribe(Session session, Mailbox mailbox) {
    import std.format : format;
    auto request = format!`SUBSCRIBE "%s"`(mailbox.toString);
    auto id = session.sendRequest(request);
    return session.responseGeneric(id);
}


@SILdoc("Unsubscribe from the specified mailbox.")
auto unsubscribe(Session session, Mailbox mailbox) {
    import std.format : format;
    auto request = format!`UNSUBSCRIBE "%s"`(mailbox.toString);
    auto id = session.sendRequest(request);
    return session.responseGeneric(id);
}

@SILdoc("IMAP ENABLE command.")
auto enable(Session session, string command) {
    import std.format : format;
    auto request = format!`ENABLE %s`(command);
    auto id = session.sendRequest(request);
    return session.responseGeneric(id);
}

@SILdoc("IMAP raw command.")
auto raw(Session session, string command) {
    import std.format : format;
    auto id = session.sendRequest(command);
    return session.responseGeneric(id);
}

@SILdoc(`IMAP idle command`)
auto idle(Session session) {
    import std.stdio;
    Tag t;
    ImapResult r, ri;

    if (!session.capabilities.has(Capability.idle))
        return ImapResult(ImapStatus.bad, "");

    do
    {
        version (Trace) stderr.writefln("inner loop for idle");
        t = session.sendRequest("IDLE");
        ri = session.responseIdle(t);
        r = session.responseContinuation(t);
        version (Trace) stderr.writefln("sendRequest - responseContinuation was %s", r);
        if (r.status == ImapStatus.continue_) {
            ri = session.responseIdle(t);
            version (Trace) stderr.writefln("responseIdle result was %s", ri);
            session.sendContinuation("DONE");
            version (Trace) stderr.writefln("continuation result was %s", ri);
            r = session.responseGeneric(t);
            version (Trace) stderr.writefln("reponseGenericresult was %s", r);
        }
    } while (false); // ri.status != ImapStatus.untagged);
    stderr.writefln("returning %s", ri);

    return ri;
}

///
enum SearchField {
    all,
    and,
    or,
    not,
    old,
    answered,
    deleted,
    draft,
    flagged,
    header,
    body_,
    bcc,
    cc,
    from,
    to,
    subject,
    text,
    uid,
    unanswered,
    undeleted,
    undraft,
    unflagged,
    unkeyword,
    unseen,
    larger,
    smaller,
    sentBefore,
    sentOn,
    sentSince,
    keyword,
    messageNumbers,
    uidNumbers,
    resultMin,
    resultMax,
    resultAll,
    resultCount,
    resultRemoveFrom,
    resultPartial,
    sourceMailbox,
    sourceSubtree,
    sourceTag,
    sourceUidValidity,
    contextCount,
    context
}

struct SearchParameter {
    string fieldName;
    // Variable value;
}


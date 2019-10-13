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
static int tag = 0x1000;


auto imapTry(alias F,Args...)(ref Session session, Args args)
{
	import std.traits : isInstanceOf;

	auto result = F(session,args);
	alias ResultT = typeof(result);
	static if (is(ResultT == int))
		auto status = result;
	else static if(is(ResultT == ImapResult))
		auto status = result.status;
	else static if(isInstanceOf!(Result,ResultT))
		auto status = result.status;
	else static if(is(ResultT == ListResponse) || is(ResultT == FlagResult))
		auto status = result.status;
	else static assert(0,"unknown type :" ~ ResultT.stringof);

	static if (is(ResultT == int))
	{
		return result;
	}
	else
	{
		if (status == ImapStatus.unknown)
		{
			if (session.options.recoverAll || session.options.recoverErrors)
			{
				session.login();
				return ImapResult(ImapStatus.none,"");
			}
			else
			{
				return ImapResult(ImapStatus.unknown,"");
			}
		}
		else if (status == ImapStatus.bye)
		{
			session.closeConnection();
			if (session.options.recoverAll)
			{
				session.login();
				return ImapResult(ImapStatus.none,"");
			}
		}
		else
		{
			session.destroy();
			return ImapResult(ImapStatus.unknown,"");
		}
	}
	assert(0);
}

bool isLoginRequest(string value)
{
	import std.string : strip, toUpper, startsWith;
	return value.strip.toUpper.startsWith("LOGIN");
}

@SILdoc("Sends to server data; a command")
int sendRequest(ref Session session, string value)
{
	import std.format : format;
	import std.exception : enforce;
	import std.experimental.logger : infof,tracef;
	import std.stdio;
	import std.string : endsWith;
	int n;
	int t = tag;

	enforce(session.socket,"not connected to server");

	if (value.isLoginRequest)
	{
		infof("sending command (%s):\n\n%s\n\n", session.socket,
		    value.length - session.imapLogin.password.length - "\"\"\r\n".length, value);
		tracef("C (%s): %s\n", session.socket, value.length,
				session.imapLogin.password.length - "\"\"\r\n".length,  value);
	} else {
		infof("sending command (%s):\n\n%s\n", session.socket, value);
		tracef("C (%s): %s", session.socket, value);
	}

	auto taggedValue = format!"D%04X %s%s"(tag,value, value.endsWith("\n") ? "":"\r\n");
	stderr.writefln("sending %s",taggedValue);
	if (session.socketWrite(taggedValue) == -1)
		return -1;

	if (tag == 0xFFFF)	/* Tag always between 0x1000 and 0xFFFF. */
		tag = 0x0FFF;
	tag++;

	return t;
}

@SILdoc("Sends a response to a command continuation request")
int sendContinuation(ref Session session, string data)
{
	import std.exception : enforce;
	enforce(session.socket,"not connected to server");
	session.socketWrite(data ~ "\r\n");
	//socketWrite(session, data ~ "\r\n");
	return 1;
}


@SILdoc("Reset any inactivity autologout timer on the server")
void noop(ref Session session)
{
	auto t = session.sendRequest("NOOP");
	session.check!responseGeneric(t);
}

///
auto check(alias F, Args...)(ref Session session, Args args)
{
	import std.exception : enforce;
	import std.format : format;
	import std.traits : isInstanceOf;
	import imap.response : ImapResult;

	auto v = F(session,args);
	alias ResultT = typeof(v);
	static if (is(ResultT == ImapStatus))
	{
		auto status = v;
	}
	else static if (isInstanceOf!(ResultT,Result) || is(ResultT == ImapResult))
	{
		auto status = v.status;
	}
	else
	{
		auto status = v;
	}
	if (status == ImapStatus.bye)
	{
		session.closeConnection();
	}
	enforce(status!= -1 && status != ImapStatus.bye, format!"error calling %s"(__traits(identifier,F)));
	return v;
}


@SILdoc("Connect to the server, login to the IMAP server, get its capabilities, get the namespace of the mailboxes.")
ref Session login(ref Session session)
{
	import std.format : format;
	import std.exception : enforce;
	import std.experimental.logger : errorf, infof;
	import std.string : strip;
	import std.stdio;
	
	int t;
	ImapResult res;
	ImapStatus rl = ImapStatus.unknown;
	auto login = session.imapLogin;

	scope(failure)
		closeConnection(session);
	if (session.socket is null || !session.socket.isAlive())
	{
		infof("login called with dead socket, so trying to reconnect");
		session = openConnection(session);
	 	if (session.useSSL && !session.options.startTLS)
			 session = openSecureConnection(session);
	}
	enforce(session.socket.isAlive(), "not connected to server");

	auto rg = session.check!responseGreeting();
	stderr.writefln("got login first stage: %s",rg);
/+
	if (session.options.debugMode)
	{
		t = session.check!sendRequest("NOOP");
		session.check!responseGeneric(t);
	}+/
	t = session.check!sendRequest("CAPABILITY");
	stderr.writefln("sent capability request");
	res = session.check!responseCapability(t);
	stderr.writefln("got capabilities: %s",res);

	bool needsStartTLS =   (session.sslProtocol != ProtocolSSL.none) &&
                            session.capabilities.has(Capability.startTLS) &&
                            session.options.startTLS;
	if (needsStartTLS)
	{
        version(Trace) stderr.writeln("sending StartTLS");
		t = session.check!sendRequest("STARTTLS");
        version(Trace) stderr.writeln("checking for StartTLS response ");
		res = session.check!responseGeneric(t);
		// enforce(res.status == ImapStatus.ok, "received bad response: " ~ res.to!string);
        version(Trace) stderr.writeln("opening secure connection");
        session.openSecureConnection();
        version(Trace) stderr.writeln("opened secure connection; check capabilties");
        t = session.check!sendRequest("CAPABILITY");
        version(Trace) stderr.writeln("sent capabilties request");
        res = session.check!responseCapability(t);
        version(Trace) stderr.writeln("got capabilities response");
        version(Trace) stderr.writeln(res);
	}

	if (rg.status == ImapStatus.preAuth)
	{
		rl = ImapStatus.preAuth;
	}

	else
	{
		if (session.capabilities.has(Capability.cramMD5) && session.options.cramMD5)
		{
			stderr.writefln("cram");
			t = session.check!sendRequest("AUTHENTICATE CRAM-MD5");
			res = session.check!responseAuthenticate(t);
			stderr.writefln("authenticate cram first response: %s",res);
			enforce(res.status == ImapStatus.continue_, "login failure");
			auto hash = authCramMD5(login.username,login.password,res.value.strip);
			stderr.writefln("hhash: %s",hash);
			t = session.check!sendContinuation(hash);
			res = session.check!responseGeneric(t);
			stderr.writefln("response: %s",res);
			rl = res.status;
		}
		if (rl != ImapStatus.ok)
		{
			t = session.check!sendRequest(format!"LOGIN \"%s\" \"%s\""(login.username, login.password));
			res = session.check!responseGeneric(t);
			rl = res.status;
		}
		if (rl == ImapStatus.no)
		{
			auto err = format!"username %s or password rejected at %s\n"(login.username, session.server);
			errorf("username %s or password rejected at %s\n",login.username, session.server);
			session.closeConnection();
			// return session.setStatus(ImapStatus.no);
            throw new Exception(err);
		}
	} 

	t = session.check!sendRequest("CAPABILITY");
	res = session.check!responseCapability(t);

	if (session.capabilities.has(Capability.namespace) && session.options.namespace)
	{
		t = session.check!sendRequest("NAMESPACE");
		res = session.check!responseNamespace(t);
		rl = res.status;
	}

	if (session.selected != Mailbox.init)
	{
		t = session.check!sendRequest(format!"SELECT \"%s\""(session.selected.applyNamespace()));
		auto selectResult = session.responseSelect(t);
		enforce(selectResult.status == ImapStatus.ok);
		rl = selectResult.status;
	}

	return session.setStatus(rl);
}


@SILdoc("Logout from the IMAP server and disconnect")
int logout(ref Session session)
{

	if (responseGeneric(session, sendRequest(session, "LOGOUT")).status == ImapStatus.unknown) {
		//sessionDestroy(session);
	} else {
		closeConnection(session);
		// sessionDestroy(session);
	}
	return ImapStatus.ok;
}

///
struct MailboxImapStatus
{
	uint exists;
	uint recent;
	uint unseen;
	uint uidnext;
}

///
auto examine(ref Session session, Mailbox mbox)
{
	import std.format : format;
	auto request = format!`EXAMINE "%s"`(mbox);
	auto id = session.sendRequest(request);
	return session.responseExamine(id);
}

// MailboxImapStatus

@SILdoc("Get mailbox status")
auto status(ref Session session, Mailbox mbox)
{
	import std.format : format;
	import std.exception : enforce;
	enforce(session.imapProtocol == ImapProtocol.imap4Rev1, "status only implemented for Imap4Rev1 - try using examine");
	auto mailbox = mbox.toString();
	auto request = format!`STATUS "%s" (MESSAGES RECENT UNSEEN UIDNEXT)`(mailbox);
	auto id = session.sendRequest(request);
	return session.responseStatus(id,mailbox);
}


@SILdoc("Open mailbox in read-write mode")
auto select(ref Session session, Mailbox mailbox)
{
	import std.format : format;
	auto request = format!`SELECT "%s"`(mailbox.toString);
	auto id = session.sendRequest(request);
	auto ret = session.responseSelect(id);
	if (ret.status == ImapStatus.ok)
		session.selected = mailbox;
	return ret;
}


@SILdoc("Close examined/selected mailbox")
ImapResult raw(ref Session session, string command)
{
	auto id = sendRequest(session,command);
	auto response = responseGeneric(session,id);
	if (response.status == ImapStatus.ok && session.socket.isAlive)
	{
		session.close();
		session.selected = Mailbox.init;
	}
	return response;
}

@SILdoc("Close examined/selected mailbox")
ImapResult close(ref Session session)
{
	enum request = "CLOSE";
	auto id = sendRequest(session,request);
	auto response = responseGeneric(session,id);
	if (response.status == ImapStatus.ok && session.socket.isAlive)
	{
		session.close();
		session.selected = Mailbox.init;
	}
	return response;
}

@SILdoc("Remove all messages marked for deletion from selected mailbox")
ImapResult expunge(ref Session session)
{
	enum request = "EXPUNGE";
	auto id = sendRequest(session,request);
	return session.responseGeneric(id);
}

///
struct MailboxList
{
	string[] mailboxes;
	string[] folders;
}

@SILdoc("List all mailboxes")
auto list(ref Session session, string refer, string name)
{
	import std.format: format;
	auto request = format!`LIST "%s" "%s"`(refer,name);
	auto id = session.sendRequest(request);
	return session.responseList(id);
}


@SILdoc("List subscribed mailboxes")
auto lsub(ref Session session, string refer, string name)
{
	import std.format : format;
	auto request = format!`LIST "%s" "%s"`(refer,name);
	auto id = session.imapTry!sendRequest(request);
	return session.responseList(id);
}

@SILdoc("Search selected mailbox according to the supplied search criteria")
auto search(ref Session session, string criteria, string charset = null)
{
	import std.format : format;
	string s;

	s = (charset.length > 0) ? format!`UID SEARCH CHARSET "%s" %s`(charset, criteria) :
								format!`UID SEARCH %s`(criteria);

	auto t = session.imapTry!sendRequest(s);
	auto r = session.responseSearch(t);
	return r;
}

@SILdoc("Fetch the FLAGS, INTERNALDATE and RFC822.SIZE of the messages")
auto fetchFast(ref Session session, string mesg)
{
	import std.format : format;
	auto t = session.imapTry!sendRequest(format!"UID FETCH %s FAST"(mesg));
	auto r = session.responseFetchFast(t);
	return r;
}

@SILdoc("Fetch the FLAGS of the messages")
auto fetchFlags(ref Session session, string mesg)
{
	import std.format : format;
	auto t = session.imapTry!sendRequest(format!"UID FETCH %s FLAGS"(mesg));
	return session.responseFetchFlags(t);
}

@SILdoc("Fetch the INTERNALDATE of the messages")
auto fetchDate(ref Session session, string mesg)
{
	import std.format : format;
	auto request = format!"UID FETCH %s INTERNALDATE"(mesg);
	auto id = session.imapTry!sendRequest(request);
	return session.responseFetchDate(id);
}

@SILdoc("Fetch the RFC822.SIZE of the messages")
auto fetchSize(ref Session session, string mesg)
{
	import std.format : format;
	auto request = format!"UID FETCH %s RFC822.SIZE"(mesg);
	auto id = session.imapTry!sendRequest(request);
	return session.responseFetchSize(id);
}

@SILdoc("Fetch the BODYSTRUCTURE of the messages")
auto fetchStructure(ref Session session, string mesg)
{
	import std.format : format;
	auto request = format!"UID FETCH %s BODYSTRUCTURE"(mesg);
	auto id = session.imapTry!sendRequest(request);
	return session.responseFetchStructure(id);
}


@SILdoc("Fetch the BODY[HEADER] of the messages")
auto fetchHeader(ref Session session, string mesg)
{
	import std.format : format;

	auto id  = session.imapTry!sendRequest(format!`UID FETCH %s BODY.PEEK[HEADER]`(mesg));
	auto r = session.responseFetchBody(id);
	return r;
}


@SILdoc("Fetch the text, ie. BODY[TEXT], of the messages")
auto fetchRFC822(ref Session session, string mesg)
{
	import std.format : format;

	auto id  = session.imapTry!sendRequest(format!`UID FETCH %s RFC822`(mesg));
	auto r = session.responseFetchBody(id);
	return r;
}

@SILdoc("Fetch the text, ie. BODY[TEXT], of the messages")
auto fetchText(ref Session session, string mesg)
{
	import std.format : format;

	auto id  = session.imapTry!sendRequest(format!`UID FETCH %s BODY.PEEK[TEXT]`(mesg));
	auto r = session.responseFetchBody(id);
	return r;
}


@SILdoc("Fetch the specified header fields, ie. BODY[HEADER.FIELDS (<fields>)], of the messages")
auto fetchFields(ref Session session, string mesg, string headerFields)
{
	import std.format : format;

	auto id  = session.imapTry!sendRequest(format!`UID FETCH %s BODY.PEEK[HEADER.FIELDS (%s)]`(mesg, headerFields));
	auto r = session.responseFetchBody(id);
	return r;
}


@SILdoc("Fetch the specified message part, ie. BODY[<part>], of the messages")
auto fetchPart(ref Session session, string mesg, string part)
{
	import std.format : format;

	auto id  = session.imapTry!sendRequest(format!`UID FETCH %s BODY.PEEK[%s]`(mesg, part));
	auto r = session.responseFetchBody(id);
	return r;
}

@SILdoc("Add, remove or replace the specified flags of the messages")
auto store(ref Session session, string mesg, string mode, string flags)
{
	import std.format : format;
	import std.algorithm : canFind;
	import std.string : toLower, startsWith;
	import std.format : format;
	mode = mode.toLower();
	bool addMode = (mode.startsWith("add"));
	bool removeMode = (mode.startsWith("remove"));
	string useMode = addMode ? "+" : (removeMode ? "-" : "");

	auto t = session.imapTry!sendRequest(format!"UID STORE %s %sFLAGS.SILENT (%s)"(mesg, useMode,flags));
	auto r = session.responseGeneric(t);

	if (canFind(flags,`\Deleted`) && session.options.expunge)
	{
		t = session.imapTry!sendRequest("EXPUNGE");
		session.responseGeneric(t);
	}
	return r;
}


@SILdoc("Copy the specified messages to another mailbox")
auto copy(ref Session session, string mesg, Mailbox mailbox)
{
	import std.format : format;

	auto t = session.imapTry!sendRequest(format!`UID COPY %s "%s"`(mesg, mailbox.toString));
	auto r = session.imapTry!responseGeneric(t);
	if (r.status == ImapStatus.tryCreate)
	{
		t = session.imapTry!sendRequest(format!`CREATE "%s"`(mailbox.toString));
		session.imapTry!responseGeneric(t);
		if (session.options.subscribe)
		{
			t = session.imapTry!sendRequest(format!`SUBSCRIBE "%s"`(mailbox.toString));
			session.imapTry!responseGeneric(t);
		}
		t = session.imapTry!sendRequest(format!`UID COPY %s "%s"`(mesg,mailbox.toString));
		r = session.imapTry!responseGeneric(t);
	}
	return r;
}

/+
///	Append supplied message to the specified mailbox.
auto append(ref Session session, Mailbox mbox, string mesg, size_t mesglen, string flags, string date)
{
	auto request = format!`CREATE "%s"`(mailbox);
	auto id = sendRequest(session,request);
	return responseGeneric(session,id);

	t = session.imapTry!sendRequest(format!"APPEND \"%s\"%s%s%s%s%s%s {%d}"(m,
	    (flags ? " (" : ""), (flags ? flags : ""),
	    (flags ? ")" : ""), (date ? " \"" : ""),
	    (date ? date : ""), (date ? "\"" : "")));

	r = session.imapTry!responseContinuation(t);
	if (r == ImapStatus.continue_) {
		session.imapTry!sendContinuation(mesg, mesglen);
		r = imaptry!responseGeneric(t);
	}

	if (r == ImapStatus.tryCreate) {
		t = session.imapTry!sendRequest(format!`CREATE "%s"`(m));
		r = session.imapTry!responseGeneric(t);
		if (get_option_boolean("subscribe")) {
			t = session.imapTry!sendRequest(format!`SUBSCRIBE "%s"`(m));
			session.imapTry!responseGeneric(t);
		}
		TRY(t = sendRequest(session, "APPEND \"%s\"%s%s%s%s%s%s {%d}", m,
		    (flags ? " (" : ""), (flags ? flags : ""),
		    (flags ? ")" : ""), (date ? " \"" : ""),
		    (date ? date : ""), (date ? "\"" : ""), mesglen));
		r = session.imapTry!responseContinuation(t);
		if (r == ImapStatus.continue_) {
			TRY(send_continuation(session, mesg, mesglen)); 
			TRY(r = responseGeneric(session, t));
		}
	}

	return r;
}
+/

@SILdoc("Create the specified mailbox")
auto create(ref Session session, Mailbox mailbox)
{
	import std.format : format;
	auto request = format!`CREATE "%s"`(mailbox.toString);
	auto id = session.sendRequest(request);
	return session.responseGeneric(id);
}


@SILdoc("Delete the specified mailbox")
auto delete_(ref Session session, Mailbox mailbox)
{
	import std.format : format;
	auto request = format!`DELETE "%s"`(mailbox.toString);
	auto id = session.sendRequest(request);
	return session.responseGeneric(id);
}

@SILdoc("Rename a mailbox")
auto rename(ref Session session, Mailbox oldmbox, Mailbox newmbox)
{
	import std.format : format;
	auto request = format!`RENAME "%s" "%s"`(oldmbox.toString,newmbox.toString);
	auto id = session.sendRequest(request);
	return session.responseGeneric(id);
}

@SILdoc("Subscribe to the specified mailbox")
auto subscribe(ref Session session, Mailbox mailbox)
{
	import std.format : format;
	auto request = format!`SUBSCRIBE "%s"`(mailbox.toString);
	auto id = session.sendRequest(request);
	return session.responseGeneric(id);
}


@SILdoc("Unsubscribe from the specified mailbox")
auto unsubscribe(ref Session session, Mailbox mailbox)
{
	import std.format : format;
	auto request = format!`UNSUBSCRIBE"%s"`(mailbox.toString);
	auto id = session.sendRequest(request);
	return session.responseGeneric(id);
}

@SILdoc("IMAP idle")
auto idle(ref Session session)
{
	import std.stdio;
	Tag t;
	ImapResult r, ri;

	if (!session.capabilities.has(Capability.idle))
		return ImapResult(ImapStatus.bad,"");

	do
	{
		stderr.writefln("inner loop for idle");
		t = session.sendRequest("IDLE");
		ri = session.responseIdle(t);
		r = session.responseContinuation(t);
		stderr.writefln("sendRequest - responseContinuation was %s",r);
		if (r.status == ImapStatus.continue_)
		{
			ri = session.responseIdle(t);
			stderr.writefln("responseIdle result was %s",ri);
			session.sendContinuation("DONE");
			stderr.writefln("continuation result was %s",ri);
			r = session.responseGeneric(t);
			stderr.writefln("reponseGenericresult was %s",r);
		}
	} while (ri.status != ImapStatus.untagged);
	stderr.writefln("returning %s",ri);

	return ri;
}

///
enum SearchField
{
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

struct SearchParameter
{
    string fieldName;
    //Variable value;
}




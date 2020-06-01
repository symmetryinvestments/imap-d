module jmap.api;
import jmap.types;
static import jmap.types;

version(SIL)
{
	import kaleidic.sil.lang.handlers:Handlers;
	import kaleidic.sil.lang.types : Variable,Function,SILdoc;

	void registerHandlersJmap(ref Handlers handlers)
	{
		import std.meta : AliasSeq;
		handlers.openModule("jmap");
		scope(exit) handlers.closeModule();

		static foreach(T; AliasSeq!(Credentials, JmapSessionParams, Session,Mailbox,MailboxRights,MailboxSortProperty,Filter,FilterOperator,FilterOperatorKind,FilterCondition,Comparator))
				handlers.registerType!T;

		static foreach(F; AliasSeq!(getSession, getSessionJson, wellKnownJmap,operatorAsFilter,conditionAsFilter))
			handlers.registerHandler!F;
	}
}



struct JmapSessionParams
{
	Credentials credentials;
	string uri;
}

auto wellKnownJmap(string baseURI)
{
	import std.format : format;
	import std.algorithm : endsWith;
	return baseURI.endsWith(".well-known/jmap") ? baseURI : format!"%s/.well-known/jmap"(baseURI);
}

string getSessionJson(JmapSessionParams params)
{
	return getSessionJson(params.uri,params.credentials);
}

private string getSessionJson(string uri, Credentials credentials)
{
	import requests : Request, BasicAuthentication;
	auto req = Request();
	req.authenticator = new BasicAuthentication(credentials.user,credentials.pass);
	auto result = cast(string) req.get(uri.wellKnownJmap).responseBody.data.idup;
	return result;
}

Session getSession(JmapSessionParams params)
{
	import asdf;
	import std.string : strip;
	import std.exception : enforce;
	import std.algorithm : startsWith;
	import std.stdio : writeln;

	auto json = getSessionJson(params).strip;
	writeln(json);
	enforce(json.startsWith("{") || json.startsWith("["), "invalid json response: \n" ~ json);
	auto ret = deserialize!Session(json);
	ret.credentials = params.credentials;
	return ret;
}

/+
auto getMailboxes(string uri, Credentials credentials)
{
	auto req = Request();
	req.authenticator = new BasicAuthentication(credentials.user,credentials.pass);
	auto query = "getMailboxes",{},"#9"
	auto result = cast(string) req.post(uri,query).data.idup;
	return result;
}
+/


module jmap.types;
import std.datetime : SysTime;
import std.typecons : Nullable;
import kaleidic.sil.lang.types : Variable,Function,SILdoc;
import asdf;
import kaleidic.sil.std.core.json : toVariable, toJsonString;

struct Credentials
{
	string user;
	string pass;
}

alias Url = string;
alias Emailer = string;
alias Attachment = ubyte[];
alias ModSeq = ulong;

alias Set = string[bool];

@("urn:ietf:params:jmap:core")
struct SessionCoreCapabilities
{
	uint maxSizeUpload;
	uint maxConcurrentUpload;	
	uint maxSizeRequest;
	uint maxConcurrentRequests;
	uint maxCallsInRequest;
	uint maxObjectsInGet;
	uint maxObjectsInSet;
	string[] collationAlgorithms;
}
																															    
															 
@("urn:ietf:params:jmap:mail")
enum EmailQuerySortOption
{
	receivedAt,
	from,
	to,
	subject,
	size,

	@serializationKeys("header.x-spam-score")
	headerXSpamScore,
}

struct AccountParams
{
	//EmailQuerySortOption[] emailQuerySortOptions;
	string[] emailQuerySortOptions;
	Nullable!int maxMailboxDepth;
	Nullable!int maxMailboxesPerEmail;
	Nullable!int maxSizeAttachmentsPerEmail;
	Nullable!int maxSizeMailboxName;
	bool mayCreateTopLevelMailbox;
}

struct SubmissionParams
{
   int maxDelayedSend;
   string[] submissionExtensions;
}

struct AccountCapabilities
{
	@serializationKeys("urn:ietf:params:jmap:mail")
	AccountParams accountParams;

	@serializationKeys("urn:ietf:params:jmap:submission")
	SubmissionParams submissionParams;

	//private Asdf vacationResponseParams;

	private Variable[string] allAccountCapabilities;

	void finalizeDeserialization(Asdf data)
	{
		import asdf : deserialize, Asdf;

		foreach(el;data.byKeyValue)
			allAccountCapabilities[el.key] = el.value.get!Asdf(Asdf.init).toVariable;
	}
}

struct Account
{
	string name;
	bool isPersonal;
	bool isReadOnly;

	bool isArchiveUser = false;
	AccountCapabilities accountCapabilities;
	string[string] primaryAccounts;
}

struct Session
{
	SessionCoreCapabilities coreCapabilities;

	Account[string] accounts;
	string[string] primaryAccounts;
	string username;
	Url apiUrl;
	Url downloadUrl;
	Url uploadUrl;
	Url eventSourceUrl;
	string state;
	private Asdf[string] capabilities;
	package Credentials credentials;
	private string activeAccountId_;

	private string activeAccountId()
	{
		import std.format : format;
		import std.exception : enforce;
		import std.string : join;
		import std.range : front;
		import std.algorithm : canFind;

		if (activeAccountId_.length == 0)
		{
			enforce(accounts.keys.length == 1,
					format!"multiple accounts - [%s] - and you must call setActiveAccount to pick one"
						(accounts.keys.join(",")));
			this.activeAccountId_ = accounts.keys.front;
		}

		enforce(accounts.keys.canFind(activeAccountId_,
					format!"active account ID is set to %s but it is not found amongst account IDs: [%s]"
						(activeAccountId_, accounts.keys.join(","))));
		return activeAccountId_;
	}

	string[] listCapabilities()
	{
		return capabilities.keys;
	}

	string[] listAccounts()
	{
		import std.algorithm : map;
		import std.array : array;
		return accounts.keys.map!(key => accounts[key].name).array;
	}

	Account getActiveAccountInfo()
	{
		import std.exception : enforce;
		auto p = activeAccountId() in accounts;
		enforce(p !is null, "no currently active account");
		return *p;
	}

	@SILdoc("set active account - name is the account name, not the id")
	Session setActiveAccount(string name)
	{
		import std.format : format;
		import std.exception : enforce;
		import std.format : format;

		foreach(kv; accounts.byKeyValue)
		{
			if (kv.value.name == name)
			{
				this.activeAccountId_ = kv.key;
				return this;
			}
		}
		throw new Exception(format!"account %s not found"(name));
	}


	void finalizeDeserialization(Asdf data)
	{
		import asdf : deserialize, Asdf;

		foreach(el;data["capabilities"].byKeyValue)
			capabilities[el.key] = el.value.get!Asdf(Asdf.init);
		this.coreCapabilities = deserialize!SessionCoreCapabilities(capabilities["urn:ietf:params:jmap:core"]);
	}

	private Asdf post(JmapRequest request)
	{
		import asdf;
	    import requests : Request, BasicAuthentication;
		auto json = serializeToJson(request); // serializeToJsonPretty
	    auto req = Request();
	    req.authenticator = new BasicAuthentication(credentials.user,credentials.pass);
	    auto result = cast(string) req.post(apiUrl, json,"application/json").responseBody.data.idup;
	    return parseJson(result);
	}

	Variable uploadBinary(string data, string type = "application/binary")
	{
		import std.string : replace;
		import asdf;
	    import requests : Request, BasicAuthentication;
		auto uri = this.uploadUrl.replace("{accountId}",this.activeAccountId());
	    auto req = Request();
	    req.authenticator = new BasicAuthentication(credentials.user,credentials.pass);
	    auto result = cast(string) req.post(uploadUrl, data,type).responseBody.data.idup;
		return parseJson(result).toVariable;
	}

	string downloadBinary(string blobId, string type = "application/binary", string name = "default.bin", string downloadUrl=null)
	{
		import std.string : replace;
		import asdf;
	    import requests : Request, BasicAuthentication;
		import std.algorithm : canFind;

		downloadUrl = (downloadUrl.length == 0) ? this.downloadUrl : downloadUrl;
		downloadUrl = downloadUrl
						.replace("{accountId}",this.activeAccountId().uriEncode)
						.replace("{blobId}",blobId.uriEncode)
						.replace("{type}",type.uriEncode)
						.replace("{name}",name.uriEncode);

		downloadUrl = downloadUrl ~  "&accept=" ~ type.uriEncode;
	    auto req = Request();
	    req.authenticator = new BasicAuthentication(credentials.user,credentials.pass);
	    auto result = cast(string) req.get(downloadUrl).responseBody.data.idup;
		return result;
	}
	


	Variable get(string type, string[] ids, Variable properties = Variable.init, Variable[string] additionalArguments = (Variable[string]).init)
	{
		return getRaw(type,ids,properties, additionalArguments).toVariable;
	}

	Asdf getRaw(string type, string[] ids, Variable properties = Variable.init, Variable[string] additionalArguments = (Variable[string]).init)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto props =  parseJson(toJsonString(properties));
		auto invocation = Invocation.get(type,activeAccountId(), invocationId,ids, props,additionalArguments);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}


	Mailbox[] getMailboxes()
	{
		import std.range : front, dropOne;
		auto asdf = getRaw("Mailbox",null);
		return deserialize!(Mailbox[])(asdf["methodResponses"].byElement.front.byElement.dropOne.front["list"]);
	}

	Variable getContact(string[] ids, Variable properties = Variable([]), Variable[string] additionalArguments =(Variable[string]).init)
	{
		import std.range : front, dropOne;
		return Variable(
				this.get("Contact",ids,properties, additionalArguments)
				.get!(Variable[string])
				["methodResponses"]
				.get!(Variable[])
				.front
				.get!(Variable[])
				.front
				.get!(Variable[])
				.dropOne
				.front
		);
	}

	Variable getEmails(string[] ids, Variable properties = Variable([ "id", "blobId", "threadId", "mailboxIds", "keywords", "size", "receivedAt", "messageId", "inReplyTo", "references", "sender", "from", "to", "cc", "bcc", "replyTo", "subject", "sentAt", "hasAttachment", "preview", "bodyValues", "textBody", "htmlBody", "attachments" ]), Variable bodyProperties = Variable(["all"]),
			bool fetchTextBodyValues = true, bool fetchHTMLBodyValues = true, bool fetchAllBodyValues = true)
	{
		import std.range : front, dropOne;
		return Variable(
				this.get(
					"Email",ids,properties, [
						"bodyProperties":bodyProperties,
						"fetchTextBodyValues":fetchTextBodyValues.Variable,
						"fetchAllBodyValues":fetchAllBodyValues.Variable,
						"fetchHTMLBodyValues": fetchHTMLBodyValues.Variable,
					]
				)
				.get!(Variable[string])
				["methodResponses"] //,(Variable[]).init)
				.get!(Variable[])
				.front
				.get!(Variable[])
				.dropOne
				.front
				.get!(Variable[string])
				["list"]
		);
	}


	Asdf changesRaw(string type, string sinceState, Nullable!uint maxChanges = (Nullable!uint).init, Variable[string] additionalArguments = (Variable[string]).init)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto invocation = Invocation.changes(type,activeAccountId(), invocationId,sinceState,maxChanges,additionalArguments);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable changes(string type, string sinceState, Nullable!uint maxChanges = (Nullable!uint).init, Variable[string] additionalArguments = null)
	{
		return changesRaw(type,sinceState,maxChanges,additionalArguments).toVariable;
	}

	Asdf setRaw(string type, string ifInState = null, Variable[string] create = null, Variable[string][string] update = null, string[] destroy_ = null, Variable[string] additionalArguments = (Variable[string]).init)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto createAsdf = parseJson(toJsonString(Variable(create)));
		auto updateAsdf = parseJson(toJsonString(Variable(update)));
		auto invocation = Invocation.set(type,activeAccountId(), invocationId,ifInState,createAsdf,updateAsdf,destroy_,additionalArguments);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable set(string type, string ifInState = null, Variable[string] create = null, Variable[string][string] update = null, string[] destroy_ = null, Variable[string] additionalArguments = (Variable[string]).init)
	{
		return setRaw(type,ifInState,create,update,destroy_,additionalArguments).toVariable;
	}

	Asdf copyRaw(string type, string fromAccountId, string ifFromInState = null, string ifInState = null, Variable[string] create = null, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null, Variable[string] additionalArguments = (Variable[string]).init)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto createAsdf = parseJson(toJsonString(Variable(create)));
		auto invocation = Invocation.copy(type,fromAccountId, invocationId,ifFromInState,activeAccountId,ifInState,createAsdf,onSuccessDestroyOriginal,destroyFromIfInState);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable copy(string type, string fromAccountId, string ifFromInState = null, string ifInState = null, Variable[string] create = null, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null, Variable[string] additionalArguments = (Variable[string]).init)
	{
		return copyRaw(type,fromAccountId,ifFromInState,ifInState,create,onSuccessDestroyOriginal,destroyFromIfInState,additionalArguments).toVariable;
	}


	Asdf queryRaw(string type, Variable filter, Variable sort, int position, string anchor=null, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false, Variable[string] additionalArguments = (Variable[string]).init)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto filterAsdf = parseJson(toJsonString(filter));
		auto sortAsdf = parseJson(toJsonString(sort));
		auto invocation = Invocation.query(type,activeAccountId,invocationId,filterAsdf,sortAsdf,position,anchor,anchorOffset,limit,calculateTotal, additionalArguments);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable query(string type, Variable filter, Variable sort, int position, string anchor, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false, Variable[string] additionalArguments = (Variable[string]).init)
	{
		return queryRaw(type, filter, sort, position, anchor, anchorOffset, limit,calculateTotal,additionalArguments).toVariable;
	}

	Asdf queryChangesRaw(string type, Variable filter, Variable sort, string sinceQueryState, Nullable!uint maxChanges = (Nullable!uint).init, Nullable!string upToId = (Nullable!string).init, bool calculateTotal = false, Variable[string] additionalArguments = (Variable[string]).init)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto filterAsdf = parseJson(toJsonString(filter));
		auto sortAsdf = parseJson(toJsonString(sort));
		auto invocation = Invocation.queryChanges(type,activeAccountId,invocationId,filterAsdf,sortAsdf,sinceQueryState,maxChanges,upToId,calculateTotal,additionalArguments);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable queryChanges(string type, Variable filter, Variable sort, string sinceQueryState,Nullable!uint maxChanges = (Nullable!uint).init, Nullable!string upToId = (Nullable!string).init, bool calculateTotal = false, Variable[string] additionalArguments = (Variable[string]).init)
	{
		return queryChangesRaw(type, filter, sort, sinceQueryState,maxChanges,upToId,calculateTotal,additionalArguments).toVariable;
	}
}

struct Email
{
	string id;
	string blobId;
	string threadId;
	Set mailboxIds;
	Set keywords;
	Emailer[] from;
	Emailer[] to;
	string subject;
	SysTime date;
	int size;
	string preview;
	Attachment[] attachments;

	ModSeq createdModSeq;
	ModSeq updatedModSeq;
	Nullable!SysTime deleted;
}

struct ThreadEmail
{
	string id;
	string[] mailboxIds;
	bool isUnread;
	bool isFlagged;
}

struct Thread
{
	string id;
	ThreadEmail[] emails;
	ModSeq createdModSeq;
	ModSeq updatedModSeq;
	Nullable!SysTime deleted;
}

struct MailboxRights
{
	bool mayReadItems;
	bool mayAddItems;
	bool mayRemoveItems;
	bool mayCreateChild;
	bool mayRename;
	bool mayDelete;
	bool maySetKeywords;
	bool maySubmit;
	bool mayAdmin;
	bool maySetSeen;
}

struct Mailbox
{
	string id;
	string name;
	string parentId;
	string role;
	int sortOrder;
	int totalEmails;
	int unreadEmails;
	int totalThreads;
	int unreadThreads;
	MailboxRights myRights;
	bool autoPurge;
	int hidden;
	string identityRef;
	bool learnAsSpam;
	int purgeOlderThanDays;
	bool isCollapsed;
	bool isSubscribed;
	bool suppressDuplicates;
	bool autoLearn;
	MailboxSortProperty[] sort;
}

struct MailboxSortProperty
{
	string property;
	bool isAscending;
}


struct MailboxEmailList
{
	string id;
	string messageId;
	string threadId;
	ModSeq updatedModSeq;
	SysTime created;
	Nullable!SysTime deleted;
}

struct EmailChangeLogEntry
{
	string id;
	string[] created;
	string[] updated;
	string[] destroyed;
}

struct ThreadChangeLogEntry
{
	string id;
	string[] created;
	string[] updated;
	string[] destroyed;
}

struct ThreadRef
{
	string id;
	string threadId;
	SysTime lastSeen;
}

struct HighLowModSeqCache
{
	ModSeq highModSeq;
	ModSeq highModSeqEmail;
	ModSeq highModSeqThread;
	ModSeq lowModSeqEmail;
	ModSeq lowModSeqThread;
	ModSeq lowModSeqMailbox;
}

/+
{
   "accounts" : {
      "u1f4140ae" : {
         "accountCapabilities" : {
            "urn:ietf:params:jmap:mail" : {
               "emailQuerySortOptions" : [
                  "receivedAt",
                  "from",
                  "to",
                  "subject",
                  "size",
                  "header.x-spam-score"
               ],
               "maxMailboxDepth" : null,
               "maxMailboxesPerEmail" : 1000,
               "maxSizeAttachmentsPerEmail" : 50000000,
               "maxSizeMailboxName" : 490,
               "mayCreateTopLevelMailbox" : true
            },
            "urn:ietf:params:jmap:submission" : {
               "maxDelayedSend" : 44236800,
               "submissionExtensions" : []
            },
            "urn:ietf:params:jmap:vacationresponse" : {}
         },
         "isArchiveUser" : false,
         "isPersonal" : true,
         "isReadOnly" : false,
         "name" : "laeeth@kaleidic.io"
      }
   },
   "apiUrl" : "https://jmap.fastmail.com/api/",
   "capabilities" : {
      "urn:ietf:params:jmap:core" : {
         "collationAlgorithms" : [
            "i;ascii-numeric",
            "i;ascii-casemap",
            "i;octet"
         ],
         "maxCallsInRequest" : 64,
         "maxConcurrentRequests" : 10,
         "maxConcurrentUpload" : 10,
         "maxObjectsInGet" : 1000,
         "maxObjectsInSet" : 1000,
         "maxSizeRequest" : 10000000,
         "maxSizeUpload" : 250000000
      },
      "urn:ietf:params:jmap:mail" : {},
      "urn:ietf:params:jmap:submission" : {},
      "urn:ietf:params:jmap:vacationresponse" : {}
   },
   "downloadUrl" : "https://jmap.fastmail.com/download/{accountId}/{blobId}/{name}",
   "eventSourceUrl" : "https://jmap.fastmail.com/event/",
   "primaryAccounts" : {
      "urn:ietf:params:jmap:mail" : "u1f4140ae",
      "urn:ietf:params:jmap:submission" : "u1f4140ae",
      "urn:ietf:params:jmap:vacationresponse" : "u1f4140ae"
   },
   "state" : "cyrus-12046746;p-5;vfs-0",
   "uploadUrl" : "https://jmap.fastmail.com/upload/{accountId}/",
   "username" : "laeeth@kaleidic.io"
}
+/

void serializeAsdf(S)(ref S ser, AsdfNode node) pure
{
	if (node.isLeaf())
		serializeAsdf(ser,node.data);

	auto objState = ser.objectBegin();
	foreach(kv;node.children.byKeyValue)
	{
		ser.putKey(kv.key);
		serializeAsdf(ser,kv.value);
	}
	ser.objectEnd(objState);
}

void serializeAsdf(S)(ref S ser, Asdf el) pure
{
	final switch(el.kind)
	{
		case Asdf.Kind.null_:
			ser.putValue(null);
			break;

		case Asdf.Kind.true_:
			ser.putValue(true);
			break;

		case Asdf.Kind.false_:
			ser.putValue(false);
			break;

		case Asdf.Kind.number:
			ser.putValue(el.get!double(double.nan));
			break;

		case Asdf.Kind.string:
			ser.putValue(el.get!string(null));
			break;

		case Asdf.Kind.array:
			auto arrayState = ser.arrayBegin();
			foreach(arrEl;el.byElement)
			{
				ser.elemBegin();
				serializeAsdf(ser,arrEl);
			}
			ser.arrayEnd(arrayState);
			break;

		case Asdf.Kind.object:
			auto objState = ser.objectBegin();
			foreach(kv;el.byKeyValue)
			{
				ser.putKey(kv.key);
				serializeAsdf(ser,kv.value);
			}
			ser.objectEnd(objState);
			break;
	}
}



struct Invocation
{
	string name;
	Asdf arguments;
	string id;

	void serialize(S)(ref S ser) pure
	{
		auto outerState = ser.arrayBegin();
		ser.elemBegin();
		ser.putValue(name);
		ser.elemBegin();
		auto state = ser.objectBegin();
		foreach(el;arguments.byKeyValue)
		{
			ser.putKey(el.key);
			serializeAsdf(ser,el.value);
		}
		ser.objectEnd(state);
		ser.elemBegin();
		ser.putValue(id);
		ser.arrayEnd(outerState);
	}


	static Invocation get(string type, string accountId, string invocationId = null, string[] ids = null, Asdf properties = Asdf.init, Variable[string] additionalArguments = (Variable[string]).init)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["ids"] = AsdfNode(ids.serializeToAsdf);
		arguments["properties"] = AsdfNode(properties);
		foreach(kv;additionalArguments.byKeyValue)
			arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

		Invocation ret = {
			name: type ~ "/get",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}

	static Invocation changes(string type, string accountId, string invocationId, string sinceState, Nullable!uint maxChanges, Variable[string] additionalArguments = (Variable[string]).init)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["sinceState"] = AsdfNode(sinceState.serializeToAsdf);
		arguments["maxChanges"] = AsdfNode(maxChanges.serializeToAsdf);
		foreach(kv;additionalArguments.byKeyValue)
			arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

		Invocation ret = {
			name: type ~ "/changes",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}


	static Invocation set(string type, string accountId, string invocationId = null, string ifInState = null, Asdf create = Asdf.init, Asdf update = Asdf.init, string[] destroy_ = null, Variable[string] additionalArguments = (Variable[string]).init)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["ifInState"] = AsdfNode(ifInState.serializeToAsdf);
		arguments["create"] = AsdfNode(create);
		arguments["update"] = AsdfNode(update);
		arguments["destroy"] = AsdfNode(destroy_.serializeToAsdf);
		foreach(kv;additionalArguments.byKeyValue)
			arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

		Invocation ret = {
			name: type ~ "/set",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}

	static Invocation copy(string type, string fromAccountId, string invocationId = null, string ifFromInState = null, string accountId = null, string ifInState = null, Asdf create = Asdf.init, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null, Variable[string] additionalArguments = (Variable[string]).init)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["fromAccountId"] =AsdfNode(fromAccountId.serializeToAsdf);
		arguments["ifFromInState"] = AsdfNode(ifFromInState.serializeToAsdf);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["ifInState"] = AsdfNode(ifInState.serializeToAsdf);
		arguments["create"] = AsdfNode(create);
		arguments["onSuccessDestroyOriginal"] = AsdfNode(onSuccessDestroyOriginal.serializeToAsdf);
		arguments["destroyFromIfInState"] = AsdfNode(destroyFromIfInState.serializeToAsdf);
		foreach(kv;additionalArguments.byKeyValue)
			arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

		Invocation ret = {
			name: type ~ "/copy",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}

	static Invocation query(string type, string accountId, string invocationId, Asdf filter, Asdf sort, int position, string anchor=null, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false, Variable[string] additionalArguments = (Variable[string]).init)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["filter"] = AsdfNode(filter);
		arguments["sort"] = AsdfNode(sort);
		arguments["position"] = AsdfNode(position.serializeToAsdf);
		arguments["anchor"] = AsdfNode(anchor.serializeToAsdf);
		arguments["anchorOffset"] = AsdfNode(anchorOffset.serializeToAsdf);
		arguments["limit"] = AsdfNode(limit.serializeToAsdf);
		arguments["calculateTotal"] = AsdfNode(calculateTotal.serializeToAsdf);
		foreach(kv;additionalArguments.byKeyValue)
			arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

		Invocation ret = {
			name: type ~ "/query",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}

	static Invocation queryChanges(string type, string accountId, string invocationId, Asdf filter, Asdf sort, string sinceQueryState, Nullable!uint maxChanges = (Nullable!uint).init, Nullable!string upToId = (Nullable!string).init, bool calculateTotal = false, Variable[string] additionalArguments = (Variable[string]).init)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["filter"] = AsdfNode(filter);
		arguments["sort"] = AsdfNode(sort);
		arguments["sinceQueryState"] = AsdfNode(sinceQueryState.serializeToAsdf);
		arguments["maxChanges"] = AsdfNode(maxChanges.serializeToAsdf);
		arguments["upToId"] = AsdfNode(upToId.serializeToAsdf);
		arguments["calculateTotal"] = AsdfNode(calculateTotal.serializeToAsdf);
		foreach(kv;additionalArguments.byKeyValue)
			arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

		Invocation ret = {
			name: type ~ "/queryChanges",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}
}

enum FilterOperatorKind
{
	and,
	or,
	not,
}

interface Filter
{
}

class FilterOperator : Filter
{
	FilterOperatorKind operator;
	Filter[] conditions;
}

class FilterCondition : Filter
{
	Variable filterCondition;
}

Filter operatorAsFilter(FilterOperator filterOperator)
{
	return cast(Filter) filterOperator;
}

Filter conditionAsFilter(FilterCondition filterCondition)
{
	return cast(Filter) filterCondition;
}


struct Comparator
{
	string property;
	bool isAscending = true;
	string collation = null;
}

	
struct JmapRequest
{
	string[] using;
	Invocation[] methodCalls;
	string[string] createdIds = null;
}

struct JmapResponse
{
	Invocation[] methodResponses;
	string[string] createdIds;
	string sessionState;
}

struct JmapResponseError
{
	string type;
	int status;
	string detail;
}

struct ResultReference
{
	string resultOf;
	string name;
	string path;
}


struct Address
{
	string type;
	string label; // Nullable!string label;
	string street;
	string locality;
	string region;
	string postcode;
	string country;
	bool isDefault;
}

struct JmapFile
{
	string blobId;
	string type;
	string name;
	Nullable!uint size;
}

struct ContactInformation
{
	string type;
	string label;
	string value;
	bool isDefault;
}


struct Contact
{
	string id;
	bool isFlagged;
	JmapFile avatar;
	string prefix;
	string firstName;
	string lastName;
	string suffix;
	string nickname;
	string birthday;
	string anniversary;
	string company;
	string department;
	string jobTitle;
	ContactInformation[] emails;
	ContactInformation[] phones;
	ContactInformation[] online;
	Address[] addresses;
	string notes;
}

struct ContactGroup
{
	string id;
	string name;
	string[] ids;
}

string uriEncode(const(char)[] s)
{
	import std.string : replace;

	return  s.replace("!","%21").replace("#","%23").replace("$","%24").replace("&","%26").replace("'","%27")
			.replace("(","%28").replace(")","%29").replace("*","%2A").replace("+","%2B").replace(",","%2C")
			.replace("-","%2D").replace(".","%2E").replace("/","%2F").replace(":","%3A").replace(";","%3B")
			.replace("=","%3D").replace("?","%3F").replace("@","%40").replace("[","%5B").replace("]","%5D")
			.idup;
}

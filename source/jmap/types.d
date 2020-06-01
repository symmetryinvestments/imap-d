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

	//private Asdf[string] extraAccountCapabilities;
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

	string[] listCapabilities()
	{
		return capabilities.keys;
	}

	void finalizeDeserialization(Asdf data)
	{
		import asdf : deserialize, Asdf;
		import std.stdio : writeln;

		foreach(el;data["capabilities"].byKeyValue)
			capabilities[el.key] = el.value.get!Asdf(Asdf.init);
		//writeln(data);
		//writeln(data["capabilities"]["urn:ietf:params:jmap:core"]);
		//writeln(capabilities["urn:ietf:params:jmap:core"]);
		this.coreCapabilities = deserialize!SessionCoreCapabilities(capabilities["urn:ietf:params:jmap:core"]);
	}

	private Asdf post(JmapRequest request)
	{
		import asdf;
	    import requests : Request, BasicAuthentication;
		import std.stdio;
		auto json = serializeToJsonPretty(request);
		stderr.writeln(json);
	    auto req = Request();
	    req.authenticator = new BasicAuthentication(credentials.user,credentials.pass);
	    auto result = cast(string) req.post(apiUrl, json,"application/json").responseBody.data.idup;
		stderr.writeln(result);
	    return parseJson(result);
	}


	Variable get(string type, string accountId, string[] ids, Variable properties = Variable.init)
	{
		return getRaw(type,accountId,ids,properties).toVariable;
	}

	Asdf getRaw(string type, string accountId, string[] ids, Variable properties = Variable.init)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto props =  parseJson(toJsonString(properties));
		auto invocation = Invocation.get(type,accountId, invocationId,ids, props);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}


	Mailbox[] getMailboxes(string accountId)
	{
		import std.range : front, dropOne;
		auto asdf = getRaw("Mailbox",accountId,null);
		return deserialize!(Mailbox[])(asdf["methodResponses"].byElement.front.byElement.dropOne.front["list"]);
	}

	Asdf changesRaw(string type, string accountId, string sinceState, Nullable!uint maxChanges = (Nullable!uint).init)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto invocation = Invocation.changes(type,accountId, invocationId,sinceState,maxChanges);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable changes(string type, string accountId, string sinceState, Nullable!uint maxChanges = (Nullable!uint).init)
	{
		return changesRaw(type,accountId,sinceState,maxChanges).toVariable;
	}

	Asdf setRaw(string type, string accountId, string ifInState = null, Variable[string] create = null, Variable[string][string] update = null, string[] destroy_ = null)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto createAsdf = parseJson(toJsonString(Variable(create)));
		auto updateAsdf = parseJson(toJsonString(Variable(update)));
		auto invocation = Invocation.set(type,accountId, invocationId,ifInState,createAsdf,updateAsdf,destroy_);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable set(string type, string accountId, string ifInState = null, Variable[string] create = null, Variable[string][string] update = null, string[] destroy_ = null)
	{
		return setRaw(type,accountId,ifInState,create,update,destroy_).toVariable;
	}

	Asdf copyRaw(string type, string fromAccountId, string ifFromInState = null, string accountId = null, string ifInState = null, Variable[string] create = null, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto createAsdf = parseJson(toJsonString(Variable(create)));
		auto invocation = Invocation.copy(type,fromAccountId, invocationId,ifFromInState,accountId,ifInState,createAsdf,onSuccessDestroyOriginal,destroyFromIfInState);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable copy(string type, string fromAccountId, string ifFromInState = null, string accountId = null, string ifInState = null, Variable[string] create = null, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null)
	{
		return copyRaw(type,fromAccountId,ifFromInState,accountId,ifInState,create,onSuccessDestroyOriginal,destroyFromIfInState).toVariable;
	}


	Asdf queryRaw(string type, string accountId, Variable filter, Variable sort, int position, string anchor=null, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto filterAsdf = parseJson(toJsonString(filter));
		import std.stdio;
		//writeln(filterAsdf);
		auto sortAsdf = parseJson(toJsonString(sort));
		//writeln(sortAsdf);
		auto invocation = Invocation.query(type,accountId,invocationId,filterAsdf,sortAsdf,position,anchor,anchorOffset,limit,calculateTotal);
		writeln(invocation);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		import std.stdio;
		writeln(request);
		return post(request);
	}

	Variable query(string type, string accountId, Variable filter, Variable sort, int position, string anchor, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false)
	{
		return queryRaw(type, accountId, filter, sort, position, anchor, anchorOffset, limit,calculateTotal).toVariable;
	}

	Asdf queryChangesRaw(string type, string accountId, Variable filter, Variable sort, string sinceQueryState, Nullable!uint maxChanges = (Nullable!uint).init, Nullable!string upToId = (Nullable!string).init, bool calculateTotal = false)
	{
		import std.algorithm : map;
		import std.array : array;
		auto invocationId = "12345678";
		auto filterAsdf = parseJson(toJsonString(filter));
		auto sortAsdf = parseJson(toJsonString(sort));
		auto invocation = Invocation.queryChanges(type,accountId,invocationId,filterAsdf,sortAsdf,sinceQueryState,maxChanges,upToId,calculateTotal);
		auto request = JmapRequest(listCapabilities(),[invocation],null);
		return post(request);
	}

	Variable queryChanges(string type, string accountId, Variable filter, Variable sort, string sinceQueryState,Nullable!uint maxChanges = (Nullable!uint).init, Nullable!string upToId = (Nullable!string).init, bool calculateTotal = false)
	{
		return queryChangesRaw(type, accountId, filter, sort, sinceQueryState,maxChanges,upToId,calculateTotal).toVariable;
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


	static Invocation get(string type, string accountId, string invocationId = null, string[] ids = null, Asdf properties = Asdf.init)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["ids"] = AsdfNode(ids.serializeToAsdf);
		arguments["properties"] = AsdfNode(properties);

		Invocation ret = {
			name: type ~ "/get",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}

	static Invocation changes(string type, string accountId, string invocationId, string sinceState, Nullable!uint maxChanges)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["sinceState"] = AsdfNode(sinceState.serializeToAsdf);
		arguments["maxChanges"] = AsdfNode(maxChanges.serializeToAsdf);
		Invocation ret = {
			name: type ~ "/changes",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}


	static Invocation set(string type, string accountId, string invocationId = null, string ifInState = null, Asdf create = Asdf.init, Asdf update = Asdf.init, string[] destroy_ = null)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["ifInState"] = AsdfNode(ifInState.serializeToAsdf);
		arguments["create"] = AsdfNode(create);
		arguments["update"] = AsdfNode(update);
		arguments["destroy"] = AsdfNode(destroy_.serializeToAsdf);
		Invocation ret = {
			name: type ~ "/set",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}

	static Invocation copy(string type, string fromAccountId, string invocationId = null, string ifFromInState = null, string accountId = null, string ifInState = null, Asdf create = Asdf.init, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null)
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

		Invocation ret = {
			name: type ~ "/copy",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}

	static Invocation query(string type, string accountId, string invocationId, Asdf filter, Asdf sort, int position, string anchor=null, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false)
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

		Invocation ret = {
			name: type ~ "/query",
			arguments: cast(Asdf) arguments,
			id: invocationId,
		};
		return ret;
	}

	static Invocation queryChanges(string type, string accountId, string invocationId, Asdf filter, Asdf sort, string sinceQueryState, Nullable!uint maxChanges = (Nullable!uint).init, Nullable!string upToId = (Nullable!string).init, bool calculateTotal = false)
	{
		auto arguments = AsdfNode("{}".parseJson);
		arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
		arguments["filter"] = AsdfNode(filter);
		arguments["sort"] = AsdfNode(sort);
		arguments["sinceQueryState"] = AsdfNode(sinceQueryState.serializeToAsdf);
		arguments["maxChanges"] = AsdfNode(maxChanges.serializeToAsdf);
		arguments["upToId"] = AsdfNode(upToId.serializeToAsdf);
		arguments["calculateTotal"] = AsdfNode(calculateTotal.serializeToAsdf);

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


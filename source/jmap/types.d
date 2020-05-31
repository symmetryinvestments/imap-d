module jmap.types;
import std.datetime : SysTime;
import std.typecons : Nullable;
import kaleidic.sil.lang.types : Variable,Function,SILdoc;
import asdf;

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

struct Mailbox
{
	string id;
	string name;
	string parentId;
	string role;
	int sortOrder;
	bool mayReadItems;
	bool mayAddItems;
	bool mayRemoveItems;
	bool mayCreateChild;
	bool mayRename;
	bool mayDelete;
	int totalEmails;
	int unreadEmails;
	int totalThreads;
	int unreadThreads;

	ModSeq createdModSeq;
	ModSeq updatedModSeq;
	ModSeq updatedNotCountsModSeq;
	Nullable!SysTime deleted;
	int highestUID;
	int emailHighestModSeq;
	int emailListLowModSeq;
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

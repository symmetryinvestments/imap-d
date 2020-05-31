import std.datetime : SysTime;
import std.typecons : Nullable;

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
	uint maxConcurrentRequest;
	uint maxCallsInRequest;
	uint maxObjectsInGet;
	uint maxObjectsInSet;
	string[] collationAlgorithms;
}

struct Account
{
	string name;
	bool isPersonal;
	bool isReadOnly;
	Variable[string] accountCapabilities;
	string[string] primaryAccounts;
}

struct Session
{
	SessionCoreCapabilities capabilities;
	Account[string] accounts;
	string[string] primaryAccounts;
	string username;
	string apiUrl;
	string downloadUrl;
	string uploadUrl;
	string eventSourceUrl;
	string state;
	Variable[string] otherProperties;
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


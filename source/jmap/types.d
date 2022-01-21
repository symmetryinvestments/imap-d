module jmap.types;

import core.time : seconds;
import imap.sil : SILdoc;
import mir.algebraic : Nullable, visit;
import mir.algebraic_alias.json;
import mir.array.allocation : array;
import mir.ion.conv : serde;
import mir.ion.deser.json : deserializeJson;
import mir.ion.ser.json : serializeJson, serializeJsonPretty;
import mir.ndslice.topology : as, member, map;
import mir.serde;
import mir.exception : MirException, enforce;
import mir.format : text;
import std.datetime.date : DateTime;
import std.datetime.systime : SysTime;

struct Credentials {
    string user;
    string pass;
}

alias Url = string;
alias Emailer = string;
alias Attachment = ubyte[];
alias ModSeq = ulong;

alias Set = string[bool];

@("urn:ietf:params:jmap:core")
struct SessionCoreCapabilities {
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
enum EmailQuerySortOption {
    receivedAt,
    from,
    to,
    subject,
    size,

    @serdeKeys("header.x-spam-score")
    headerXSpamScore,
}

struct AccountParams {
    // EmailQuerySortOption[] emailQuerySortOptions;
    string[] emailQuerySortOptions;
    Nullable!int maxMailboxDepth;
    Nullable!int maxMailboxesPerEmail;
    Nullable!int maxSizeAttachmentsPerEmail;
    Nullable!int maxSizeMailboxName;
    bool mayCreateTopLevelMailbox;
}

struct SubmissionParams {
    int maxDelayedSend;
    string[] submissionExtensions;
}

struct AccountCapabilities {
    @serdeKeys("urn:ietf:params:jmap:mail")
    AccountParams accountParams;

    @serdeOptional
    @serdeKeys("urn:ietf:params:jmap:submission")
    SubmissionParams submissionParams;

    // @serdeIgnsoreIn JsonAlgebraic vacationResponseParams;

    @serdeIgnoreDefault @serdeIgnoreIn
    StringMap!JsonAlgebraic allAccountCapabilities;
}

struct Account {
    string name;
    bool isPersonal;
    bool isReadOnly;

    bool isArchiveUser = false;
    AccountCapabilities accountCapabilities;
    
    @serdeOptional
    StringMap!string primaryAccounts;
}

struct Session {
    @serdeOptional
    SessionCoreCapabilities coreCapabilities;

    StringMap!Account accounts;
    StringMap!string primaryAccounts;
    string username;
    Url apiUrl;
    Url downloadUrl;
    Url uploadUrl;
    Url eventSourceUrl;
    string state;
    @serdeIgnoreIn StringMap!JsonAlgebraic capabilities;
    package Credentials credentials;
    private string activeAccountId_;
    private bool debugMode = false;

    void setDebug(bool debugMode = true) {
        this.debugMode = debugMode;
    }

    private string activeAccountId() {
        import std.algorithm : canFind;

        if (activeAccountId_.length == 0) {
            if (accounts.keys.length != 1)
                throw new MirException("multiple accounts - ", accounts.keys, " - and you must call setActiveAccount to pick one");
            this.activeAccountId_ = accounts.keys[0];
        }
        else if (!accounts.keys.canFind(activeAccountId_))
            throw new MirException("active account ID is set to ", activeAccountId_, " but it is not found amongst account IDs: ", activeAccountId_);
        return activeAccountId_;
    }

    const(string)[] listCapabilities() const {
        return capabilities.keys;
    }

    string[] listAccounts() const {
        return accounts.values.member!"name".as!string.array;
    }

    Account getActiveAccountInfo() {
        return *enforce!"no currently active account"(activeAccountId() in accounts);
    }

    @SILdoc("set active account - name is the account name, not the id")
    Session setActiveAccount(string name) {

        foreach (i, ref value; accounts.values) {
            if (value.name == name) {
                this.activeAccountId_ = accounts.keys[i];
                return this;
            }
        }
        throw new MirException("account ", name, " not found");
    }

    void serdeFinalize() {
        this.coreCapabilities = capabilities["urn:ietf:params:jmap:core"].serde!SessionCoreCapabilities;
    }

    private JsonAlgebraic post(JmapRequest request) {
        import requests : Request, BasicAuthentication;
        import std.string : strip;
        import std.stdio : writefln, stderr;
        auto json = request.serializeJsonPretty; 
        if (debugMode)
            stderr.writefln("post request to apiUrl (%s) with data: %s", apiUrl, json);
        auto req = Request();
        req.timeout = 3 * 60.seconds;
        req.authenticator = new BasicAuthentication(credentials.user, credentials.pass);
        auto result = req.post(apiUrl, json, "application/json").responseBody.data!string.strip;
        if (debugMode)
            stderr.writefln("response: %s", result);
        return result.length == 0 ? JsonAlgebraic(null) : result.deserializeJson!JsonAlgebraic;
    }

    JsonAlgebraic uploadBinary(string data, string type = "application/binary") {
        import std.string : replace;
        import requests : Request, BasicAuthentication;
        auto uri = this.uploadUrl.replace("{accountId}", this.activeAccountId());
        auto req = Request();
        req.authenticator = new BasicAuthentication(credentials.user, credentials.pass);
        return req.post(uploadUrl, data, type).responseBody.data!string.deserializeJson!JsonAlgebraic;
    }

    string downloadBinary(string blobId, string type = "application/binary", string name = "default.bin", string downloadUrl = null) {
        import std.string : replace;
        import requests : Request, BasicAuthentication;
        import std.algorithm : canFind;

        downloadUrl = (downloadUrl.length == 0) ? this.downloadUrl : downloadUrl;
        downloadUrl = downloadUrl
            .replace("{accountId}", this.activeAccountId().uriEncode)
            .replace("{blobId}", blobId.uriEncode)
            .replace("{type}", type.uriEncode)
            .replace("{name}", name.uriEncode);

        downloadUrl = downloadUrl ~  "&accept=" ~ type.uriEncode;
        auto req = Request();
        req.authenticator = new BasicAuthentication(credentials.user, credentials.pass);
        return req.get(downloadUrl).responseBody.data!string;
    }

    JsonAlgebraic get(string type, string[] ids, string[] properties = null, StringMap!JsonAlgebraic additionalArguments = null) {
        import std.stdio : stderr, writefln;
        auto invocationId = "12345678";
        if (debugMode)
            stderr.writefln("props: %s", serializeJson(properties));
        auto invocation = Invocation.get(type, activeAccountId(), invocationId, ids, properties, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation]);
        return post(request);
    }

    Mailbox[] getMailboxes() {
        import std.range : front, dropOne;
        return get("Mailbox", null)
            .get!(StringMap!JsonAlgebraic)["methodResponses"]
            .get!(JsonAlgebraic[]).front
            .get!(JsonAlgebraic[]).dropOne.front
            .get!(StringMap!JsonAlgebraic)["list"]
            .serde!(typeof(return));
    }

    JsonAlgebraic getContact(string[] ids, string[] properties = null, StringMap!JsonAlgebraic additionalArguments = null) {
        import std.range : front, dropOne;
        return this.get("Contact", ids, properties, additionalArguments)
            .get!(StringMap!JsonAlgebraic)["methodResponses"]
            .get!(JsonAlgebraic[]).front
            .get!(JsonAlgebraic[]).front
            .get!(JsonAlgebraic[]).dropOne.front;
    }

    JsonAlgebraic getEmails(string[] ids, string[] properties = [ "id", "blobId", "threadId", "mailboxIds", "keywords", "size", "receivedAt", "messageId", "inReplyTo", "references", "sender", "from", "to", "cc", "bcc", "replyTo", "subject", "sentAt", "hasAttachment", "preview", "bodyValues", "textBody", "htmlBody", "attachments", ], string[] bodyProperties = ["all"],
            bool fetchTextBodyValues = true, bool fetchHTMLBodyValues = true, bool fetchAllBodyValues = true) {
        import std.range : front, dropOne;
        return this.get(
                "Email", ids, properties, [
                    "bodyProperties" : bodyProperties.map!JsonAlgebraic.array.JsonAlgebraic,
                    "fetchTextBodyValues" : fetchTextBodyValues.JsonAlgebraic,
                    "fetchAllBodyValues" : fetchAllBodyValues.JsonAlgebraic,
                    "fetchHTMLBodyValues" : fetchHTMLBodyValues.JsonAlgebraic,
                ].StringMap!JsonAlgebraic)
            .get!(StringMap!JsonAlgebraic)["methodResponses"]
            .get!(JsonAlgebraic[]).front
            .get!(JsonAlgebraic[]).dropOne.front
            .get!(StringMap!JsonAlgebraic)["list"];
    }

    JsonAlgebraic changes(string type, string sinceState, Nullable!uint maxChanges = null, StringMap!JsonAlgebraic additionalArguments = null) {
        auto invocationId = "12345678";
        auto invocation = Invocation.changes(type, activeAccountId(), invocationId, sinceState, maxChanges, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation]);
        return post(request);
    }

    JsonAlgebraic set(string type, string ifInState = null, StringMap!JsonAlgebraic create = null, StringMap!JsonAlgebraic update = null, string[] destroy_ = null, StringMap!JsonAlgebraic additionalArguments = null) {
        auto invocationId = "12345678";
        auto invocation = Invocation.set(type, activeAccountId(), invocationId, ifInState, create, update, destroy_, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation]);
        return post(request);
    }

    JsonAlgebraic setEmail(string ifInState = null, StringMap!JsonAlgebraic create = null, StringMap!JsonAlgebraic update = null, string[] destroy_ = null, StringMap!JsonAlgebraic additionalArguments = null) {
        return set("Email", ifInState, create, update, destroy_, additionalArguments);
    }

    JsonAlgebraic copy(string type, string fromAccountId, string ifFromInState = null, string ifInState = null, StringMap!JsonAlgebraic create = null, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null, StringMap!JsonAlgebraic additionalArguments = null) {
        auto invocationId = "12345678";
        auto invocation = Invocation.copy(type, fromAccountId, invocationId, ifFromInState, activeAccountId, ifInState, create, onSuccessDestroyOriginal, destroyFromIfInState);
        auto request = JmapRequest(listCapabilities(), [invocation]);
        return post(request);
    }

    JsonAlgebraic query(string type, JsonAlgebraic filter, StringMap!JsonAlgebraic sort, int position, string anchor = null, int anchorOffset = 0, Nullable!uint limit = null, bool calculateTotal = false, StringMap!JsonAlgebraic additionalArguments = null) {
        auto invocationId = "12345678";
        auto invocation = Invocation.query(type, activeAccountId, invocationId, filter, sort, position, anchor, anchorOffset, limit, calculateTotal, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation]);
        return post(request);
    }

    JsonAlgebraic queryEmails(Filter filter, StringMap!JsonAlgebraic sort, int position = 0, string anchor = "", int anchorOffset = 0, Nullable!uint limit = null, bool calculateTotal = false, bool collapseThreads = false, StringMap!JsonAlgebraic additionalArguments = null) {
        import std.stdio : stderr, writeln;
        if (collapseThreads)
            additionalArguments["collapseThreads"] = true;
        if (debugMode)
            stderr.writeln(filter.serializeJsonPretty);
        auto filterJson = filter.serde!JsonAlgebraic;
        return query("Email", filterJson, sort, position, anchor, anchorOffset, limit, calculateTotal, additionalArguments);
    }

    JsonAlgebraic queryChanges(string type, JsonAlgebraic filter, StringMap!JsonAlgebraic sort, string sinceQueryState, Nullable!uint maxChanges = null, string upToId = null, bool calculateTotal = false, StringMap!JsonAlgebraic additionalArguments = null) {
        auto invocationId = "12345678";
        auto invocation = Invocation.queryChanges(type, activeAccountId, invocationId, filter, sort, sinceQueryState, maxChanges, upToId, calculateTotal, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation]);
        return post(request);
    }
}

struct Email {
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

enum EmailProperty {
    id,
    blobId,
    threadId,
    mailboxIds,
    keywords,
    size,
    receivedAt,
    messageId,
    headers,
    inReplyTo,
    references,
    sender,
    from,
    to,
    cc,
    bcc,
    replyTo,
    subject,
    sentAt,
    hasAttachment,
    preview,
    bodyValues,
    textBody,
    htmlBody,
    attachments,
    // Raw,
    // Text,
    // Addresses,
    // GroupedAddresses,
    // URLs,
}

enum EmailBodyProperty {
    partId,
    blobId,
    size,
    name,
    type,
    charset,
    disposition,
    cid,
    language,
    location,
    subParts,
    bodyStructure,
    bodyValues,
    textBody,
    htmlBody,
    attachments,
    hasAttachment,
    preview,
}

struct EmailSubmission {
    string id;
    string identityId;
    string emailId;
    string threadId;
    Nullable!Envelope envelope;
    DateTime sendAt;
    string undoStatus;
    string deliveryStatus;
    string[] dsnBlobIds;
    string[] mdnBlobIds;
}

struct Envelope {
    EmailAddress mailFrom;

    EmailAddress rcptTo;
}

struct EmailAddress {
    string email;
    Nullable!(StringMap!JsonAlgebraic) parameters;
}

struct ThreadEmail {
    string id;
    string[] mailboxIds;
    bool isUnread;
    bool isFlagged;
}

struct Thread {
    string id;
    ThreadEmail[] emails;
    ModSeq createdModSeq;
    ModSeq updatedModSeq;
    Nullable!SysTime deleted;
}

struct MailboxRights {
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

struct IdentityRef
{
    string accountId;
    string identityId;
}

struct Mailbox {
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
    
    @serdeOptional
    IdentityRef identityRef;
    
    bool learnAsSpam;
    int purgeOlderThanDays;
    bool isCollapsed;
    bool isSubscribed;
    bool suppressDuplicates;
    bool autoLearn;
    MailboxSortProperty[] sort;
}

string[] allMailboxPaths(Mailbox[] mailboxes) {
    return mailboxes.map!(mb => mailboxPath(mailboxes, mb.id)).array;
}

string mailboxPath(Mailbox[] mailboxes, string id, string path = null) {
    import std.algorithm : countUntil;
    import std.string : endsWith;
    if (path.endsWith("/"))
        path = path[0 .. $ - 1];
    auto i = mailboxes.countUntil!(mailbox => mailbox.id == id);
    if (i == -1)
        return path;
    path = path == null ? mailboxes[i].name : text!"/"(mailboxes[i].name, path);
    return mailboxPath(mailboxes, mailboxes[i].parentId, path);
}

Nullable!Mailbox findMailboxPath(Mailbox[] mailboxes, string path) {
    import std.algorithm : filter;
    import std.string : split, join, endsWith;

    Nullable!Mailbox ret;
    if (path.endsWith("/"))
        path = path[0 .. $ - 1];
    auto cols = path.split("/");
    if (cols.length == 0)
        return ret;

    foreach (item; mailboxes.filter!(mailbox => mailbox.name == cols[$ - 1])) {
        if (item.parentId.length == 0) {
            if (cols.length <= 1) {
                ret = item;
                break;
            } else { continue; }
        }
        auto parent = findMailboxPath(mailboxes, cols[0 .. $ - 1].join("/"));
        if (parent.isNull) {
            continue;
        } else {
            ret = item;
            break;
        }
    }
    return ret;
}

struct MailboxSortProperty {
    string property;
    bool isAscending;
}

struct MailboxEmailList {
    string id;
    string messageId;
    string threadId;
    ModSeq updatedModSeq;
    SysTime created;
    Nullable!SysTime deleted;
}

struct EmailChangeLogEntry {
    string id;
    string[] created;
    string[] updated;
    string[] destroyed;
}

struct ThreadChangeLogEntry {
    string id;
    string[] created;
    string[] updated;
    string[] destroyed;
}

struct ThreadRef {
    string id;
    string threadId;
    SysTime lastSeen;
}

struct HighLowModSeqCache {
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

@serdeProxy!(const(JsonAlgebraic)[])
struct Invocation {
    string name;
    JsonAlgebraic arguments;
    string id;

    const(JsonAlgebraic)[] toArray() const pure nothrow {
        return [name.JsonAlgebraic, arguments.JsonAlgebraic, id.JsonAlgebraic];
    }

    alias opCast(T : const(JsonAlgebraic)[]) = toArray;

    static Invocation get(string type, string accountId, string invocationId = null, string[] ids = null, string[] properties = null, StringMap!JsonAlgebraic additionalArguments = null) {
        auto arguments = StringMap!JsonAlgebraic(additionalArguments.keys.dup.assumeSafeAppend, additionalArguments.values);
        arguments["accountId"] = accountId;
        arguments["ids"] = ids.map!JsonAlgebraic.array;
        arguments["properties"] = properties.map!JsonAlgebraic.array;
        return Invocation(type ~ "/get", arguments.JsonAlgebraic, invocationId);
    }

    static Invocation changes(string type, string accountId, string invocationId, string sinceState, Nullable!uint maxChanges, StringMap!JsonAlgebraic additionalArguments = null) {
        auto arguments = StringMap!JsonAlgebraic(additionalArguments.keys.dup.assumeSafeAppend, additionalArguments.values);
        arguments["accountId"] = accountId;
        arguments["sinceState"] = sinceState;
        arguments["maxChanges"] = maxChanges.visit!JsonAlgebraic;
        return Invocation(type ~ "/changes", arguments.JsonAlgebraic, invocationId);
    }

    static Invocation set(string type, string accountId, string invocationId = null, string ifInState = null, StringMap!JsonAlgebraic create = null, StringMap!JsonAlgebraic update = null, string[] destroy_ = null, StringMap!JsonAlgebraic additionalArguments = null) {
        auto arguments = StringMap!JsonAlgebraic(additionalArguments.keys.dup.assumeSafeAppend, additionalArguments.values);
        arguments["accountId"] = accountId;
        arguments["ifInState"] = ifInState;
        arguments["create"] = create;
        arguments["update"] = update;
        arguments["destroy"] = destroy_.map!JsonAlgebraic.array;
        return Invocation(type ~ "/set", arguments.JsonAlgebraic, invocationId);
    }

    static Invocation copy(string type, string fromAccountId, string invocationId = null, string ifFromInState = null, string accountId = null, string ifInState = null, StringMap!JsonAlgebraic create = null, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null, StringMap!JsonAlgebraic additionalArguments = null) {
        auto arguments = StringMap!JsonAlgebraic(additionalArguments.keys.dup.assumeSafeAppend, additionalArguments.values);
        arguments["accountId"] = accountId;
        arguments["fromAccountId"] = fromAccountId;
        arguments["ifFromInState"] = ifFromInState;
        arguments["accountId"] = accountId;
        arguments["ifInState"] = ifInState;
        arguments["create"] = create;
        arguments["onSuccessDestroyOriginal"] = onSuccessDestroyOriginal;
        arguments["destroyFromIfInState"] = destroyFromIfInState;
        return Invocation(type ~ "/copy", arguments.JsonAlgebraic, invocationId);
    }

    static Invocation query(string type, string accountId, string invocationId, JsonAlgebraic filter, StringMap!JsonAlgebraic sort, int position, string anchor = null, int anchorOffset = 0, Nullable!uint limit = null, bool calculateTotal = false, StringMap!JsonAlgebraic additionalArguments = null) {
        auto arguments = StringMap!JsonAlgebraic(additionalArguments.keys.dup.assumeSafeAppend, additionalArguments.values);
        arguments["accountId"] = accountId;
        arguments["filter"] = filter;
        arguments["sort"] = sort;
        arguments["position"] = position;
        arguments["anchor"] = anchor;
        arguments["anchorOffset"] = anchorOffset;
        arguments["limit"] = limit.visit!JsonAlgebraic;
        arguments["calculateTotal"] = calculateTotal;
        return Invocation(type ~ "/query", arguments.JsonAlgebraic, invocationId);
    }

    static Invocation queryChanges(string type, string accountId, string invocationId, JsonAlgebraic filter, StringMap!JsonAlgebraic sort, string sinceQueryState, Nullable!uint maxChanges = null, string upToId = null, bool calculateTotal = false, StringMap!JsonAlgebraic additionalArguments = null) {
        auto arguments = StringMap!JsonAlgebraic(additionalArguments.keys.dup.assumeSafeAppend, additionalArguments.values);
        arguments["accountId"] = accountId;
        arguments["filter"] = filter;
        arguments["sort"] = sort;
        arguments["sinceQueryState"] = sinceQueryState;
        arguments["maxChanges"] = maxChanges.visit!JsonAlgebraic;
        arguments["upToId"] = upToId;
        arguments["calculateTotal"] = calculateTotal;
        return Invocation(type ~ "/queryChanges", arguments.JsonAlgebraic, invocationId);
    }
}

enum FilterOperatorKind {
    @serdeKeys("AND") and,
    @serdeKeys("OR") or,
    @serdeKeys("NOT") not,
}

alias Filter = Nullable!(FilterOperators, FilterCondition);

// Holder is required to workaround compliler circular bug
@serdeProxy!Filter 
struct FilterHolder {
    Filter filter;
    alias filter this;
}

struct FilterOperators {
    FilterOperatorKind operator;
    FilterHolder[] conditions;
}

struct FilterCondition {
@serdeIgnoreDefault:
    string inMailbox;
    Nullable!(string[])inMailboxOtherThan;
    Nullable!DateTime before;
    Nullable!DateTime after;
    Nullable!uint minSize;
    Nullable!uint maxSize;
    string allInThreadHaveKeyword;
    string someInThreadHaveKeyword;
    string noneInThreadHaveKeyword;
    string hasKeyword;
    string notKeyword;
    string text;
    string from;
    string to;
    string cc;
    string bcc;
    string subject;
    @serdeKeys("body")
    string body_;
    Nullable!(string[])header;

    this(string inMailbox,
            Nullable!(string[])inMailboxOtherThan = null,
            string before = null,
            string after = null,
            Nullable!uint minSize = null,
            Nullable!uint maxSize = null,
            string allInThreadHaveKeyword = null,
            string someInThreadHaveKeyword = null,
            string noneInThreadHaveKeyword = null,
            string hasKeyword = null,
            string notKeyword = null,
            string text = null,
            string from = null,
            string to = null,
            string cc = null,
            string bcc = null,
            string subject = null,
            string body_ = null,
            Nullable!(string[])header = null, ) {
        this.inMailbox = inMailbox;
        this.inMailboxOtherThan = inMailboxOtherThan;
        if (before.length > 0)
            this.before = DateTime.fromISOExtString(before);
        if (after.length > 0)
            this.after = DateTime.fromISOExtString(after);
        this.minSize = minSize;
        this.maxSize = maxSize;
        this.allInThreadHaveKeyword = allInThreadHaveKeyword;
        this.someInThreadHaveKeyword = someInThreadHaveKeyword;
        this.hasKeyword = hasKeyword;
        this.notKeyword = notKeyword;
        this.text = text;
        this.from = from;
        this.to = to;
        this.cc = cc;
        this.bcc = bcc;
        this.subject = subject;
        this.body_ = body_;
        this.header = header;
    }
}

struct Comparator {
    string property;
    bool isAscending = true;
    string collation = null;
}

struct JmapRequest {
    const(string)[] using;
    Invocation[] methodCalls;
    StringMap!string createdIds;
}

struct JmapResponse {
    Invocation[] methodResponses;
    StringMap!string createdIds;
    string sessionState;
}

struct JmapResponseError {
    string type;
    int status;
    string detail;
}

struct ResultReference {
    string resultOf;
    string name;
    string path;
}

struct ContactAddress {
    string type;
    string label; //  label;
    string street;
    string locality;
    string region;
    string postcode;
    string country;
    bool isDefault;
}

struct JmapFile {
    string blobId;
    string type;
    string name;
    Nullable!uint size;
}

struct ContactInformation {
    string type;
    string label;
    string value;
    bool isDefault;
}

struct Contact {
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
    ContactAddress[] addresses;
    string notes;
}

struct ContactGroup {
    string id;
    string name;
    string[] ids;
}

string uriEncode(const(char)[] s) {
    import std.string : replace;

    return s.replace("!", "%21").replace("#", "%23").replace("$", "%24").replace("&", "%26").replace("'", "%27")
           .replace("(", "%28").replace(")", "%29").replace("*", "%2A").replace("+", "%2B").replace(",", "%2C")
           .replace("-", "%2D").replace(".", "%2E").replace("/", "%2F").replace(":", "%3A").replace(";", "%3B")
           .replace("=", "%3D").replace("?", "%3F").replace("@", "%40").replace("[", "%5B").replace("]", "%5D")
           .idup;
}

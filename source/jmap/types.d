module jmap.types;
import std.datetime : SysTime;
import core.time : seconds;
import std.typecons : Nullable;

version (SIL) :

import kaleidic.sil.lang.typing.types : Variable, SilStruct, SILdoc;
import mir.ion.ser.json : serializeJson;
import mir.ion.deser.json : deserializeJson;
import std.datetime : DateTime;
import asdf;

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

    // @serdeIgnoreIn Asdf vacationResponseParams;

    version (SIL) {
        @serdeIgnoreIn SilStruct allAccountCapabilities;

        void finalizeDeserialization(Asdf data) {
            import asdf : deserialize, Asdf;

            foreach (el; data.byKeyValue)
                allAccountCapabilities[el.key.idup] = el.value.get!Asdf(Asdf.init).deserialize!Variable;
        }
    }
}

struct Account {
    string name;
    bool isPersonal;
    bool isReadOnly;

    bool isArchiveUser = false;
    AccountCapabilities accountCapabilities;
    
    @serdeOptional
    string[string] primaryAccounts;
}

struct Session {
    @serdeOptional
    SessionCoreCapabilities coreCapabilities;

    Account[string] accounts;
    string[string] primaryAccounts;
    string username;
    Url apiUrl;
    Url downloadUrl;
    Url uploadUrl;
    Url eventSourceUrl;
    string state;
    @serdeIgnoreIn Asdf[string] capabilities;
    package Credentials credentials;
    private string activeAccountId_;
    private bool debugMode = false;

    void setDebug(bool debugMode = true) {
        this.debugMode = debugMode;
    }

    private string activeAccountId() {
        import std.format : format;
        import std.exception : enforce;
        import std.string : join;
        import std.range : front;
        import std.algorithm : canFind;

        if (activeAccountId_.length == 0) {
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

    string[] listCapabilities() {
        return capabilities.keys;
    }

    string[] listAccounts() {
        import std.algorithm : map;
        import std.array : array;
        return accounts.keys.map!(key => accounts[key].name).array;
    }

    Account getActiveAccountInfo() {
        import std.exception : enforce;
        auto p = activeAccountId() in accounts;
        enforce(p !is null, "no currently active account");
        return *p;
    }

    @SILdoc("set active account - name is the account name, not the id")
    Session setActiveAccount(string name) {
        import std.format : format;
        import std.exception : enforce;
        import std.format : format;

        foreach (kv; accounts.byKeyValue) {
            if (kv.value.name == name) {
                this.activeAccountId_ = kv.key;
                return this;
            }
        }
        throw new Exception(format!"account %s not found"(name));
    }


    void finalizeDeserialization(Asdf data) {
        import asdf : deserialize, Asdf;

        foreach (el; data["capabilities"].byKeyValue)
            capabilities[el.key] = el.value.get!Asdf(Asdf.init);
        this.coreCapabilities = deserialize!SessionCoreCapabilities(capabilities["urn:ietf:params:jmap:core"]);
    }

    private Asdf post(JmapRequest request) {
        import asdf;
        import requests : Request, BasicAuthentication;
        import std.string : strip;
        import std.stdio : writefln, stderr;
        auto json = serializeToJsonPretty(request); // serializeToJsonPretty
        if (debugMode)
            stderr.writefln("post request to apiUrl (%s) with data: %s", apiUrl, json);
        auto req = Request();
        req.timeout = 3 * 60.seconds;
        req.authenticator = new BasicAuthentication(credentials.user, credentials.pass);
        auto result = (cast(string) req.post(apiUrl, json, "application/json").responseBody.data.idup).strip;
        if (debugMode)
            stderr.writefln("response: %s", result);
        return (result.length == 0) ? Asdf.init : parseJson(result);
    }

    version (SIL) {
        Variable uploadBinary(string data, string type = "application/binary") {
            import std.string : replace;
            import asdf;
            import requests : Request, BasicAuthentication;
            auto uri = this.uploadUrl.replace("{accountId}", this.activeAccountId());
            auto req = Request();
            req.authenticator = new BasicAuthentication(credentials.user, credentials.pass);
            auto result = cast(string) req.post(uploadUrl, data, type).responseBody.data.idup;
            return result.deserializeJson!Variable;
        }
    } else {
        Asdf uploadBinary(string data, string type = "application/binary") {
            import std.string : replace;
            import asdf;
            import requests : Request, BasicAuthentication;
            auto uri = this.uploadUrl.replace("{accountId}", this.activeAccountId());
            auto req = Request();
            req.authenticator = new BasicAuthentication(credentials.user, credentials.pass);
            auto result = cast(string) req.post(uploadUrl, data, type).responseBody.data.idup;
            return parseJson(result);
        }
    }


    string downloadBinary(string blobId, string type = "application/binary", string name = "default.bin", string downloadUrl = null) {
        import std.string : replace;
        import asdf;
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
        auto result = cast(string) req.get(downloadUrl).responseBody.data.idup;
        return result;
    }


    version (SIL) {
        Variable get(string type, string[] ids, Variable properties = Variable.init, SilStruct additionalArguments = null) {
            return getRaw(type, ids, properties, additionalArguments).deserialize!Variable;
        }

        Asdf getRaw(string type, string[] ids, Variable properties = Variable.init, SilStruct additionalArguments = null) {
            import std.algorithm : map;
            import std.array : array;
            import std.stdio : stderr, writefln;
            auto invocationId = "12345678";
            if (debugMode)
                stderr.writefln("props: %s", serializeJson(properties));
            auto props =  parseJson(serializeJson(properties));
            auto invocation = Invocation.get(type, activeAccountId(), invocationId, ids, props, additionalArguments);
            auto request = JmapRequest(listCapabilities(), [invocation], null);
            return post(request);
        }
    }


    Mailbox[] getMailboxes() {
        import std.range : front, dropOne;
        auto asdf = getRaw("Mailbox", null);
        return deserialize!(Mailbox[])(asdf["methodResponses"].byElement.front.byElement.dropOne.front["list"]);
    }

    Variable getContact(string[] ids, Variable properties = Variable([]), SilStruct additionalArguments = null) {
        import std.range : front, dropOne;
        return Variable(
                this.get("Contact", ids, properties, additionalArguments)
                .get!SilStruct
                ["methodResponses"]
                .get!(Variable[])
                .front
                .get!(Variable[])
                .front
                .get!(Variable[])
                .dropOne
                .front);
    }

    Variable getEmails(string[] ids, Variable properties = Variable(["id", "blobId", "threadId", "mailboxIds", "keywords", "size", "receivedAt", "messageId", "inReplyTo", "references", "sender", "from", "to", "cc", "bcc", "replyTo", "subject", "sentAt", "hasAttachment", "preview", "bodyValues", "textBody", "htmlBody", "attachments"]), Variable bodyProperties = Variable(["all"]),
            bool fetchTextBodyValues = true, bool fetchHTMLBodyValues = true, bool fetchAllBodyValues = true) {
        import std.range : front, dropOne;
        return Variable(
                this.get(
                        "Email", ids, properties, SilStruct([
                            "bodyProperties" : bodyProperties,
                            "fetchTextBodyValues" : fetchTextBodyValues.Variable,
                            "fetchAllBodyValues" : fetchAllBodyValues.Variable,
                            "fetchHTMLBodyValues" : fetchHTMLBodyValues.Variable,
                        ]))
                .get!SilStruct
                ["methodResponses"] // ,(Variable[]).init)
                .get!(Variable[])
                .front
                .get!(Variable[])
                .dropOne
                .front
                .get!SilStruct
                ["list"]);
    }


    Asdf changesRaw(string type, string sinceState, Nullable!uint maxChanges = (Nullable!uint).init, SilStruct additionalArguments = null) {
        import std.algorithm : map;
        import std.array : array;
        auto invocationId = "12345678";
        auto invocation = Invocation.changes(type, activeAccountId(), invocationId, sinceState, maxChanges, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation], null);
        return post(request);
    }

    Variable changes(string type, string sinceState, Nullable!uint maxChanges = (Nullable!uint).init, SilStruct additionalArguments = null) {
        return changesRaw(type, sinceState, maxChanges, additionalArguments).deserialize!Variable;
    }

    Asdf setRaw(string type, string ifInState = null, SilStruct create = null, SilStruct update = null, string[] destroy_ = null, SilStruct additionalArguments = null) {
        import std.algorithm : map;
        import std.array : array;
        auto invocationId = "12345678";
        auto createAsdf = parseJson(serializeJson(Variable(create)));
        auto updateAsdf = parseJson(serializeJson(Variable(update)));
        auto invocation = Invocation.set(type, activeAccountId(), invocationId, ifInState, createAsdf, updateAsdf, destroy_, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation], null);
        return post(request);
    }

    Variable set(string type, string ifInState = null, SilStruct create = null, SilStruct update = null, string[] destroy_ = null, SilStruct additionalArguments = null) {
        return setRaw(type, ifInState, create, update, destroy_, additionalArguments).deserialize!Variable;
    }

    Variable setEmail(string ifInState = null, SilStruct create = null, SilStruct update = null, string[] destroy_ = null, SilStruct additionalArguments = null) {
        return set("Email", ifInState, create, update, destroy_, additionalArguments);
    }


    Asdf copyRaw(string type, string fromAccountId, string ifFromInState = null, string ifInState = null, SilStruct create = null, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null, SilStruct additionalArguments = null) {
        import std.algorithm : map;
        import std.array : array;
        auto invocationId = "12345678";
        auto createAsdf = parseJson(serializeJson(Variable(create)));
        auto invocation = Invocation.copy(type, fromAccountId, invocationId, ifFromInState, activeAccountId, ifInState, createAsdf, onSuccessDestroyOriginal, destroyFromIfInState);
        auto request = JmapRequest(listCapabilities(), [invocation], null);
        return post(request);
    }

    Variable copy(string type, string fromAccountId, string ifFromInState = null, string ifInState = null, SilStruct create = null, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null, SilStruct additionalArguments = null) {
        return copyRaw(type, fromAccountId, ifFromInState, ifInState, create, onSuccessDestroyOriginal, destroyFromIfInState, additionalArguments).deserialize!Variable;
    }


    Asdf queryRaw(string type, Variable filter, Variable sort, int position, string anchor = null, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false, SilStruct additionalArguments = null) {
        import std.algorithm : map;
        import std.array : array;
        auto invocationId = "12345678";
        auto filterAsdf = parseJson(serializeJson(filter));
        auto sortAsdf = parseJson(serializeJson(sort));
        auto invocation = Invocation.query(type, activeAccountId, invocationId, filterAsdf, sortAsdf, position, anchor, anchorOffset, limit, calculateTotal, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation], null);
        return post(request);
    }

    Variable queryEmails(Filter filter, Variable sort, int position = 0, string anchor = "", int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false, bool collapseThreads = false, SilStruct additionalArguments = null) {
        import std.exception : enforce;
        import std.stdio : stderr, writeln;
        if (collapseThreads)
            additionalArguments["collapseThreads"] = Variable(true);
        auto o = cast(FilterOperator) filter;
        auto c = cast(FilterCondition) filter;
        enforce(o !is null || c !is null, "filter must be either an operator or a condition");
        if (debugMode)
            stderr.writeln((o !is null) ? serializeToJsonPretty(o) : serializeToJsonPretty(c));
        Variable filterVariable = (o !is null) ? parseJson(serializeToJson(o)).deserialize!Variable : parseJson(serializeToJson(c)).deserialize!Variable;
        return queryRaw("Email", filterVariable, sort, position, anchor, anchorOffset, limit, calculateTotal, additionalArguments).deserialize!Variable;
    }

    Variable query(string type, Variable filter, Variable sort, int position, string anchor, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false, SilStruct additionalArguments = null) {
        return queryRaw(type, filter, sort, position, anchor, anchorOffset, limit, calculateTotal, additionalArguments).deserialize!Variable;
    }

    Asdf queryChangesRaw(string type, Variable filter, Variable sort, string sinceQueryState, Nullable!uint maxChanges = (Nullable!uint).init, string upToId = null, bool calculateTotal = false, SilStruct additionalArguments = null) {
        import std.algorithm : map;
        import std.array : array;
        auto invocationId = "12345678";
        auto filterAsdf = parseJson(serializeJson(filter));
        auto sortAsdf = parseJson(serializeJson(sort));
        auto invocation = Invocation.queryChanges(type, activeAccountId, invocationId, filterAsdf, sortAsdf, sinceQueryState, maxChanges, upToId, calculateTotal, additionalArguments);
        auto request = JmapRequest(listCapabilities(), [invocation], null);
        return post(request);
    }

    Variable queryChanges(string type, Variable filter, Variable sort, string sinceQueryState, Nullable!uint maxChanges = (Nullable!uint).init, string upToId = null, bool calculateTotal = false, SilStruct additionalArguments = null) {
        return queryChangesRaw(type, filter, sort, sinceQueryState, maxChanges, upToId, calculateTotal, additionalArguments).deserialize!Variable;
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
    Nullable!SilStruct parameters;
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
    Nullable!IdentityRef identityRef;
    bool learnAsSpam;
    int purgeOlderThanDays;
    bool isCollapsed;
    bool isSubscribed;
    bool suppressDuplicates;
    bool autoLearn;
    MailboxSortProperty[] sort;
}

string[] allMailboxPaths(Mailbox[] mailboxes) {
    import std.algorithm : map;
    import std.array : array;
    return mailboxes.map!(mb => mailboxPath(mailboxes, mb.id)).array;
}

string mailboxPath(Mailbox[] mailboxes, string id, string path = null) {
    import std.algorithm : countUntil;
    import std.format : format;
    import std.exception : enforce;
    import std.string : endsWith;
    if (path.endsWith("/"))
        path = path[0 .. $ - 1];
    auto i = mailboxes.countUntil!(mailbox => mailbox.id == id);
    if (i == -1)
        return path;
    path = (path == null) ? mailboxes[i].name : format!"%s/%s"(mailboxes[i].name, path);
    return mailboxPath(mailboxes, mailboxes[i].parentId, path);
}

Nullable!Mailbox findMailboxPath(Mailbox[] mailboxes, string path) {
    import std.algorithm : filter;
    import std.string : split, join, endsWith;
    import std.range : back;
    import std.exception : enforce;

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

void serializeAsdf(S)(ref S ser, AsdfNode node) pure {
    if (node.isLeaf())
        serializeAsdf(ser, node.data);

    auto objState = ser.objectBegin();
    foreach (kv; node.children.byKeyValue) {
        ser.putKey(kv.key);
        serializeAsdf(ser, kv.value);
    }
    ser.objectEnd(objState);
}

void serializeAsdf(S)(ref S ser, Asdf el) pure {
    final switch (el.kind) {
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
            ser.putValue(el.get!double (double.nan));
            break;

        case Asdf.Kind.string:
            ser.putValue(el.get!string(null));
            break;

        case Asdf.Kind.array:
            auto arrayState = ser.arrayBegin();
            foreach (arrEl; el.byElement) {
                ser.elemBegin();
                serializeAsdf(ser, arrEl);
            }
            ser.arrayEnd(arrayState);
            break;

        case Asdf.Kind.object:
            auto objState = ser.objectBegin();
            foreach (kv; el.byKeyValue) {
                ser.putKey(kv.key);
                serializeAsdf(ser, kv.value);
            }
            ser.objectEnd(objState);
            break;
    }
}


struct Invocation {
    string name;
    Asdf arguments;
    string id;

    void serialize(S)(ref S ser) pure {
        auto outerState = ser.arrayBegin();
        ser.elemBegin();
        ser.putValue(name);
        ser.elemBegin();
        auto state = ser.objectBegin();
        foreach (el; arguments.byKeyValue) {
            ser.putKey(el.key);
            serializeAsdf(ser, el.value);
        }
        ser.objectEnd(state);
        ser.elemBegin();
        ser.putValue(id);
        ser.arrayEnd(outerState);
    }


    static Invocation get(string type, string accountId, string invocationId = null, string[] ids = null, Asdf properties = Asdf.init, SilStruct additionalArguments = null) {
        auto arguments = AsdfNode("{}".parseJson);
        arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
        arguments["ids"] = AsdfNode(ids.serializeToAsdf);
        arguments["properties"] = AsdfNode(properties);
        foreach (kv; additionalArguments.byKeyValue)
            arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

        Invocation ret = {
            name : type ~ "/get",
            arguments : cast(Asdf) arguments,
            id : invocationId,
        };
        return ret;
    }

    static Invocation changes(string type, string accountId, string invocationId, string sinceState, Nullable!uint maxChanges, SilStruct additionalArguments = null) {
        auto arguments = AsdfNode("{}".parseJson);
        arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
        arguments["sinceState"] = AsdfNode(sinceState.serializeToAsdf);
        arguments["maxChanges"] = AsdfNode(maxChanges.serializeToAsdf);
        foreach (kv; additionalArguments.byKeyValue)
            arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

        Invocation ret = {
            name : type ~ "/changes",
            arguments : cast(Asdf) arguments,
            id : invocationId,
        };
        return ret;
    }


    static Invocation set(string type, string accountId, string invocationId = null, string ifInState = null, Asdf create = Asdf.init, Asdf update = Asdf.init, string[] destroy_ = null, SilStruct additionalArguments = null) {
        auto arguments = AsdfNode("{}".parseJson);
        arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
        arguments["ifInState"] = AsdfNode(ifInState.serializeToAsdf);
        arguments["create"] = AsdfNode(create);
        arguments["update"] = AsdfNode(update);
        arguments["destroy"] = AsdfNode(destroy_.serializeToAsdf);
        foreach (kv; additionalArguments.byKeyValue)
            arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

        Invocation ret = {
            name : type ~ "/set",
            arguments : cast(Asdf) arguments,
            id : invocationId,
        };
        return ret;
    }

    static Invocation copy(string type, string fromAccountId, string invocationId = null, string ifFromInState = null, string accountId = null, string ifInState = null, Asdf create = Asdf.init, bool onSuccessDestroyOriginal = false, string destroyFromIfInState = null, SilStruct additionalArguments = null) {
        auto arguments = AsdfNode("{}".parseJson);
        arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
        arguments["fromAccountId"] = AsdfNode(fromAccountId.serializeToAsdf);
        arguments["ifFromInState"] = AsdfNode(ifFromInState.serializeToAsdf);
        arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
        arguments["ifInState"] = AsdfNode(ifInState.serializeToAsdf);
        arguments["create"] = AsdfNode(create);
        arguments["onSuccessDestroyOriginal"] = AsdfNode(onSuccessDestroyOriginal.serializeToAsdf);
        arguments["destroyFromIfInState"] = AsdfNode(destroyFromIfInState.serializeToAsdf);
        foreach (kv; additionalArguments.byKeyValue)
            arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

        Invocation ret = {
            name : type ~ "/copy",
            arguments : cast(Asdf) arguments,
            id : invocationId,
        };
        return ret;
    }

    static Invocation query(string type, string accountId, string invocationId, Asdf filter, Asdf sort, int position, string anchor = null, int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false, SilStruct additionalArguments = null) {
        auto arguments = AsdfNode("{}".parseJson);
        arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
        arguments["filter"] = AsdfNode(filter);
        arguments["sort"] = AsdfNode(sort);
        arguments["position"] = AsdfNode(position.serializeToAsdf);
        arguments["anchor"] = AsdfNode(anchor.serializeToAsdf);
        arguments["anchorOffset"] = AsdfNode(anchorOffset.serializeToAsdf);
        arguments["limit"] = AsdfNode(limit.serializeToAsdf);
        arguments["calculateTotal"] = AsdfNode(calculateTotal.serializeToAsdf);
        foreach (kv; additionalArguments.byKeyValue)
            arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

        Invocation ret = {
            name : type ~ "/query",
            arguments : cast(Asdf) arguments,
            id : invocationId,
        };
        return ret;
    }

    static Invocation queryChanges(string type, string accountId, string invocationId, Asdf filter, Asdf sort, string sinceQueryState, Nullable!uint maxChanges = (Nullable!uint).init, string upToId = null, bool calculateTotal = false, SilStruct additionalArguments = null) {
        auto arguments = AsdfNode("{}".parseJson);
        arguments["accountId"] = AsdfNode(accountId.serializeToAsdf);
        arguments["filter"] = AsdfNode(filter);
        arguments["sort"] = AsdfNode(sort);
        arguments["sinceQueryState"] = AsdfNode(sinceQueryState.serializeToAsdf);
        arguments["maxChanges"] = AsdfNode(maxChanges.serializeToAsdf);
        arguments["upToId"] = AsdfNode(upToId.serializeToAsdf);
        arguments["calculateTotal"] = AsdfNode(calculateTotal.serializeToAsdf);
        foreach (kv; additionalArguments.byKeyValue)
            arguments[kv.key] = AsdfNode(kv.value.serializeToAsdf);

        Invocation ret = {
            name : type ~ "/queryChanges",
            arguments : cast(Asdf) arguments,
            id : invocationId,
        };
        return ret;
    }
}

enum FilterOperatorKind {
    and,
    or,
    not,
}

interface Filter {
}

class FilterOperator : Filter {
    FilterOperatorKind operator;

    Filter[] conditions;

    this(FilterOperatorKind operator, Filter[] conditions) {
        this.operator = operator;
        this.conditions = conditions;
    }

    void serialize(S)(ref S serializer) {
        import std.exception : enforce;
        import std.format : format;
        import std.conv : to;
        import std.string : toUpper;

        auto o = serializer.objectBegin();
        serializer.putKey("operator");
        serializer.putValue(operator.to!string.toUpper());
        serializer.putKey("conditions");
        auto o2 = serializer.arrayBegin();
        foreach (i, condition; conditions) {
            serializer.elemBegin();
            auto f = cast(FilterOperator) condition;
            auto c = cast(FilterCondition) condition;
            enforce(f !is null || c !is null, format!"condition #%s must be FilterOperator or FilterCondition!"(i));
            if (f !is null) {
                serializer.serializeValue(f);
            } else if (c !is null) {
                serializer.serializeValue(c);
            }
        }
        serializer.arrayEnd(o2);
        serializer.objectEnd(o);
    }
}


package enum nullArray = (Nullable!(string[])).init;
package enum NullUint = (Nullable!uint).init;
package enum NullDateTime = (Nullable!DateTime).init;

FilterCondition filterCondition(string inMailbox = null,
        Nullable!(string[])inMailboxOtherThan = nullArray,
        string before = null,
        string after = null,
        Nullable!uint minSize = NullUint,
        Nullable!uint maxSize = NullUint,
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
        Nullable!(string[])header = nullArray, ) {
    return new FilterCondition(inMailbox, inMailboxOtherThan, before, after, minSize,
            maxSize, allInThreadHaveKeyword, someInThreadHaveKeyword, noneInThreadHaveKeyword,
            hasKeyword, notKeyword, text, from, to, cc, bcc, subject, body_, header);
}

private void doSerialize(S, T)(ref S serializer, T t) {
    import std.traits : hasUDA, getUDAs, isCallable, isInstanceOf;
    auto o = serializer.objectBegin;
    static foreach (i, M; T.tupleof) {
        {
            static if (!isCallable!M) {
                static if (hasUDA!(M, "serdeKeys")) {
                    enum name = getUDAs!(M, "serdeKeys")[0].value;
                } else {
                    enum name = __traits(identifier, M);
                }
                mixin("auto value = t." ~ __traits(identifier, M) ~ ";");
                static if (isInstanceOf!(Nullable, typeof(value))) {
                    if (!value.isNull) {
                        // static if (is(typeof(value.get.result) == typeof(Variable)))
                        //      serializeAsAsdf(value.get.result);
                        // else static if is(Unqual!
                        //      doSerialize(serializer,value.get.result);
                        serializer.serializeAsdf(serializeToAsdf(value.get));
                    } else {
                        serializer.putValue(null);
                    }
                } else {
                    serializer.serializeAsdf(serializeToAsdf(result));
                }
            }
        }
    }
}

string toUTCDate(Nullable!DateTime dt) {
    import std.exception : enforce;
    enforce(!dt.isNull, "datetime must not be null");
    return toUTCDate(dt.get);
}

// "2014-10-30T06:12:00Z"
string toUTCDate(DateTime dt) {
    import std.string : format;
    return format!"%04d-%02d-%02dT%02d:%02d:%02dZ"(
        dt.date.year,
        dt.date.month,
        dt.date.day,
        dt.timeOfDay.hour,
        dt.timeOfDay.minute,
        dt.timeOfDay.second,
    );
}

class FilterCondition : Filter {
    @serdeIgnoreOutIf!`a.length == 0`
    string inMailbox;

    @serdeIgnoreOutIf!`a.isNull`
    Nullable!(string[])inMailboxOtherThan;

    @serdeIgnoreOutIf!`a.isNull`
    @serdeTransformOut!toUTCDate
    Nullable!DateTime before;

    @serdeIgnoreOutIf!`a.isNull`
    @serdeTransformOut!toUTCDate
    Nullable!DateTime after;

    @serdeIgnoreOutIf!`a.isNull`
    Nullable!uint minSize;

    @serdeIgnoreOutIf!`a.isNull`
    Nullable!uint maxSize;

    @serdeIgnoreOutIf!`a.length == 0`
    string allInThreadHaveKeyword;

    @serdeIgnoreOutIf!`a.length == 0`
    string someInThreadHaveKeyword;

    @serdeIgnoreOutIf!`a.length == 0`
    string noneInThreadHaveKeyword;

    @serdeIgnoreOutIf!`a.length == 0`
    string hasKeyword;

    @serdeIgnoreOutIf!`a.length == 0`
    string notKeyword;

    @serdeIgnoreOutIf!`a.length == 0`
    string text;

    @serdeIgnoreOutIf!`a.length == 0`
    string from;

    @serdeIgnoreOutIf!`a.length == 0`
    string to;

    @serdeIgnoreOutIf!`a.length == 0`
    string cc;

    @serdeIgnoreOutIf!`a.length == 0`
    string bcc;

    @serdeIgnoreOutIf!`a.length == 0`
    string subject;

    @serdeIgnoreOutIf!`a.length == 0`
    @serdeKeys("body")
    string body_;

    @serdeIgnoreOutIf!`a.isNull`
    Nullable!(string[])header;

    override string toString() const {
        import asdf : jsonSerializer;
        import std.array : appender;
        return serializeToJson(this);
        /+
        auto app = appender!(char[]);
        auto ser = jsonSerializer!("\t")((const(char)[] chars) => app.put(chars));
        serialize(ser);
        ser.flush;
        return cast(string)(app.data); +/
    }
/+
    void serialize(S)(ref S serializer)
    {
        doSerialize(serializer,this);
    }
+/

    this(string inMailbox = null,
            Nullable!(string[])inMailboxOtherThan = nullArray,
            string before = null,
            string after = null,
            Nullable!uint minSize = NullUint,
            Nullable!uint maxSize = NullUint,
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
            Nullable!(string[])header = nullArray, ) {
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

Filter operatorAsFilter(FilterOperator filterOperator) {
    return cast(Filter) filterOperator;
}

Filter conditionAsFilter(FilterCondition filterCondition) {
    return cast(Filter) filterCondition;
}


struct Comparator {
    string property;
    bool isAscending = true;
    string collation = null;
}


struct JmapRequest {
    string[] using;
    Invocation[] methodCalls;
    string[string] createdIds = null;
}

struct JmapResponse {
    Invocation[] methodResponses;
    string[string] createdIds;
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

private void serializeAsAsdf(S)(Variable v, ref S serializer) {
    import std.range : iota;
    import kaleidic.sil.lang.types : SilVariant, KindEnum;
    import kaleidic.sil.lang.builtins : fnArray;

    final switch (v.kind) {
        case KindEnum.void_:
            serializer.putValue(null);
            return;

        case KindEnum.object:
            auto var = v.get!SilVariant;
            auto acc = var.type.objAccessor;
            if (acc is null) {
                serializer.putValue("object");
                return;
            }
            auto obj = serializer.objectBegin();
            foreach (member; acc.listMembers) {
                serializer.putKey(member);
                serializeAsAsdf(acc.readProperty(member, var), serializer);
            }
            serializer.objectEnd(obj);
            return;

        case KindEnum.variable:
            serializeAsAsdf(v.get!Variable, serializer);
            return;

        case KindEnum.function_:
            serializer.putValue("function"); // FIXME
            return;

        case KindEnum.boolean:
            serializer.putValue(v.get!bool);
            return;

        case KindEnum.char_:
            serializer.putValue([(v.get!char)].idup);
            return;

        case KindEnum.integer:
            serializer.putValue(v.get!long);
            return;

        case KindEnum.number:
            import std.format : singleSpec;
            import kaleidic.sil.lang.util : fullPrecisionFormatSpec;
            enum spec = singleSpec(fullPrecisionFormatSpec!double);
            serializer.putNumberValue(v.get!double, spec);
            return;

        case KindEnum.string_:
            serializer.putValue(v.get!string);
            return;

        case KindEnum.table:
            auto obj = serializer.objectBegin();
            foreach (ref kv; v.get!SilStruct.byKeyValue) {
                serializer.putKey(kv.key);
                serializeAsAsdf(kv.value, serializer);
            }
            serializer.objectEnd(obj);
            return;

        case KindEnum.array:
            auto v2 = v.getAssume!(Variable[]);
            auto arr = serializer.arrayBegin();
            foreach (elem; v2) {
                serializer.elemBegin;
                serializeAsAsdf(elem, serializer);
            }
            serializer.arrayEnd(arr);
            return;

        case KindEnum.arrayOf:
            auto v2 = v.getAssume!(KindEnum.arrayOf);
            auto arr = serializer.arrayBegin();
            foreach (i; v2.getLength().iota) {
                serializer.elemBegin;
                Variable elem = v2.getElement(i);
                serializeAsAsdf(elem, serializer);
            }
            serializer.arrayEnd(arr);
            return;

        case KindEnum.rangeOf:
            serializeAsAsdf(fnArray(v), serializer);
            return;
    }
    assert(0);
}

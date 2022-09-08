module jmap.types;
import std.datetime : SysTime;
import core.time : seconds;
import imap.sil : SILdoc;
import mir.algebraic : Nullable, visit;
import mir.algebraic_alias.json;
import mir.array.allocation : array;
import mir.ion.conv : serde;
import mir.deser.json : deserializeJson;
import mir.ser.json : serializeJson, serializeJsonPretty;
import mir.ndslice.topology : as, member, map;
import mir.serde;
import mir.exception : MirException, enforce;
import mir.format : text;
import std.datetime : DateTime;
import asdf;

version (SIL) {
    import kaleidic.sil.lang.typing.types : Variable, SilStruct;
}

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

@serdeIgnoreUnexpectedKeys
struct AccountCapabilities {
    @serdeKeys("urn:ietf:params:jmap:mail")
    AccountParams accountParams;

    @serdeOptional
    @serdeKeys("urn:ietf:params:jmap:submission")
    SubmissionParams submissionParams;

    // @serdeIgnoreIn Asdf vacationResponseParams;
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

@serdeIgnoreUnexpectedKeys
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
version(SIL):
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

    Variable queryEmails(FilterAlgebraic filter, Variable sort, int position = 0, string anchor = "", int anchorOffset = 0, Nullable!uint limit = (Nullable!uint).init, bool calculateTotal = false, bool collapseThreads = false, SilStruct additionalArguments = null) {
        import std.exception : enforce;
        import std.stdio : stderr, writeln;
        if (collapseThreads)
            additionalArguments["collapseThreads"] = Variable(true);
        import mir.ion.conv: serde;
        Variable filterVariable = filter.serde!Variable;
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

version(SIL){

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
}} //SIL

enum FilterOperatorKind {
    @serdeKeys("AND") and,
    @serdeKeys("OR") or,
    @serdeKeys("NOT") not,
}

alias FilterAlgebraic = Nullable!(FilterOperator, FilterCondition);

// Holder is required to workaround compliler circular bug
@serdeProxy!FilterAlgebraic 
struct Filter {
    FilterAlgebraic filter;
    alias filter this;
@safe pure nothrow @nogc:

    this(FilterAlgebraic filter) {
        this.filter = filter;
    }

    this(FilterOperator operator) {
        filter = operator;
    }

    this(FilterCondition condition) {
        filter = condition;
    }
}

// checks de/serialization compiles
unittest
{
    import mir.ser.json;
    import mir.deser.json;
    assert(Filter.init.serializeJson);
    assert(`null`.deserializeJson!Filter == Filter.init);
}

deprecated("use FilterCondition instead")
FilterCondition filterCondition(string inMailbox = null,
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
    import std.stdio : stderr;
    static warned = false;
    if (!warned) {
        stderr.writefln("filterCondition() will be removed in the future, switch your code to use FilterCondition()");
        warned = true;
    }
    return FilterCondition(inMailbox, inMailboxOtherThan, before, after, minSize,
            maxSize, allInThreadHaveKeyword, someInThreadHaveKeyword, noneInThreadHaveKeyword,
            hasKeyword, notKeyword, text, from, to, cc, bcc, subject, body_, header);
}

struct FilterOperator {
    FilterOperatorKind operator;
    Filter[] conditions;
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

deprecated("use filter constructor instead")
Filter operatorAsFilter(FilterOperator filterOperator) {
    import std.stdio : stderr;
    static warned = false;
    if (!warned) {
        stderr.writefln("filterCondition() will be removed in the future, switch your code to use FilterCondition()");
        warned = true;
    }
    return cast(Filter) filterOperator;
}

struct Comparator {
    string property;
    bool isAscending = true;
    string collation = null;
}

version(SIL):

struct JmapRequest {
    const(string)[] using;
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

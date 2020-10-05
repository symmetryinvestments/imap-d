module jmap.api;
import jmap.types;
static import jmap.types;

version (SIL) {
    import kaleidic.sil.lang.handlers : Handlers;
    import kaleidic.sil.lang.types : Variable, Function, SILdoc;
    import kaleidic.sil.lang.builtins : Maybe;

    void registerHandlersJmap(ref Handlers handlers) {
        import std.meta : AliasSeq;
        handlers.openModule("jmap");
        scope (exit) handlers.closeModule();

        static foreach (T; AliasSeq!(Credentials, JmapSessionParams, Session, Mailbox, MailboxRights, MailboxSortProperty, Filter, FilterOperator, FilterOperatorKind, FilterCondition, Comparator, Account, AccountParams, AccountCapabilities, SessionCoreCapabilities, Contact, ContactGroup, ContactInformation, JmapFile, EmailAddress, Envelope, ContactAddress, ResultReference, JmapResponseError, EmailProperty, EmailBodyProperty, Maybe))
            handlers.registerType!T;

        static foreach (F; AliasSeq!(getSession, getSessionJson, wellKnownJmap, operatorAsFilter, filterCondition, addQuotes, uniqBy, mailboxPath, allMailboxPaths,
                                     findMailboxPath))
            handlers.registerHandler!F;
    }
}

version (SIL) :


    Variable[] uniqBy(Variable[] input, Function f) {
        import std.algorithm : uniq;
        import std.array : array;
        return input.uniq!((a, b) => f(a, b).get!bool).array;
    }

string addQuotes(string s) {
    if (s.length < 2 || s[0] == '"' || s[$ - 1] == '"')
        return s;
    return '"' ~ s ~ '"';
}


struct JmapSessionParams {
    Credentials credentials;
    string uri;
}

auto wellKnownJmap(string baseURI) {
    import std.format : format;
    import std.algorithm : endsWith;
    return baseURI.endsWith(".well-known/jmap") ? baseURI : format!"%s/.well-known/jmap"(baseURI);
}

string getSessionJson(JmapSessionParams params) {
    return getSessionJson(params.uri, params.credentials);
}

private string getSessionJson(string uri, Credentials credentials) {
    import requests : Request, BasicAuthentication;
    auto req = Request();
    req.authenticator = new BasicAuthentication(credentials.user, credentials.pass);
    auto result = cast(string) req.get(uri.wellKnownJmap).responseBody.data.idup;
    return result;
}

Session getSession(JmapSessionParams params) {
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


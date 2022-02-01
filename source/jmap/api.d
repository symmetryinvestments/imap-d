module jmap.api;
import jmap.types;
static import jmap.types;

version (SIL) {
    void registerHandlersJmap(Handlers)(ref Handlers handlers) {
        import kaleidic.sil.lang.typing.types : Variable, Function;
        import std.meta : AliasSeq;
        handlers.openModule("jmap");
        scope (exit) handlers.closeModule();

        static foreach (T; AliasSeq!(Credentials, JmapSessionParams, Session, Mailbox, MailboxRights, MailboxSortProperty, Filter, FilterOperator, FilterOperatorKind, FilterCondition, Comparator, Account, AccountParams, AccountCapabilities, SessionCoreCapabilities, Contact, ContactGroup, ContactInformation, JmapFile, EmailAddress, Envelope, ContactAddress, ResultReference, JmapResponseError, EmailProperty, EmailBodyProperty))
            handlers.registerType!T;

        static foreach (F; AliasSeq!(getSession, getSessionJson, wellKnownJmap, operatorAsFilter, filterCondition, addQuotes, uniqBy, mailboxPath, allMailboxPaths,
                                     findMailboxPath))
            handlers.registerHandler!F;
    }

    Variable[] uniqBy(Variable[] input, Function f) {
        import std.algorithm : uniq;
        import std.array : array;
        return input.uniq!((a, b) => f(a, b).get!bool).array;
    }

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

version (SIL) :

Session getSession(JmapSessionParams params) {
    import mir.ion.deser.json : deserializeJson;
    import std.string : strip;
    import std.exception : enforce;
    import std.algorithm : startsWith;
    import std.stdio : writeln;

    auto json = getSessionJson(params).strip;
    writeln(json);
    enforce(json.startsWith("{") || json.startsWith("["), "invalid json response: \n" ~ json);
    auto ret = json.deserializeJson!Session;
    ret.credentials = params.credentials;
    return ret;
}

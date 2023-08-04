module jmap.api;
import jmap.types;
static import jmap.types;

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
    import mir.deser.json : deserializeJson;
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

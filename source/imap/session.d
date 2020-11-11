///
module imap.session;
import imap.defines;
import imap.socket;
import imap.set;
import imap.sil : SILdoc;

import core.stdc.stdio;
import core.stdc.string;
import core.stdc.errno;
import std.socket;
import core.time : Duration;

import deimos.openssl.ssl;
import deimos.openssl.err;
import deimos.openssl.sha;


struct SSL_ {
    SSL* handle;
    alias handle this;
}


///
Set!T removeValues(T)(Set!T set, T[] values) {
    import std.algorithm : each;
    Set!T ret;
    set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
    foreach (value; values) {
        if (value in ret)
            ret.remove(value);
    }
    return ret;
}

///
Set!T addValues(T)(Set!T set, T[] values) {
    import std.algorithm : each;
    Set!T ret;
    set.values_.byKeyValue.each!(entry => ret[entry.key] = entry.value);
    values.each!(value => set.values_[value] = true);
    return ret;
}

///
Set!T addSet(T)(Set!T lhs, Set!T rhs) {
    import std.algorithm : each;
    Set!T ret;
    return lhs.addValues(rhs.values);
}

///
Set!T removeSet(T)(Set!T lhs, Set!T rhs) {
    import std.algorithm : each;
    Set!T ret;
    return lhs.removeValues(rhs.values);
}

///
struct ImapServer {
    string server = "imap.fastmail.com"; // localhost";
    string port = "993";

    string toString() {
        import std.format : format;
        return format!"%s:%s"(server, port);
    }
}

///
struct ImapLogin {
    @SILdoc("User's name. It takes a string as a value.")
    string username = "laeeth@kaleidic.io";

    @SILdoc("User's secret keyword. If a password wasn't supplied the user will be asked to enter one interactively the first time it will be needed. It takes a string as a value.")
    string password;

    string toString() {
        import std.format : format;
        return format!"%s:[hidden]"(username);
    }
}

///
struct Options {
    import core.time : Duration, seconds, minutes;

    bool debugMode = false;
    bool verboseOutput = false;
    bool interactive = false;
    bool namespace = false;

    @SILdoc("When this option is enabled and the server supports the Challenge-Response Authentication Mechanism (specifically CRAM-MD5), this method will be used for user authentication instead of a plaintext password LOGIN. This variable takes a boolean as a value. Default is false")
    bool cramMD5 = false;

    bool startTLS = false;
    bool tryCreate = false;
    bool recoverAll = true;
    bool recoverErrors = true;

    @SILdoc("Normally, messages are marked for deletion and are actually deleted when the mailbox is closed. When this option is enabled, messages are expunged immediately after being marked deleted. This variable takes a boolean as a value. Default is false")
    bool expunge = false;

    @SILdoc("By enabling this option new mailboxes that were automatically created, get also subscribed; they are set active in order for IMAP clients to recognize them. This variable takes a boolean as a value. Default is false")
    bool subscribe = false;

    bool wakeOnAny = true;

    @SILdoc("The time in minutes before terminating and re-issuing the IDLE command, in order to keep alive the connection, by resetting the inactivity timeout of the server. A standards compliant server must have an inactivity timeout of at least 30 minutes. But it may happen that some IMAP servers don't respect that, or some intermediary network device has a shorter timeout. By setting this option the above problem can be worked around. This variable takes a number as a value. Default is 29 minutes. ")
    Duration keepAlive = 29.minutes;

    string logFile;
    string configFile;
    string oneline;
    string trustStore = "/etc/ssl/certs";
    string trustFile = "/etc/ssl/certs/cert.pem";
    Duration timeout = 20.seconds;
}

///
final class Session {
    import imap.defines : ImapStatus;
    import imap.namespace;
    Options options;
    ImapStatus status_;
    string server;

    @SILdoc("The port to connect to. It takes a number as a value. Default is ''143'' for imap and ''993'' for imaps.")
    string port;

    package AddressInfo addressInfo;
    ImapLogin imapLogin;
    Socket socket;
    ImapProtocol imapProtocol;
    Set!Capability capabilities;
    string namespacePrefix;
    char namespaceDelim = '\0';
    Mailbox selected;

    bool useSSL = true;
    bool noCerts = true;
    ProtocolSSL sslProtocol = ProtocolSSL.tls1_2; // ssl3; // tls1_2;
    SSL* sslConnection;
    SSL_CTX* sslContext;

    override string toString() {
        import std.array : Appender;
        import std.format : format;
        import std.conv : to;
        Appender!string ret;
        ret.put(format!"Session to %s:%s as user %s\n"(server, port, imapLogin.username));
        ret.put(format!"- useSSL: %s\n"(useSSL.to!string));
        ret.put(format!"- startTLS: %s\n"(useSSL.to!string));
        ret.put(format!"- noCerts: %s\n"(noCerts.to!string));
        ret.put(format!"- sslProtocol: %s\n"(sslProtocol.to!string));
        ret.put(format!"- imap protocol: %s\n"(imapProtocol.to!string));
        ret.put(format!" - capabilities: %s\n"(capabilities.to!string));
        ret.put(format!" - namespace: %s/%s\n"(namespacePrefix, [namespaceDelim]));
        ret.put(format!" - selected mailbox: %s\n"(selected));
        return ret.data;
    }

    this(ImapServer imapServer, ImapLogin imapLogin, bool useSSL = true, Options options = Options.init) {
        import std.exception : enforce;
        import std.process : environment;
        this.options = options;
        this.server = imapServer.server;
        this.port = imapServer.port;
        this.useSSL = useSSL;
        this.imapLogin = imapLogin;
    }

    Session useStartTLS(bool useTLS = true) {
        this.options.startTLS = useTLS;
        return this;
    }

    Session setSelected(Mailbox mailbox) {
        this.selected = mailbox;
        return this;
    }

    Session setStatus(ImapStatus status) {
        this.status_ = status;
        return this;
    }

    string status() {
        import std.conv : to;
        return status_.to!string;
    }
}


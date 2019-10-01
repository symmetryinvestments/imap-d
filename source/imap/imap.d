module imap.imap;
version(None):
import std.stdio;
version(SSL) import deimos.openssl.ssl;
import imap.session;
import imap.list;
import imap.buffer;
import imap.regexp;
import imap.defines;
import std.string;
import core.stdc.locale;
import std.getopt;
// c errno
// limits
// stat
// locale
// openssl ssl err

extern Buffer ibuf, obuf, nbuf, cbuf;
extern Regexp* responses;
extern SSL_CTX *ssl3ctx;
extern SSL_CTX *ssl23ctx;
extern SSL_CTX *tls1ctx;
static if (OPENSSL_VERSION_NUMBER >= 0x01000100fL)
{
	extern SSL_CTX* tls11ctx;
	extern SSL_CTX* tls12ctx;
}

Options opts;			/* Program options. */
Environment env;		/* Environment variables. */

List *sessions = null ;		/* Active IMAP sessions. */

//IMAPFilter: an IMAP mail filtering utility.
int main(string[] args)
{
	int c;
	char* cafile = null, capath = null ;

	setlocale(LC_CTYPE, "");

	opts.verbose = 0;
	opts.interactive = 0;
	opts.log = null ;
	opts.config = null ;
	opts.oneline = null ;
	opts.debug_ = null ;

	opts.truststore = null ;
	if (exists_dir("/etc/ssl/certs"))
		opts.truststore = "/etc/ssl/certs";
	else if (exists_file("/etc/ssl/cert.pem"))
		opts.truststore = "/etc/ssl/cert.pem";

	env.home = null ;
	env.pathmax = -1;

	void setInteractive(string key, string val)
	{
		enforce(key=="interactive|i");
		if(val.length==0)
			opt.interactive=1;
		else
			opt.interactive=val.to!int;
	}

	bool reportVersion=false;
	auto helpInformation=getopt(
		args,
		"version|v", &reportVersion,
		"config|c", &opts.config,
		"debug|d", &opts.debug_,
		"oneline|e",&opts.oneline,
		"interactive|i",&setInteractive,
		"log|l",&opts.log,
		"truststore|t",&opt.truststore,
		"verbose|b", &opts.verbose
		);
	if(reportVersion)
	{
		version_func();
		return(1);
	}
	if (helpInformation.wanted)
	{
		defaultGetOptPrinter("imap_d",helpInformation.options);
		usage();
		return(1);
	}
	

	get_pathmax();
	open_debug();
	create_homedir();
	catch_signals();
	open_log();
	if ((opts.config is null  )||(opts.config.length==0))
		opts.config = get_filepath("config.lua");

	buffer_init(&ibuf, INPUT_BUF);
	buffer_init(&obuf, OUTPUT_BUF);
	buffer_init(&nbuf, NAMESPACE_BUF);
	buffer_init(&cbuf, CONVERSION_BUF);

	regexp_compile(responses);

	SSL_library_init();
	SSL_load_error_strings();
	ssl3ctx = SSL_CTX_new(SSLv3_client_method());
	ssl23ctx = SSL_CTX_new(SSLv23_client_method());
	tls1ctx = SSL_CTX_new(TLSv1_client_method());
	static if (OPENSSL_VERSION_NUMBER >= 0x01000100fL)
	{
		tls11ctx = SSL_CTX_new(TLSv1_1_client_method());
		tls12ctx = SSL_CTX_new(TLSv1_2_client_method());
	}
	if (exists_dir(opts.truststore))
		capath = opts.truststore;
	else if (exists_file(opts.truststore))
		cafile = opts.truststore;
	SSL_CTX_load_verify_locations(ssl3ctx, cafile, capath);
	SSL_CTX_load_verify_locations(ssl23ctx, cafile, capath);
	SSL_CTX_load_verify_locations(tls1ctx, cafile, capath);
	static if( OPENSSL_VERSION_NUMBER >= 0x01000100fL)
	{
		SSL_CTX_load_verify_locations(tls11ctx, cafile, capath);
		SSL_CTX_load_verify_locations(tls12ctx, cafile, capath);
	}

	start_lua();
	static if(LUA_VERSION_NUM < 502)
	{
		{
			Session *s;

			List *l = sessions;
			while (l !is null ) {
				s = l.data;
				l = l.next;

				request_logout(s);
			}
		}
	}
	stop_lua();

	SSL_CTX_free(ssl3ctx);
	SSL_CTX_free(ssl23ctx);
	SSL_CTX_free(tls1ctx);
	static if (OPENSSL_VERSION_NUMBER >= 0x01000100fL)
	{
		SSL_CTX_free(tls11ctx);
		SSL_CTX_free(tls12ctx);
	}
	ERR_free_strings();

	regexp_free(responses);

	buffer_free(&ibuf);
	buffer_free(&obuf);
	buffer_free(&nbuf);
	buffer_free(&cbuf);

	xfree(env.home);

	close_log();
	close_debug();

	exit(0);
}


// Print a very brief usage message.
void usage()
{

	stderr.writefln("usage: imap [-iVv] [-c configfile] " ~
	    			"[-d debugfile] [-e 'command'] [-l logfile]");
}


 // Print program's version and copyright.
void version_func()
{

	stderr.writefln("IMAPFilter %s  %s", VERSION, COPYRIGHT);
}

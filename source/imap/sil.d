module imap.sil;

version(SIL) { public import kaleidic.sil.lang.types : SILdoc; }
else
{
	struct SILdoc
	{
		string value;
	}
}



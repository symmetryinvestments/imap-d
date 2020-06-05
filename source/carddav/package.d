module carddav;
/+
struct AddressDataType
{
	string contentType;
	string version_;
}

struct AddressBook struct
{
	string path;
	string name;
	string description;
	long maxResourceSize;
	AddressDataType[] supportedAddressData;
}

func (ab *AddressBook) SupportsAddressData(contentType, version string) bool {
	if len(ab.SupportedAddressData) == 0 {
		return contentType == "text/vcard" && version == "3.0"
	}
	for _, t := range ab.SupportedAddressData {
		if t.ContentType == contentType && t.Version == version {
			return true
		}
	}
	return false
}

struct AddressBookQuery
{
	AddressDataRequest dataRequest;

	PropFilter[] propFilters;
	FilterTst filterTest; // defaults to FilterAnyOf
	int limit; // <= 0 means unlimited
}

struct AddressDataRequest
{
	string[] props;
	bool allProp;
}

type PropFilter struct {
	Name string
	Test FilterTest // defaults to FilterAnyOf

	// if IsNotDefined is set, TextMatches and Params need to be unset
	IsNotDefined bool
	TextMatches  []TextMatch
	Params       []ParamFilter
}

type ParamFilter struct {
	Name string

	// if IsNotDefined is set, TextMatch needs to be unset
	IsNotDefined bool
	TextMatch    *TextMatch
}

type TextMatch struct {
	Text            string
	NegateCondition bool
	MatchType       MatchType // defaults to MatchContains
}

type FilterTest string

const (
	FilterAnyOf FilterTest = "anyof"
	FilterAllOf FilterTest = "allof"
)

type MatchType string

const (
	MatchEquals     MatchType = "equals"
	MatchContains   MatchType = "contains"
	MatchStartsWith MatchType = "starts-with"
	MatchEndsWith   MatchType = "ends-with"
)

type AddressBookMultiGet struct {
	Paths       []string
	DataRequest AddressDataRequest
}

type AddressObject struct {
	Path    string
	ModTime time.Time
	ETag    string
	Card    vcard.Card
}

//SyncQuery is the query struct represents a sync-collection request
type SyncQuery struct {
	DataRequest AddressDataRequest
	SyncToken   string
	Limit       int // <= 0 means unlimited
}

//SyncResponse contains the returned sync-token for next time
type SyncResponse struct {
	SyncToken string
	Updated   []AddressObject
	Deleted   []string
}
+/

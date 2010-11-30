use Test::More;
eval q{ use Test::Spelling };
plan skip_all => "Test::Spelling is not installed." if $@;
add_stopwords(map { split /[\s\:\-]/ } <DATA>);
$ENV{LANG} = 'C';
all_pod_files_spelling_ok('lib');
__DATA__
Tokuhiro Matsuno
Furl
tokuhirom
AAJKLFJEF
GMAIL
COM
Tatsuhiko
Miyagawa
Kazuhiro
Osawa
lestrrat
typester
cho45
charsbar
coji
clouder
gunyarakun
hio_d
hirose31
ikebe
kan
kazeburo
daisuke
maki
TODO
API
URL
URI
db
http
url
SSL
san
OSX
XP
FAQ
chunked
github
Kazuho
Oku
gfx
mala
mattn
ArrayRef
HashRef
Str
IDN
APIs
de
facto
com
picohttpparser
req
RFC
Goro
TCP
walf443
callback
uri
behaviour
hostnames
IP
EINTR
XS
backend


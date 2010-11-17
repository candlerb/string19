Towards an alternative approach
===============================

The top three issues I have with ruby 1.9 are:

1. It doesn't add anything to simple expressions like "a << b" except that
   they can now crash under certain input conditions - and this is the sort of
   thing which is difficult to pick up in unit testing.

   Similarly, regular expression matches are more likely to crash given
   unexpected or malformed input.

2. There are myriad rules and inconsistencies - e.g. that data read from a
   File defaults to the environment locale, but data read from a Socket
   defaults to ASCII-8BIT.

3. The same program and data can behave differently on different machines,
   dependent on the environment locale.

This last point is in some cases the desired behaviour, because tools like
'sed' also behave in this way:

    $ echo "über" >/tmp/str
    $ sed -e 's/.//' /tmp/str
    ber
    $ env LC_ALL=C sed -e 's/.//' /tmp/str
    �ber

But note that:

1. sed is inherently a text-processing tool, whereas ruby is often used
   for processing binary data;

2. sed doesn't crash when given invalid input:
        $ echo -e "\xfcber"
        �ber
        $ echo -e "\xfcber" >/tmp/str
        $ sed -e 's/.//' /tmp/str
        �er

3. sed doesn't need to introduce its own library of encodings, but just
   uses the facilities provided by the underlying OS. (Having said that, I
   don't know exactly *how* sed deals with encodings. Does it handle UTF-8
   specially? Are other encodings mbrtowc'd or iconv'd, and then converted
   back again for output?)

Anyway, given all this, how do I think ruby should have dealt with the issue
of encodings?


Option 0: Don't tag strings
---------------------------

What I mean is, leave Strings as one-dimensional arrays of bytes, not tagged
with any encoding.  This basically rolls things back to ruby 1.8, and this
is what I'm sticking with.

For people who want to use non-ASCII text, make them work with UTF-8.
There is regexp support for this in 1.8 already. Some extra methods could
be added to make life more convenient, e.g.

* counting the number of characters: `str.charsize`
* extracting characters: `str.substr(0..50)`
* transcoding: `str.encode("ISO-8859-1", "UTF-8")`


Option 1: binary and UTF-8
--------------------------

Python 3.0 and Erlang both have two distinct data structures, one for binary
data and one for UTF-8 text.  This could be implemented as two classes, e.g. 
String and Binary, or as a String with a one-bit binary flag.

You'd need some way to distinguish a binary literal from a string one,
maybe just Binary.new(...)

The main difference between this and option 0 is that [], length, chop etc
would work differently on binaries and strings, whereas option 0 above would
have different methods like String#substr, String#charsize, String#charchop
etc.

TODO: flesh out the various cases like what happens when combining String
and Binary.

Going with either option 0 or 1 would eliminate most of the complexity
inherent in ruby 1.9.

All non-UTF-8 data would be transcoded at the boundary (something which is
needed for stateful encodings like ISO-2022-JP anyway).

What you'd lose is the ability to handle things like EUC-JP and GB2312
"natively", without transcoding to UTF-8 and back again.  Is that important? 
Aren't these "legacy" character sets anyway?  If it is important, you could
still have an external library for dealing with them natively.

UTF-16 and UTF-32 would also need transcoding, but this is lossless.

You'd lose the ability to write ruby scripts in non-UTF-8 character sets,
but on the plus side, all the rules for #encoding tags would no longer be
needed.  Note that ruby 1.9 requires constants to start with capital 'A' to
'Z', so it's not possible to write programs entirely in non-Roman scripts
anyway.

Programs which use non-UTF-8 data would have to be written to take this into
account.  e.g.

    File.open("/path/to/data", "r:IBM437")   # transcode to UTF-8
    File.open("/path/to/data2", "w:IBM437")  # transcode from UTF-8

I have no objection to making "r:locale" and "w:locale" available, but IMO
that should not be the default.


Option 2: Band-aids
-------------------

Given that so much effort has been invested in tagging strings throughout
ruby 1.9, and the huge loss of face which would be involved in reversing
that decision, I don't expect this ever to happen.

So could we apply some tweaks to the current system to make it more
reasonable? Here are some options.

* When opening a text file ("r" or "w" as opposed to "rb" or "wb") then
  make the external encoding default to UTF-8. If you want it to be
  different then use "r:<encoding>" or "r:locale" when opening a file.

  Or even make it default to US-ASCII, like source encodings do. This
  is consistent and *forces* people to decide whether to open a file as
  UTF-8, some other encoding, or guess from the locale.

  (Making both files and source encodings default to UTF-8 is perhaps
  more helpful though)

* Have a universally-compatible "BINARY" encoding. Any operation between
  BINARY and FOO gives encoding BINARY, and transcoding between BINARY and
  any other encoding is a null operation.

* Treat invalid characters in the same way as String#[] does, i.e. never
  raise an exception. In particular, regexp matching always succeeds.

Whilst this may make programs less fragile, it could also end up with the
set of rules for Strings becoming even more complex, not less.


Option 3: Automatic transcoding
-------------------------------

There seems to me to be little benefit in having every single String in your
program tagged with an encoding, if the main thing it does is introduce
opportunities for Ruby to raise exceptions when these strings encounter each
other.

But if Ruby trancoded strings automatically as required, this might actually
become useful.

Consider: I'm building up a string of UTF-8 characters. Then I append a
string of ISO-8859-1. Hey presto, it is converted to UTF-8 and appended, and
the program continues happily. Ditto when interpolating:

    "This error message incorporates #{str1} and #{str2}"

where str1 and str2 could be of different encodings. They would both be
transcoded to the source encoding of the outer string.

Proposed rules:

* Everything is compatible with everything else, by definition.

* If I combine str1 (encoding A) with str2 (encoding B), then str2 is
transcoded to encoding A before the operation starts, and the result is of
encoding A.

* If I match str (encoding S) with regexp (encoding R), then *regexp* is
transcoded to encoding S automatically.

    Consider, for example, that

        str =~ /abc/

    would work even if str were in a wide encoding like UTF-16BE, which
    would contain "\x00a\x00b\x00c", because the regexp has been transcoded
    to a UTF-16BE regexp behind the scenes.

    For efficiency, multiple encoding representations of the same regexp
    could be stored as a cache inside the regexp object itself, generated
    on demand.

* Have a binary regexp /./n which matches one *byte* always (whereas /./
would match one *character* in the source string, in the source's encoding)

* Transcoding errors could still occur, but I think these should normally
default to substituting a ? character. If you want to raise an exception
then use the `encode` or `encode!` methods with appropriate arguments to
request this behaviour.

* Transcoding to or from ASCII-8BIT is a null operation, so if you are
working with binary all you need to do is ensure one of your arguments is
ASCII-8BIT.

* As another example:

        s2 = s1.tr("as","Aß")

    would first transcode both "as" and "Aß" to the encoding of s1, before
    running the tr method. This would therefore work even if s1 were in a wide
    encoding, and s2 would still be in a wide encoding. It would also work if s1
    were in ISO-8859-1 but the source encoding of the file were UTF-8, since
    both have a representation for "ß".

* To be fully consistent, transcoding should take place on output as well as
input.  e.g.  if STDIN's external encoding is taken from the locale, then
STDOUT's external encoding should also be taken from the locale. Writing
a string tagged as ISO-8859-1 to STDOUT should transcode it automatically.

There are some issues to consider though. For example, what happens for
`str1<=>str2` where they are of different encodings?  Do we transcode str2
to str1's encoding just for the comparison, and then throw that
representation away?  This could make repeated comparisons (e.g. for
sorting) very expensive.  Perhaps the alternative representations need to
be cached, similar to the ascii_only? flag.

I haven't worked this all the way through, but I believe you would end up
with a much simpler set of rules for combining strings of different
encodings. Encoding.compatible? would be dropped completely, and
String#ascii_only? would become purely an optimisation (so that transcoding
becomes a null operation in common cases)

It would also be much easier to reason about encodings, because for an
expression like s3 = s1 + s2 the encoding of s3 will always be the encoding
of s1.

This does introduce some asymmetry, but it's still got to be better than
raising exceptions. It's quite a fundamental change though.

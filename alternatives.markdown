Alternative approaches
======================

I suppose I can't criticise all this without offering some alternatives
(other than sticking with 1.8 of course)

1. Automatic transcoding
------------------------

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
    could be stored as a cache inside the regexp object itself.

* Have a binary regexp /./n which matches one *byte* always (whereas /./
would match one *character* in the source string, in the source's encoding)

* Transcoding errors could still occur, but I think these should normally
default to substituting a ? character. If you want to raise an exception
then use the `encode` or `encode!` methods with appropriate arguments to
request this behaviour - or there could be a global variable to set the
default behaviour.

* Transcoding to or from ASCII-8BIT is a null operation, so if you are
working with binary all you need to do is ensure one of your arguments is
ASCII-8BIT.

As another example:

    s2 = s1.tr("as","Aß")

would first transcode both "as" and "Aß" to the encoding of s1, before
running the tr method. This would therefore work even if s1 were in a wide
encoding, and s2 would still be in a wide encoding. It would also work if s1
were in ISO-8859-1 but the source encoding of the file were UTF-8, since
both have a representation for "ß".

I haven't worked this all the way through, but I believe you would end up
with a much simpler set of rules for combining strings of different
encodings. Encoding.compatible? would be dropped completely, and
String#ascii_only? would become purely an optimisation (so that transcoding
becomes a null operation in common cases)

It would also be much easier to reason about encodings, because for an
expression like s3 = s1 + s2 the encoding of s3 will always be the encoding
of s1.

This does introduce some asymmetry, but it's still got to be better than
raising exceptions. It's quite a fundamental change though, and probably
too late for ruby 1.9.x.

2. Universally compatible BINARY encoding
-----------------------------------------

* Make ASCII-8BIT compatible with every other encoding, and the result is
always ASCII-8BIT

* A regexp match between an ASCII-8BIT string and a regexp with encoding R
takes place as if the string had encoding R

* Transcoding from ASCII-8BIT to any other encoding is a null operation and
always succeeds

This would be very easy to implement, but I consider it a band-aid only. It
only helps people working with binary, and it adds even more rules to
remember.

3. Separate encoding-aware class
--------------------------------

Allow the user to deal in raw strings of bytes that have no encoding at all
(as opposed to an encoding of ASCII-8BIT, which still has its own rules for
compatibility etc)

This could have been done by leaving String as it was in 1.8, and have a new
class which wraps a String with an Encoding: e.g.

    str = Chars("hello", "UTF-8")

* Chars#to_str would return just the String. Therefore any operation between
String and Chars would succeed, and return a String.

* String#[] and ?x would be changed to give a one-character string, as in 1.9

* Chars#[] would then give a Chars object containing one character, and so
on, duck-typing String but returning Chars instead.

* File I/O could be modified to return Chars objects, but only if you
explicitly ask for it (and it should not use the encoding from the
environment locale unless you ask for that too)

* Do we need a per-file Source encoding at all? If so, it could be made a
constant like `__FILE__` and `__LINE__`:

        str = Chars("hello", __ENCODING__)

This approach means that encoding behaviour is optional, expandable (e.g. to
include locale behaviour in future), and code could be made 1.8-compatible
just by adding a few .to_str calls - whereas at the moment, code has to
choose between calling .size or .bytesize dependent on whether it's running
under 1.8.6 or 1.9.

However I expect something like this was considered when 1.9 was being
designed, and rejected as being too clumsy.

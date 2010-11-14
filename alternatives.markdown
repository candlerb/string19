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


Option 1: Don't tag strings
---------------------------

What I mean is, turn Strings back into being one-dimensional arrays of
bytes, not tagged with any encoding.  This basically rolls things back to
ruby 1.8.

So how to deal with text in encodings, if not in the ruby 1.9 way?  Well,
simple operations like concatenation are just operations on bytes anyway. 
So this leaves only a small number of cases for which the language could
provide support.

### Multiple encodings ###

Some tiny minority of programs might be juggling Strings of different
encodings internally at the same time.  For each String you want to carry
state saying what encoding it is in.  Fine: then make a wrapper class which
carries a String and its Encoding.  Have it as a library you can require.

Most programs will either just work with one encoding throughout, or will
transcode at the edges.

### Substrings ###

e.g. truncate a string to the first 50 characters. This means having
operations like [] and slice which work on characters rather than bytes. 

I'd just add a new method:

    str.chars(0..50, "UTF-8")

In some cases you'll want to use the encoding from the environment, as sed
does:

    str.chars(0..50, "locale")

I observe that getting the n'th character of a String in a variable-width
encoding is inherently an expensive operation, and so it seems reasonable to
make this slightly more awkward than the [] syntax.  It flags to you that if
you have a lot of processing to do, maybe you should transcode the whole
string to a fixed-width encoding first.

### Regexps ###

Matching text against a regexp can be done by setting the encoding on the
regexp, not the text.  ruby 1.8 allowed this for a handful of encodings,
like `/.../u` for UTF-8.

The encoding can be given when building a regexp: e.g.
`Regexp.new("str", "encoding")`

and I'd also be fine with tagging the source file to set the default for all
the regexp literals inside it:

    # encoding: iso-8859-1
    ...
    str =~ /foo/       # Regexp.new("foo", "iso-8859-1")

I strongly believe that regexp matching should not raise an exception even
in the presence of invalid characters.  This is the same as sed, and indeed
the same as ruby 1.9's `String#[]` method.

By the way, something that I think ruby 1.8 got wrong was the ability to
set $KCODE from the command line, and to compile --with-default-kcode.

When Apple built ruby 1.8 for the Mac they set `--with-default-kcode=UTF8`,
and this simply means that programs written elsewhere may crash when
run on the Mac. For an example see http://www.ruby-forum.com/topic/216511

Tagging each source file for regexp encoding (1.9-style) makes more
sense.  But I'm proposing that this tagging applies only to regexp literals,
not to string literals as well.

### Transcoding ###

Iconv does this nicely, but I have no problem adding methods to String to
make this more convenient.

    str.encode!("UTF-8", "ISO-8859-1")    # encode to UTF-8 from ISO-8859-1

Having the ability to auto-transcode on input and output is of course
useful, and being able to use the environment locale if you ask for it. e.g.

    File.open("/etc/passwd","r:UTF-8:ISO-8859-1")
    File.open("/etc/passwd","r:UTF-8:locale")

Unlike ruby 1.9, the strings themselves would not be tagged.

### Nothing else? ###

If I think of anything else I'll add it here, but I think that's it. It
solves the problems I listed above, and it gives the tools for working with
text in various encodings whilst not breaking programs which work with
binary data.


Option 2: Band-aids
-------------------

Given that so much effort has been invested in tagging strings throughout
ruby 1.9, and the huge loss of face which would be involved in reversing
that decision, I don't expect this ever to happen.

So could we apply some tweaks to the current system to make it more
reasonable? Here are some options.

* Have a universally-compatible "BINARY" encoding. Any operation between
  BINARY and FOO gives encoding BINARY, and transcoding between BINARY and
  any other encoding is a null operation.

* Open all files in BINARY mode, except where explicitly asked:
  `File.open("/etc/passwd","r:locale")`

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

I've removed what I wrote here originally, because basically python 3.0 has
got it right, and you might as well read about it here:
http://docs.python.org/release/3.0.1/whatsnew/3.0.html#text-vs-data-instead-of-unicode-vs-8-bit

But in summary:

* There are two types of object: strings (unicode text) and bytes (data).
* The two are incompatible. For example, you cannot concatenate strings and
  bytes, and they always compare as different.
* A string is a sequence of unicode characters. There is no 'encoding'
  associated with it, because characters exist independently of their encoded
  representation.
* When you convert between text and data (i.e. the external representation
  of that text), then you specify what encoding to use. The default is
  picked up from LANG unless you override it, as in ruby 1.9.
* When you open a file, you open it in either text or binary mode (r/rb),
  and what you get when you read it is either strings or bytes respectively.

This to me is hugely sensible and logical. Some practical consequences are:

1. If there's a problem with your program, it will crash early and
*consistently* (e.g.  if you opened a file in binary mode and tried to treat
it as text, or vice versa).

Ruby may run OK if you feed it some data (e.g.  which happens to be
ASCII-only) but crash when you feed it something else.

2. Strings have no encoding dimension, so both program analysis and unit
testing are totally straightforward.

3. External libraries need only document whether they accept (and return)
strings or bytes.  If you make a wrong assumption, again your program will
crash early and you can immediately fix it.


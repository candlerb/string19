#!/usr/bin/env ruby19
# encoding: UTF-8
# This document is Copyright (C) Brian Candler 2009. All rights reserved.

############# CONTENTS ###################

# -1. PREAMBLE
#  0. INTRODUCTION
#  1. ENCODINGS
#  2. PROPERTIES OF ENCODINGS
#  3. STRING, FILE AND REGEXP ENCODINGS
#  4. VALID AND FIXED ENCODINGS
#  5. COMPATIBLE OBJECTS
#  6. STRING CONCATENATION
#  7. THE BINARY / ASCII-8BIT ENCODING
#  8. SINGLE CHARACTERS
#  9. EQUALITY AND COLLATION
# 10. HASH AND EQL?
# 11. UPPER AND LOWER CASE
# 12. REGULAR EXPRESSIONS
# 13. FROZEN STRINGS
# 14. OTHER METHODS ON STRING
# 15. OTHER METHODS WHICH TAKE STRING ARGUMENTS
# 16. OTHER METHODS WHICH RETURN STRINGS
# 17. LIBRARY METHODS
# 18. SOURCE ENCODING
# 19. STRING LITERALS
# 20. EXTERNAL AND INTERNAL ENCODING
 
############# -1. PREAMBLE ###############

# This file is runnable documentation. It runs for me under Ubuntu Lucid
# using ruby-1.9.2-p0 and ruby-1.9.1-p429 compiled from source, with my
# default en_GB.utf8 locale. I believe it will run on other systems, but it
# may not, given that Ruby's String behaviour is sensitive to the
# environment in which it is run.

# The following code is just for setting up the test cases.

require 'rbconfig'
RUBY=Config::CONFIG['ruby_install_name']
TMPFILE="test-ruby19"
require 'test/unit'
class TestString < Test::Unit::TestCase
  alias :is :assert_equal

  def test_string19

############# 0. INTRODUCTION ####################

# This article attempts to define, in a reasonable level of detail, the M17N
# properties in ruby 1.9 and how they affect the execution of a program.

# With ruby 1.8, if you weren't working with M17N then you could ignore it. 
# But with ruby 1.9, even if you are working with binary data like JPEGs or
# PDFs or ASN1 certificates, you need to understand how String has been
# changed, otherwise your program may fail depending on exactly how and
# where it is run.

# There is other documentation on this subject, most notably James Edward
# Gray II's series starting at
# http://blog.grayproductions.net/articles/ruby_19s_string
# but everything I read only raised more questions, so I wrote this
# document as I experimented with the behaviour.

# What I have written here has been determined by reverse-engineering, that
# is, trial-and-error testing and looking at the ruby 1.9 C source.  This is
# because there is no official documentation of the expected behaviour of
# String in the 1.9 world.  I believe that what I have written is true, and
# I've tried to provide runnable examples of each aspect of the behaviour,
# but I also know that it is far from complete.

############# 1. ENCODINGS #######################

# An "encoding" is a character set, and ruby 1.9 comes with a large set of
# predefined encodings with an instance of the Encoding class representing
# each one.  They are all constants under the Encoding namespace, and you
# can get a list of them all using Encoding.list

  is Encoding,
    Encoding::UTF_8.class

# Each Encoding also has a string name. You can get a list of all names
# using Encoding.name_list, and convert between string names and Encoding
# objects using Encoding.find and Encoding#to_s

  is Encoding::ASCII_8BIT,
    Encoding.find("ASCII-8BIT")
  
  is "ASCII-8BIT",
    Encoding::ASCII_8BIT.to_s

# An encoding may have more than one name, in which case only the primary
# one is returned by Encoding#to_s, but any of the names can be used in
# Encoding.find. All the names are returned by Encoding#names, with the
# primary one first. There is also an Encoding.aliases hash.

  is Encoding::ASCII_8BIT,
    Encoding.find("BINARY")
  
  is "ASCII-8BIT",
    Encoding::BINARY.to_s

  # NOTE: 1.9.2 gives me ["ASCII-8BIT", "BINARY"]
  # but 1.9.1 gives me ["ASCII-8BIT", "BINARY", "filesystem"]
  
  assert Encoding::ASCII_8BIT.names.include? "ASCII-8BIT"
  assert Encoding::ASCII_8BIT.names.include? "BINARY"

  is "ASCII-8BIT",
    Encoding.aliases["BINARY"]
  
  is nil,
    Encoding.aliases["ASCII-8BIT"]

# In general, all the methods which take an Encoding will also take
# a String which is the encoding name, meaning that you don't have to call
# Encoding.find yourself.

# The set of aliases for each encoding is not static, since there are
# special aliases like "external" and "locale" which are reassigned
# dynamically. e.g. in irb

#     >> Encoding::UTF_8.names
#     => ["UTF-8", "CP65001", "locale", "external"]
#     >> Encoding::ISO_8859_1.names
#     => ["ISO-8859-1", "ISO8859-1"]
#     >> Encoding.default_external = "ISO-8859-1"
#     => "ISO-8859-1"
#     >> Encoding::UTF_8.names
#     => ["UTF-8", "CP65001", "locale"]
#     >> Encoding.default_external = "ISO-8859-1"
#     => "ISO-8859-1"

# We will come back to this later.

# Encoding#names and Encoding.aliases are not frozen, so you can modify
# them to add additional aliases if you wish.

# The name of the character set for the system's "locale" is available in
# Encoding.locale_charmap. Note that this is a String, not an Encoding.

  is String,
    Encoding.locale_charmap.class   # e.g. "UTF-8"

# The choice of locale is made at runtime based on environment variables,
# see setlocale(3)

  res = %x{env LC_ALL=en_US.utf8 #{RUBY} -e "puts Encoding.locale_charmap"}.chomp
  is "UTF-8", res

# Quoting from the Encoding.locale_charmap documentation: "The result is
# highly platform dependent.  So Encoding.find(Encoding.locale_charmap) may
# cause an error.  If you need some encoding object even for unknown locale,
# Encoding.find("locale") can be used."

# On Linux systems, the 'C' locale maps to the ANSI_X3.4-1968 character set.

  res = %x{env LC_ALL=C #{RUBY} -e "puts Encoding.locale_charmap"}.chomp
  if res != "ANSI_X3.4-1968"
    STDERR.puts "WARNING: got #{res.inspect} as locale_charmap for LC_ALL=C"
  end

# On systems which have no locale support at all, the fallback is US-ASCII.
# This may be the case with Cygwin, or at least was in the past.

############# 2. PROPERTIES OF ENCODINGS ##########

# If an encoding includes single-byte ASCII characters in the range 00-7F,
# then it is said to be ASCII-compatible.
#
# Most encodings are in fact ASCII-compatible. An example of one which is not
# is Encoding::UTF_16BE (because all characters are two bytes)
#
# As far as I can see this property of the encoding isn't directly exposed to
# the Ruby programmer, but you can test for it indirectly like this:
#
#    Encoding.list.find_all { |e| 
#      !Encoding.compatible?("a".force_encoding(e), "a")
#    }
#
# There are also encodings which are tagged as 'dummy', which is a property
# you can test for using Encoding#dummy?

  is true,
    Encoding::ISO_2022_JP.dummy?

# According to a comment in the source, "A dummy encoding is an encoding for
# which character handling is not properly implemented.  It is used for
# stateful encodings." (That is, encodings with 'shift' sequences which
# means that the interpretation of a character depends on characters which
# have preceeded it)

# REFERENCE: macro rb_enc_asciicompat() in include/ruby/encoding.h

############# 3. STRING, FILE AND REGEXP PROPERTIES #################

# Strings, Regexps and File/IO objects have encoding properties. Two new
# properties have been introduced:
#
# 'encoding': this points to an Encoding object, and labels a string as
# being built from a particular character set.  This property can be set
# explicitly, and can also change automatically when you append characters
# to it.
#
# 'ascii_only?': this is a boolean property of the *content* of a String,
# and is set dynamically to represent whether the string contains *only* all
# bytes with the top bit set to zero (i.e.  values in the range 00-7F).
# Appending or removing characters from a string can change this property.
# It is false if the Encoding is not ASCII-compatible.

# 3.1 Strings
#
# Strings have both 'encoding' and 'ascii_only?' properties. I will go into
# detail later about how a string picks up its initial encoding, but for now
# notice that string literals in this file get UTF-8 because of the line
# "#encoding:UTF-8" at the top of this file.

  str = "hello"
  is Encoding::UTF_8,
    str.encoding
  is true,
    str.ascii_only?

  str = "groß"
  is Encoding::UTF_8,
    str.encoding
  is false,
    str.ascii_only?

# For ASCII-compatible encodings, the empty string has ascii_only? true

  str = ""
  is true,
    str.ascii_only?

# However for non-ASCII-compatible encodings, e.g. "wide" encodings where
# all characters are 2 or more bytes, ascii_only? is always false - even
# for the empty string, or for strings which consist only of characters in
# the 0000-007F range.

  str = "".force_encoding("UTF-16BE")
  is false,
    str.ascii_only?
  
  str = "A".encode!("UTF-16BE")
  is false,
    str.ascii_only?

# In ruby 1.9, the ascii_only? property is cached to avoid having to
# recompute it all the time.  This means that the interpreter must be very
# careful to clear this cache after any string change which might invalidate
# it, otherwise bad things happen (like String#hash or String#eql? giving
# the wrong results)

# The encoding of a string can be changed to any known encoding using
# 'force_encoding'. This does not change the content of the string at all,
# just its encoding tag. It always returns the same string, not a copy.

  str = "groß"
  is [103, 114, 111, 195, 159],
    str.bytes.to_a
  
  str.force_encoding("ISO8859-1")
  is Encoding::ISO8859_1,
    str.encoding
  is [103, 114, 111, 195, 159],
    str.bytes.to_a

# Encodings can be specified using their name in string form, or a
# predefined constant under the Encoding module.

  str = "hello"
  assert_nothing_raised {
    str.force_encoding "UTF-8"
    str.force_encoding Encoding::UTF_8
  }

# To transcode a string, use the 'encode' or 'encode!' methods. This gives a
# string with the characters re-encoded for the target character set. The
# former returns a new string, and the latter updates the source string.

  str = "groß"
  str.encode!("ISO8859-1")
  is Encoding::ISO8859_1,
    str.encoding
  is [103, 114, 111, 223],
    str.bytes.to_a

# Normally this will raise an error if the source string contains an
# invalid character, or a source character isn't available in the target
# character set

  str = "hello\xff"
  err = assert_raises(Encoding::InvalidByteSequenceError) {
    str.encode!("ISO8859-1")
  }

  str = "hello\u0100"
  err = assert_raises(Encoding::UndefinedConversionError) {
    str.encode!("ISO8859-1")
  }

# However there are options you can apply which will override this
# behaviour - see 'ri String#encode' and 'ri Encoding::Converter.new'
# for full details.
#
#     :invalid => :replace     # replace invalid src chars
#     :undef => :replace       # replace undef'd dst chars
#     :replace => "?"          # the replacement character
#     :xml => :text            # undef'd dst chars -> &#xHEX;
#     :xml => :attr            # also quotes the result and "->&quot;
# There are also three options for converting newlines, see ri.

  str = "hello\xff"
  str.encode!("ISO8859-1", :invalid => :replace)
  is "hello?", str

  str = "hello\u0100"
  str.encode!("ISO8859-1", :undef => :replace)
  is "hello?", str

  str = "hello\u0100"
  str.encode!("ISO8859-1", :xml => :text)
  is "hello&#x100;", str

  str = "hello\"\u0100"
  str.encode!("ISO8859-1", :xml => :attr)
  is '"hello&quot;&#x100;"', str

# If you specify both :xml=>:text and :undef=>:replace, :xml wins
# (why not :undef=>:xml instead?)

  str = "hello\u0100"
  str.encode!("ISO8859-1", :xml => :text, :undef => :replace)
  is "hello&#x100;", str

# REFERENCES: str_transcode() in transcode.c

# 3.2 Symbols
#
# Symbols have an 'encoding' but no 'ascii_only?' property. Rather, the
# encoding is forced to US-ASCII if the symbol contains only ASCII chars.

  sym = "gro".to_sym     # note that "gro" has encoding UTF-8
  is Encoding::US_ASCII,
    sym.encoding

  sym = :groß
  is Encoding::UTF_8,
    sym.encoding

  assert_raises(NoMethodError) {
    sym.ascii_only?
  }

# Symbols which consist of the same sequence of bytes but different
# encodings are distinct symbols (see under EQUALITY AND COLLATION)

# 3.3 Regular Expressions
#
# Regexps also have an 'encoding'. They do not have an 'ascii_only?'
# property, but they do have a related 'fixed_encoding?' property, which
# affects the matching compatibility rules (described later). Roughly
# speaking, a regexp with fixed_encoding? is intended to match strings only
# of the same encoding.
#
# The fixed_encoding? property is not visible when you convert the Regexp
# back to a string, unlike the //m, //i and //x flags.

  re = /gro/
  is [Encoding::US_ASCII, false, "/gro/", "(?-mix:gro)"],
    [re.encoding, re.fixed_encoding?, re.inspect, re.to_s]

  re = /groß/
  is [Encoding::UTF_8, true, "/groß/", "(?-mix:groß)"],
    [re.encoding, re.fixed_encoding?, re.inspect, re.to_s]

  # A UTF-8-only Regexp literal, even without UTF-8 characters
  re = /gro/u
  is [Encoding::UTF_8, true, "/gro/", "(?-mix:gro)"],
    [re.encoding, re.fixed_encoding?, re.inspect, re.to_s]

if RUBY_VERSION >= "1.9.2"
  # Another way to do this (1.9.2 only)
  re = Regexp.new("gro", Regexp::FIXEDENCODING)
  is [Encoding::UTF_8, true, "/gro/", "(?-mix:gro)"],
    [re.encoding, re.fixed_encoding?, re.inspect, re.to_s]
end

  assert_raises(NoMethodError) {
    /gro/.ascii_only?
  }

# 3.4 File and IO objects
#
# These have two properties, 'external_encoding' and 'internal_encoding',
# and a 'set_encoding' method. We'll look at these later.

  File.open(__FILE__, "r:UTF-8:ISO-8859-1") do |f|
    is Encoding::UTF_8,
      f.external_encoding
    is Encoding::ISO_8859_1,
      f.internal_encoding
  end

# REFERENCE: see enc_capable() in encoding.c which detects classes which
# have encoding capabilities.

############# 4. VALID ENCODINGS ##########################

# Since you can change the encoding tags arbitrarily, it's possible to have
# a String which is not a valid sequence of characters in the selected
# character set. You can test for this using the 'valid_encoding?' method.

  str = "hello\xdf".force_encoding("ISO-8859-1")
  is true,
    str.valid_encoding?
  str.force_encoding("UTF-8")
  is false,
    str.valid_encoding?

# Some operations which work on a character-by-character basis,
# such as Regexp matches, will fail if the String has an invalid
# encoding.

  str = "aß\xddf".force_encoding("UTF-8")

  err = assert_raises(ArgumentError) {
    str =~ /./
  }
  #is "invalid byte sequence in UTF-8",
  #  err.message

# Operations which treat the String as a sequence of bytes, such as
# writing it out to a file, will still succeed.

  str = "aß\xddf".force_encoding("UTF-8")

  assert_nothing_raised {
    File.open(TMPFILE,"wb") { |f| f.write str }
  }
  File.delete(TMPFILE)

# Symbols have neither 'force_encoding' nor 'valid_encoding?' methods

  assert_raises(NoMethodError) {
    :gro.force_encoding("UTF-8")
  }
  assert_raises(NoMethodError) {
    :gro.valid_encoding?
  }

# As of ruby 1.9.2, you cannot create a symbol with an invalid encoding.
#
# Prior to this you could create a symbol with an invalid encoding, but you
# could not #inspect it, so irb gave an error if you tried to display one:
#
#   >> "hello\xdf".to_sym
#   ArgumentError: invalid byte sequence in UTF-8
#           from /usr/local/lib/ruby/1.9.1/irb/inspector.rb:84:in `inspect'
#
# That appears to be a problem with the display, not the generation.
# That is: Symbol#inspect raises an exception for these symbols.

if RUBY_VERSION >= "1.9.2"

  assert_raises(EncodingError) {
    str = "hello\xdf".force_encoding("UTF-8")
    sym = str.to_sym
  }

else

  str = "hello\xdf".force_encoding("UTF-8")
  sym = str.to_sym
  is Encoding::UTF_8,
    sym.encoding
  is [104, 101, 108, 108, 111, 223],
    sym.to_s.bytes.to_a
  assert_raises(ArgumentError) {
    sym.inspect
  }

end

# Similarly, Regexps do not have 'force_encoding' or 'valid_encoding?'
# methods.

  assert_raises(NoMethodError) {
    /gro/.force_encoding("UTF-8")
  }
  assert_raises(NoMethodError) {
    /gro/.valid_encoding?
  }

# You cannot create a Regexp with invalid characters

  assert_raises(RegexpError) {  # note: not Encoding::InvalidByteSequenceError
    Regexp.new("hello\xdf")
  }

############# 5. COMPATIBLE OBJECTS #############

# When an operation occurs on two encoding-aware objects, it will only
# succeed if the objects have "compatible" encodings.  Furthermore, the
# encoding of the resultant value has to be chosen.
#
# Compatibility depends not only on the encoding tags of the objects, but
# also in the case of Strings on their contents.
#
# You can perform the test for compatibility, without actually performing
# an operation on the two objects, by using Encoding.compatible?(obj1,obj2).
# The return value is the encoding that the result would have, or nil if
# the objects are not compatible.
#
# Roughly speaking: two objects are compatible if they both have the same
# encoding, or either of them is empty or ascii_only.
#
# Here are the rules more accurately: they are invoked in this sequence,
# and the first matching rule wins.
#
# 1. Two objects are compatible if they have the same encoding; the resultant
#    object will have the same encoding. (Note that 'object' includes File
#    and Regexp here too, but I'm only testing using String)

  a = "groß"
  b = "über"
  is [Encoding::UTF_8, Encoding::UTF_8, Encoding::UTF_8],
    [a.encoding, b.encoding, Encoding.compatible?(a, b)]

# 2. Two objects are compatible if one of them is the empty string; the
#    resultant object has the encoding of the other one.

  a = "hello\xff"
  a.force_encoding "ISO-8859-1"
  b = ""
  is [Encoding::ISO_8859_1, Encoding::UTF_8, Encoding::ISO_8859_1],
    [a.encoding, b.encoding, Encoding.compatible?(a, b)]

  a = ""
  b = "hello\xff"
  b.force_encoding "ISO-8859-1"
  is [Encoding::UTF_8, Encoding::ISO_8859_1, Encoding::ISO_8859_1],
    [a.encoding, b.encoding, Encoding.compatible?(a, b)]

# This is true even if the empty string has a non-ASCII-compatible encoding

  a = "".force_encoding("UTF-16BE")
  b = "hello\xff"
  b.force_encoding "ISO-8859-1"
  is [Encoding::UTF_16BE, Encoding::ISO_8859_1, Encoding::ISO_8859_1],
    [a.encoding, b.encoding, Encoding.compatible?(a, b)]

# 3. The objects are not compatible if either uses a non-ASCII-compatible
#    encoding

  a = "aa".force_encoding "UTF-16BE"
  b = "bb"
  is [Encoding::UTF_16BE, Encoding::UTF_8, nil],
    [a.encoding, b.encoding, Encoding.compatible?(a, b)]

# 4. If one of the objects is not a String but has the encoding "US-ASCII"
#    then the objects are compatible, and the result has the encoding of
#    the other

  a = /a/
  b = "bß"
  is [Encoding::US_ASCII, Encoding::UTF_8, Encoding::UTF_8],
    [a.encoding, b.encoding, Encoding.compatible?(a, b)]

  a = "aß"
  b = /b/
  is [Encoding::UTF_8, Encoding::US_ASCII, Encoding::UTF_8],
    [a.encoding, b.encoding, Encoding.compatible?(a, b)]

# 5. If one object is a String which contains only 7-bit ASCII characters
#    (ascii_only?), and the other is an object with an ASCII-compatible
#    encoding, then the objects are compatible and the result has the
#    encoding of the other object.

  a = "hello"                               # ascii_only
  b = "\xff".force_encoding "ISO-8859-1"    # ascii_compat encoding
  is [Encoding::UTF_8, Encoding::ISO_8859_1, Encoding::ISO_8859_1],
    [a.encoding, b.encoding, Encoding.compatible?(a,b)]

  a = "groß"                                # ascii_compat encoding
  b = "world".force_encoding "ISO-8859-1"   # ascii_only
  is [Encoding::UTF_8, Encoding::ISO_8859_1, Encoding::UTF_8],
    [a.encoding, b.encoding, Encoding.compatible?(a,b)]

  a = "hello"                               # ascii_only
  b = "\xff\xff".force_encoding("UTF-16BE") # not ascii_compat
  is nil,
    Encoding.compatible?(a, b)

# If *both* are strings containing only 7-bit ASCII characters, then the
# result has the encoding of the first.

  a = "hello".force_encoding "ISO-8859-1"
  b = "world"
  is Encoding::ISO_8859_1,
    Encoding.compatible?(a,b)

# REFERENCE: rb_enc_compatible() in encoding.c

# Regexps with the fixed_encoding? flag are subject to a slightly stricter
# set of rules. In this case, a regexp which contains only ASCII characters
# is not compatible with a string with a different encoding if that other
# string contains non-ASCII characters.

  re = /gro/u
  
  str = "gro".force_encoding("ISO-8859-1")
  assert_nothing_raised {
    re =~ str
  }
  
  # but:
  str = "gro\xdf".force_encoding("ISO-8859-1")
  assert_raises(Encoding::CompatibilityError) {
    re =~ str
  }

############# 6. STRING CONCATENATION #############

# When you combine strings using << or +, the above compatibility rules
# are applied. Note that this means that even when you concatenate onto
# an existing string using <<, the encoding of that string may be
# silently changed.

  a = "hello"
  b = "hello\xdf".force_encoding("ISO-8859-1")
  is Encoding::UTF_8,
    a.encoding
  a << b
  is Encoding::ISO_8859_1,
    a.encoding

# If the strings are not compatible then an exception is raised:

  a = "hello\xdf".force_encoding("ISO-8859-1")
  b = "groß"
  assert_raises(Encoding::CompatibilityError) {
    a << b
  }

# This means that care is needed if combining Strings from unknown
# sources. If they are tagged with different encodings, then it might work
# (e.g. if one is empty, or one contains only ASCII characters);
# but at other times you may get an exception.

############# 7. THE BINARY / ASCII-8BIT ENCODING #############

# There is an encoding for binary data, called "ASCII-8BIT". You can also
# refer to this as "BINARY", but this is just an alias; if you ask such
# an object what its encoding is, you'll get "ASCII-8BIT" even if you
# specified it to be "BINARY".

  a = "abc"
  a.force_encoding "BINARY"
  is "ASCII-8BIT",
    a.encoding.to_s

# This encoding is ASCII-compatible. It is impossible to mark an object
# as "true binary" (not containing any ASCII text)
#
# Furthermore, this encoding gives you no special exemption from the
# compatibility rules. If you are appending things onto a "binary" string,
# and one of those happens to be tagged with a different character set and
# contain non-ASCII characters, then you will still get an exception.

  a = "\xde\xad\xbe\xef".force_encoding("BINARY")
  is Encoding::ASCII_8BIT,
    a.encoding
  
  b = "groß"
  
  assert_raises(Encoding::CompatibilityError) {
    a << b
  }

# So if you are trying to build a binary message out of Strings which may be
# tagged with an encoding other than ASCII-8BIT, you need to keep forcing
# encodings.

  a = "\xde\xad\xbe\xef".force_encoding("BINARY")
  b = "groß"
  b.force_encoding "ASCII-8BIT"
  assert_nothing_raised {
    a << b
  }

# Note that it *is* permissible to label a string containing bytes with
# the top bit set as US-ASCII, without raising any error.

  a = "\xde\xad\xbe\xef"
  assert_nothing_raised {
    a.force_encoding("US-ASCII")
  }
  is Encoding::US_ASCII,
    a.encoding

# This makes it somewhat unclear as to what the difference between ASCII-8BIT
# and US-ASCII is supposed to be.

############# 8. SINGLE CHARACTERS #######

# The String#[] method now uses character indexes, rather than byte indexes.
# When given a single integer index it returns a one-character string.

  a = "qłer"
  is "ł", a[1]

# Strangely, selecting individual characters from the string succeeds even
# if the string has an invalid encoding!

  str = "aß\xddf".force_encoding("UTF-8")
  assert_equal ["a", "ß", "\xdd", "f", false],
    [str[0], str[1], str[2], str[3], str.valid_encoding?]

# String#ord gives a codepoint of the first character in the string:

  a = "qłer"
  is 322, a[1].ord
  is 322, a[1..-1].ord

# Integer#chr without an argument gives a US-ASCII encoding for 0-127,
# an ASCII-8BIT encoding for 128-255, and an exception for higher values.

  a = 65.chr
  is "A".force_encoding("US-ASCII"), a
  
  a = 223.chr
  is "\xdf".force_encoding("ASCII-8BIT"), a

  assert_raises(RangeError) {
    322.chr
  }

# But Integer#chr can now take an encoding as an argument

  a = 322.chr("UTF-8")
  is "ł", a
  
# Note that Array#pack with C option silently truncates to 8 bits.

  is((322 & 0xff).chr,
    [322].pack("C"))

# However, String#% (or Kernel#sprintf) respects the encoding of the format
# string.

  is "abcł",
    "abc%c" % 322
  
############# 9. EQUALITY AND COLLATION ############

# How does encoding affect string equality and ordering when sorting?

# Strings are subject to a subset of compatibility rules defined above.
# Strings are equal if they are of the same length and have the same
# byte content, and are "comparable". Strings are comparable if either
# of them is empty; or they have the same encoding; or they have different
# encodings but both are ascii-compatible encodings and both strings are
# only using 7-bit characters.

  a = "hello"
  b = "hello".force_encoding("ISO-8859-1")
  is true,
    a == b
    
  a = "groß"
  b = "groß".force_encoding("ISO-8859-1")
  is false,
    a == b

# If the RHS is not a string, but responds to :to_str, then == is called
# on the RHS with the LHS as an argument, and the result converted to
# either true or false. Note that to_str is not called!

  a = "hello"
  b = Object.new
  def b.to_str
    raise "Not called"
  end
  def b.==(other)
    :dummy_true_value
  end
  is true,
    a == b

# REFERENCE: rb_str_equal, str_eql, rb_str_comparable in string.c

# Collation is done by means of the spaceship operator (<=>).

# If the strings are different sequences of bytes then a simple bytewise
# comparison is used, regardless of encoding. Note that it does *not* use
# the Unicode Collation Algorithm (UCA).

  a = "hello"
  b = "hellO"
  is 1,
    a <=> b     # but in UCA, hello comes before hellO

# If one string is prefix of the other then the longer string wins.
# If the strings are bytewise equal and the encodings are equal, it returns 0.
# If the strings are bytewise equal and are comparable, it returns 0.

  a = "hello"
  b = "hello".force_encoding("ISO-8859-1")
  is 0,
    a <=> b
    
# If the strings are bytewise equal but not comparable, it returns -1 or 1
# dependent on an internal ordering of encodings.

  a = "groß"
  b = "groß".force_encoding("ISO-8859-1")
  is -1,
    a <=> b
  is 1,
    b <=> a

# If the RHS is not a string, but responds to :to_str and :<=>, then the
# spaceship operator of the RHS object is used, and the result negated. 
# (That is, effectively the arguments are swapped).  Note: the existence of
# :to_str is checked but it is not called.

  a = "hello"
  b = Object.new
  def b.<=>(x)
    99
  end
  def b.to_str
    raise "Not called"
  end
  is -99,
    a <=> b

# Otherwise if the RHS is not a string, nil is returned (no exception raised)

  a = "hello"
  b = Object.new
  is nil,
    a <=> b

# REFERENCE: rb_str_cmp_m in string.c

# It's important to realise that ruby 1.9 does not sort by codepoints, it
# sorts by bytes.  It's a convenient property of UTF-8 encoding that lower
# codepoints sort before higher ones, but this does not work for all
# encodings, not even all encodings of unicode.  Here's an example of where
# the distinction is important:

  s1 = 97.chr("UTF-8")		# a
  s2 = 257.chr("UTF-8")		# ā
  is true, s1 < s2		# expected
  
  s1 = 97.chr("UTF-16LE")	# a
  s2 = 257.chr("UTF-16LE")	# ā
  is false, s1 < s2		# not ordered by codepoint

# In ruby 1.9 these questions have to be considered for symbols too, since
# symbols now have string-like properties. As far as I can see, the same
# rules are applied to symbols as for strings. In particular, this means
# that symbols which have the same sequence of bytes but different encodings
# are different symbols

  s1 = "groß".force_encoding("UTF-8").to_sym
  s2 = "groß".force_encoding("ISO-8859-1").to_sym

  is false,
    s1.object_id == s2.object_id

  is false,
    s1 == s2

  is -1,
    s1 <=> s2

# Symbols cannot usefully be compared directly to Strings though.

  is nil,
    :foo <=> "foo"
  
  is false,
    :foo == "foo"

# Symbols have a to_s but not to_str method.

  assert_raises(NoMethodError) {
    :foo.to_str
  }

# Regular expressions can be tested for equality, and differ if they have
# differing encodings...

  a1 = "groß".force_encoding("UTF-8")
  a2 = "groß".force_encoding("ISO-8859-1")
  is true,
    Regexp.new(a1) == Regexp.new(a1)
  is false,
    Regexp.new(a1) == Regexp.new(a2)

# ... but they do not collate. Prior to 1.9.2, Regexp#<=> did not exist.
# In 1.9.2, Regexp#<=> returns 0 for equal regexps and nil otherwise.
# Object#<=> exists in 1.9.2 too.

if RUBY_VERSION >= "1.9.2"

  is 0, Regexp.new("foo") <=> Regexp.new("foo")
  is nil, Regexp.new("foo") <=> Regexp.new("bar")
  is nil, Object.new <=> Object.new

else

  assert_raises(NoMethodError) {
    Regexp.new("foo") <=> Regexp.new("foo")
  }

end

############# 10. HASH AND EQL? ############

# When Strings are used as Hash keys, the #hash and #eql? methods
# are used to determine whether Strings are the same. The rules
# for handling encodings are:
#
# - #hash includes the encoding in the hash calculation only if the
#   string is not ascii_only?
# - #eql? returns false if the strings are not comparable (i.e. have
#   different encodings and either is not ascii_only?)

  s1 = "hello"
  s2 = "hello".force_encoding("ISO-8859-1")
  is true,
    s1.hash == s2.hash
  is true,
    s1.eql?(s2)

  s1 = "groß"
  s2 = "groß".force_encoding("ISO-8859-1")
  is false,
    s1.hash == s2.hash
  is false,
    s1.eql?(s2)

# REFERENCES: rb_str_eq, rb_eql, rb_str_hash in string.c

############# 11. UPPER AND LOWER CASE #############

# There are five cases I can see where Ruby needs to distinguish and/or
# convert between 'lower case' and 'upper case' characters.

# 11.1 Regular expression character classes

# These are handled by the Oniguruma regexp library. Each encoding has
# its own rules for which characters are upper case, lower case, or
# neither. As far as I can see these are fixed per encoding - there is
# no variation per language or locale.

  s = "übÊr"
  is 0,
    s =~ /[[:lower:]]/
  is 2,
    s =~ /[[:upper:]]/

# 11.2 Source parsing (distinguishing local variables from constants)

# The set of characters allowed in identifiers is defined by
# rb_enc_isalnum() plus underscore. "isalnum" is delegated to Oniguruma,
# and is also defined per character set.

  is [1, 2],
     eval(<<EOS)
# encoding: UTF-8
SCHÖN = 1    # constant
schloß = 2   # variable
[self.class.const_get(:SCHÖN), schloß]
EOS

# The code delegates the isupper test to Oniguruma too, which means that
# you'd think that a constant could start with a non-ASCII upper-case
# character, but in fact it overrides this later.  Anything which starts
# with a non-ASCII uppercase character is treated as a local variable.

  is [:ÜBER], eval(<<EOS)
#encoding: UTF-8
ÜBER = 1
local_variables.grep(/BER/)
EOS

# This is apparently intentional behaviour. For a discussion see
# http://redmine.ruby-lang.org/issues/show/1853 and links from there.

# 11.3 String methods upcase!, downcase!, capitalize! and swapcase!

# Unexpectedly, the string case conversion functions do *NOT* implement the
# Unicode case conversion rules - rather, they only apply to ASCII
# characters 'a' to 'z' and 'A' to 'Z'.  All characters outside this range
# are left unchanged.  This is clearly intentional from the source code. 
# However they do work on ASCII characters in wide encodings like UTF16

  s = "über"
  is "üBER",    # NOT "ÜBER"
    s.upcase

  s = "über".encode!("UTF-16BE")
  is "\x00\xfc\x00B\x00E\x00R".force_encoding("UTF-16BE"),
    s.upcase    # \xfc = 252 = "ü".ord

# 11.4 String#casecmp

# casecmp uses the macro TOUPPER which in turn calls rb_toupper which
# only works for ASCII characters. So upper and lower-case extended
# characters are treated as different.

  is 0,
    "u".casecmp("U")
  is 1,
    "ü".casecmp("Ü")   # 252 vs 220

# REFERENCES:
# - rb_enc_islower() etc in include/ruby/encoding.h
# - rb_enc_tolower() etc in encoding.c
# - these macros ultimately expand to to enc->is_code_ctype()

# 11.5 String#succ

# The documentation says that "incrementing a letter results in another
# letter of the same case.  Incrementing nonalphanumerics uses the
# underlying character set's collating sequence."

# Therefore it needs to distinguish alphanumeric from non-alphanumeric,
# and also upper case from lower case. As far as I can tell, it only
# treats ASCII letters as alphanumeric.

  s = "abc" + 255.chr("UTF-8")
  s.succ!
  is "abc" + 256.chr("UTF-8"),
    s

# Note that 255.chr("UTF-8") is in Unicode terms both alphanumeric
# [[:alnum:]] and upper case [[:upper:]], but 256.chr("UTF-8") is
# alphanumeric and lower case.

############# 12. REGULAR EXPRESSIONS ############

# Regular expression matches are now done on a character-by-character
# basis, rather than byte-by-byte.

  s = "über"
  is 0,
    s =~ /\A.b/

# An exception is raised if the regexp and string are not compatible

  s = "groß"
  r = Regexp.new("...\xff".force_encoding("ISO-8859-1"))
  assert_raises(Encoding::CompatibilityError) {
    s =~ r
  }
  assert_raises(Encoding::CompatibilityError) {
    r =~ s
  }

# or if the source string contains invalid characters, even if they
# are not reached

  s = "hello\xff"
  r = /h/
  assert_raises(ArgumentError) {  # not Encoding::InvalidByteSequenceError
    r =~ s
  }

# TODO: check behaviour of gsub and sub, match, regexp in #[] and scan

############# 13. FROZEN STRINGS #############

# If a string is frozen, you cannot call force_encoding on it (even to
# the same encoding as it already has)

  s = "hello"
  s.freeze
  assert_raises(RuntimeError) {
    s.force_encoding("UTF-8")
  }

# In 1.9.2-preview1 you *could* change the encoding using "encode!"
# This was a bug and has now been fixed.
# http://redmine.ruby-lang.org/issues/show/1836
#
# According to this ticket and 1550, the intention is that any potentially
# modifying operation on a frozen string should raise an exception.  I have
# not attempted to verify this across all methods.

############# 14. OTHER METHODS ON STRING #############

# We now need to document each method on String whose behaviour depends on
# the encoding of the String, or may change the encoding of the String.

# In general, String methods now work on characters rather than bytes: e.g. 
# [], []=, size/length, center, chars/each_char/codepoints, chop, ljust,
# lstrip, reverse, rjust, squeeze, strip etc (and their bang counterparts)
#
# The encoding value is used to help these methods delimit what constitutes
# a "character".  I will I will not make test cases for all these here, as
# it should be obvious how they are intended to work.  Test cases are useful
# for revealing implementation bugs of course, but that's not the purpose of
# this document.

# Rather, I will document the behaviour where it is not necessarily obvious.

# String#clear leaves the encoding unchanged:

  s = "\xfcber".force_encoding("ISO-8859-1")
  s.clear
  is Encoding::ISO_8859_1,
    s.encoding

# but String#replace changes the encoding to match the String being copied.

  s = "\xfcber".force_encoding("ISO-8859-1")
  s.replace("hello")
  is Encoding::UTF_8,
    s.encoding

# String#unpack ignores the encoding

  assert_nothing_raised {
    "\xff\xff\xff\xff".force_encoding("UTF-8").unpack("N")
    "\xff\xff\xff\xff".force_encoding("ISO-8859-1").unpack("N")
  }

# Methods which return a new string or strings generally return them with
# the same encoding as the original string.
#
# But String#crypt returns an ASCII-8BIT encoding always:

  s = "abc".crypt("aa")
  is Encoding::ASCII_8BIT,
    s.encoding

# Then there are methods which take additional String arguments, as those
# arguments may have a different encoding to the String they are operating
# on.  Generally these raise an exception if the additional argument(s) are
# not compatible with the original string.

# e.g. String#[] #[]= #insert #slice!

  s = "\xfcber".force_encoding("ISO-8859-1")
  assert_raises(Encoding::CompatibilityError) {
    s["\xfc"]    # UTF-8 argument due to source encoding
  }

# Ditto count, delete, end_with?, include?, start_with?, index, rindex
# Ditto the % operator with %s and %c format specifiers.

# The following behaviour is bizarre, and I suspect unintentional,
# so I have commented it out: see http://www.ruby-forum.com/topic/214297
#  
#   s = "%c%c%c%c%c".force_encoding("US-ASCII")
#   t = s % [49, 5, 245, 225, 1]
#   is Encoding::US_ASCII, t.encoding

# String#tr and tr_s take two String arguments. Both must be compatible
# with the source string.

  s = "\xfcber".force_encoding("ISO-8859-1")
  assert_raises(Encoding::CompatibilityError) {
    s.tr("\xfc","u")
  }
  assert_raises(Encoding::CompatibilityError) {
    s.tr("u","\xfc")
  }

# There are some methods which do work on bytes explicitly and hence do
# not depend on the encoding. These include String#bytesize,
# String#bytes/each_byte, String#getbyte/setbyte. e.g.

  s = "groß"
  is 5, s.bytesize
  is [103, 114, 111, 195, 159],
    s.to_enum(:each_byte).collect { |b| b }

# String#to_i has traditionally been tolerant of malformed numbers,
# and it remains so for invalid encodings too.

  is 0,
    "\xfcber".to_i

############# 15. OTHER METHODS WHICH TAKE STRING ARGUMENTS #############

# There are a large number of methods in classes other than String which
# take String arguments. I will only touch on a few here.

# If Array#pack is packing numbers in binary format, it will set
# ASCII-8BIT as the encoding.

  is Encoding::ASCII_8BIT,
    [0x41414141].pack("N").encoding

# When packing Strings, you will get ASCII-8BIT as well. It doesn't
# matter if the encodings are not compatible.

  s1 = "hello"
  s2 = "groß"
  s3 = "\xfcber".force_encoding("ISO-8859-1")
  is Encoding::ASCII_8BIT,
    [s1].pack("A*").encoding
  is Encoding::ASCII_8BIT,
    [s1,s2].pack("A*A*").encoding
  is Encoding::ASCII_8BIT,
    [s1,s2,s3].pack("A*A*A*").encoding

# TODO: expand this section. For example, does File.open ignore
# encodings in its filename and mode arguments?

############# 16. OTHER METHODS WHICH RETURN STRINGS #############

# There are a large number of methods in classes other than String which
# return String values. I will only touch a few here.

# Numeric#to_s returns a string with encoding US-ASCII

  is Encoding::US_ASCII,
    123.to_s.encoding

# TODO: expand this section. For example, the strings returned by Dir.[]
# appear to get their encoding from the environment.

############# 17. LIBRARY METHODS #############

# The documentation should be extended to consider every method in a
# library which takes a string, or which returns a string. This is a
# huge task, both for Ruby's supplied libraries and for third-party
# libraries.

# Sometimes the expected behaviour is "obvious":

  require 'scanf'
  s = "x\xfc".force_encoding("ISO-8859-1")
  s1, s2 = s.scanf("%c%c")
  is [Encoding::ISO_8859_1, Encoding::ISO_8859_1],
    [s1.encoding, s2.encoding]

# (Strangely, the documentation for scanf says that under Windows you should
# open files in binary mode "so that scanf can keep track of characters
# correctly")

# But there are many cases when it is not. Consider for example Net::HTTP.
# The web server can supply a Content-Type: header which specifies the
# charset, or the document itself can specify its character set using an XML
# declaration or a HTML META tag.  What encoding does the returned web page
# body have, and does it respect any of these sources?
#
# The only way to be sure is to test it, and/or to examine the source code.
#
# As will be discussed later, the default encoding for data read from a
# Socket is ASCII-8BIT.  So unless Net::HTTP takes special measures to
# interpret the out-of-band encoding information, you can guess that this is
# what you will get.
#
# Unfortunately this means that today you might get ASCII-8BIT, but at some
# point in the future if Net::HTTP is updated you might get a different
# body encoding (since it is not documented that Net::HTTP will return an
# ASCII-8BIT body)

############# 18. SOURCE ENCODING ##############

# When the ruby source is read and executed, it has a "source encoding"
# which is used when deciding what encoding to give to literals within
# that source. The source encoding depends on where the source was read
# from and on special comments included within it.

# 18.1 Source in a file
#
# Unless declared otherwise, the source encoding for ruby source read from a
# file is US-ASCII.  This is a sane default because it *doesn't* depend on
# what is in the environment.  It can be set to something else using a
# special comment in the first line of the file (or the second line, if the
# first is a #!  shebang line)

  is "US-ASCII", execute_in_file(<<EOS)
puts "".encoding
EOS

  is "ISO-8859-1", execute_in_file(<<EOS)
#encoding: ISO-8859-1
puts "".encoding
EOS

  is "ISO-8859-1", execute_in_file(<<EOS)
#!/usr/bin/ruby -w
#encoding: ISO-8859-1
puts "".encoding
EOS

  is "US-ASCII", execute_in_file(<<EOS)

#encoding: ISO-8859-1
#this is ignored if there is any non-shebang line before it
puts "".encoding
EOS

# Furthermore, if the source file has no encoding declared (or is declared
# US-ASCII), but contains any character with the high bit set, it will fail
# to parse at all. Such characters are not valid US-ASCII, and Ruby refuses
# to guess what encoding they might be.

  assert_match /invalid multibyte char/,  # SyntaxError
    execute_in_file(<<'EOS')
puts "groß".encoding
EOS

  assert_match /invalid multibyte char/,  # SyntaxError
    execute_in_file(<<'EOS')
#encoding: US-ASCII
puts "groß".encoding
EOS

# Similarly, if the source includes characters which are not valid in the
# source encoding, it will fail.

  res = execute_in_file("#encoding:UTF-8\n\"\xfcber\"\n")
  # need to sanitise the result otherwise we can't regexp-match it!
  res.force_encoding("ASCII-8BIT")
  assert_match /invalid multibyte char/, res

# As a special case, Strings created with String.new with no argument
# always get ASCII-8BIT encoding. Remember that this file is UTF-8 source:

  is Encoding::ASCII_8BIT,
    String.new.encoding
  is Encoding::UTF_8,
    String.new("").encoding

  is "ASCII-8BIT", execute_in_file(<<EOS)  # although source enc is US-ASCII
puts String.new.encoding
EOS

# 18.2 Source read from stdin
#
# Source read from stdin defaults to the locale encoding. But it can also be
# overridden using a #encoding line

  is "UTF-8",
    %x{ echo "puts ''.encoding" | env LC_ALL=en_US.utf8 #{RUBY} }.chomp
  is "ASCII-8BIT",
    %x{ echo '#encoding:ASCII-8BIT\nputs "".encoding' | env LC_ALL=en_US.utf8 #{RUBY} }.chomp

# 18.3 Source on the command line
#
# This also defaults to the locale encoding, and can also be overridden
# using a #encoding line

  is "UTF-8",
    %x{ env LC_ALL=en_US.utf8 #{RUBY} -e 'puts "".encoding' }.chomp
  is "ISO-8859-1",
    %x{ env LC_ALL=en_US.utf8 #{RUBY} -e '#encoding:ISO-8859-1' -e 'puts "".encoding' }.chomp
    
# 18.4 Source in eval
#
# This is more interesting. The source encoding is the encoding of the
# source string itself, again unless overridden using #encoding.

  is Encoding::UTF_8,   # note the #encoding:UTF-8 at the top of this doc
    eval(<<EOS)
"".encoding
EOS

  is Encoding::ISO_8859_1,
    eval(<<EOS.force_encoding("ISO-8859-1"))
"".encoding
EOS

  is Encoding::ASCII_8BIT,
    eval(<<EOS.force_encoding("ISO-8859-1"))
#encoding: ASCII-8BIT
"".encoding
EOS

# Again, if the string is tagged US-ASCII but contains high-bit characters,
# the whole string fails to parse.

  assert_raises(SyntaxError) {
    eval(<<EOS.force_encoding("US-ASCII"))
"groß"
EOS
  }

# 18.5 Source in irb
#
# Since irb uses eval, the source encoding is taken from the environment.
# As a result, irb is no longer a good predictor of how a program will
# behave when run standalone. For example, try this in irb:
#
#     >> puts "hello\xff".encoding
#     UTF-8
#
# If you run this in a standalone program, you will get a different result
# unless the source-encoding is also set to UTF-8.

  is "ASCII-8BIT",
    execute_in_file(<<'EOS')
puts "hello\xff".encoding
EOS

############# 19. STRING LITERALS ##############

# Now let's look how the encoding of a string literal is chosen. It
# depends both on its content and the source encoding of the file which
# contains it.

# 19.1 Simple string literals
#
# For a string literal which doesn't contain special escape sequences, its
# encoding is copied from the source encoding of the file where it appears.
# Note that this file has #encoding:UTF-8 at the top.

  is Encoding::UTF_8,
    "".encoding
  is Encoding::UTF_8,
    "hello".encoding

# The presence of \x escapes doesn't override UTF-8, even if that creates
# an string with an invalid encoding.

  is Encoding::UTF_8,
    "hell\xff".encoding

# However, there are a lot of additional rules. Firstly, if the source file
# is US-ASCII, then the presence of a \x byte in the range 80-FF (only)
# forces the string's encoding to be ASCII-8BIT

  source = '"hello"'
  str = eval(source.force_encoding("US-ASCII"))
  is Encoding::US_ASCII,
    str.encoding

  source = '"hell\\x6f"'
  str = eval(source.force_encoding("US-ASCII"))
  is Encoding::US_ASCII,
    str.encoding

  source = '"hell\\xff"'
  str = eval(source.force_encoding("US-ASCII"))
  is Encoding::ASCII_8BIT,
    str.encoding

# The presence of a \u (unicode) escape forces the encoding to be UTF-8,
# but only for unicode characters above hex 0080 (i.e. multibyte UTF-8)

  source = '"hell\\u006f"'
  str = eval(source.force_encoding("US-ASCII"))
  is Encoding::US_ASCII,
    str.encoding

  source = '"hell\\u00ff"'
  str = eval(source.force_encoding("US-ASCII"))
  is Encoding::UTF_8,
    str.encoding

# Mixing both \x and \u in US-ASCII source is an error

  source = '"hell\\xff\\u00ff"'
  e = assert_raises(SyntaxError) {
    str = eval(source.force_encoding("US-ASCII"))
  }
  assert_match /UTF-8 mixed within US-ASCII source/, e.message

# Ditto in ASCII-8BIT source

  source = '"hell\\xff\\u00ff"'
  e = assert_raises(SyntaxError) {
    str = eval(source.force_encoding("ASCII-8BIT"))
  }
  assert_match /UTF-8 mixed within ASCII-8BIT source/, e.message

# But mixing them in UTF-8 source is OK

  is Encoding::UTF_8,
    "hell\xff\u00ff".encoding

# The same rules as ASCII-8BIT apply to 8 bit encodings like ISO-8859-1

  source = '"hello"'
  str = eval(source.force_encoding("ISO-8859-1"))
  is Encoding::ISO_8859_1,
    str.encoding

  source = '"hell\\xff"'
  str = eval(source.force_encoding("ISO-8859-1"))
  is Encoding::ISO_8859_1,
    str.encoding

  source = '"hell\\u006f"'
  str = eval(source.force_encoding("ISO-8859-1"))
  is Encoding::ISO_8859_1,
    str.encoding

  source = '"hell\\u00ff"'
  str = eval(source.force_encoding("ISO-8859-1"))
  is Encoding::UTF_8,
    str.encoding

  source = '"hell\\xff\\u00ff"'
  e = assert_raises(SyntaxError) {
    str = eval(source.force_encoding("ISO-8859-1"))
  }
  assert_match /UTF-8 mixed within ISO-8859-1 source/, e.message

# 19.2 String literals containing interpolation

# Interpolating a string into another string uses the encoding compatibility
# rules discussed easlier, and therefore depends both on the encoding *and*
# the ascii_only?  properties of both the target string and the string into
# which it is being inserted (which starts off as the source encoding).  If
# the inserted string has high-bit chars set, then its encoding overrides
# the encoding which the resulting string would normally have.

  str1 = "world".force_encoding("ISO-8859-1")   # no high-bit chars
  str = "hello #{str1}"
  assert_equal Encoding::UTF_8,
    str.encoding

  str1 = "world\xff".force_encoding("ISO-8859-1")  # has high-bit char
  str = "hello #{str1}"
  assert_equal Encoding::ISO_8859_1,
    str.encoding

# And as before, if the encodings are not compatible, an exception is
# raised.

  str1 = "world\xff".force_encoding("ISO-8859-1")
  e = assert_raises(Encoding::CompatibilityError) {
    str = "hello \u00ff #{str1}"
  }
  #assert_match /incompatible character encodings/, e.message

# A similar crash will occur if the implicitly assigned source-encoding
# isn't compatible with the interpolated string:

  assert_match /incompatible character encodings/,
    execute_in_file(<<EOS)
# encoding: ISO-8859-1
str1 = "world\\xff".force_encoding("ISO-8859-15")
str = "hello\\xff \#{str1}"
EOS

  assert_match /incompatible character encodings/,
    execute_in_file(<<EOS)
# encoding: ISO-8859-1
str1 = "world\\xff".force_encoding("ASCII-8BIT")
str = "hello\\xff \#{str1}"
EOS

# A similar error occurs where multiple strings are being interpolated,
# and although they are both compatible with the target string, they
# are not compatible with each other.

  str1 = "world\xff".force_encoding("ISO-8859-1")
  str2 = "world\xff".force_encoding("ASCII-8BIT")
  e = assert_raises(Encoding::CompatibilityError) {
    str = "hello #{str1} #{str2}"
  }
  assert_match /incompatible character encodings/, e.message

# 19.3 Character literals

# Character literals ?X now return a one-character string, and the encoding
# is the source encoding.

  is "a", ?a
  is "ß", ?ß

############# 20. EXTERNAL AND INTERNAL ENCODING #####

# The concepts of external_encoding and internal_encoding have been
# documented pretty well elsewhere, but I will summarise them here.

# Open File and IO objects have two special encoding-related properties:
# external_encoding and internal_encoding
#
# external_encoding is the encoding which strings get when read from the
# file, if they are read line or character at a time. You can specify
# the external encoding at the time the file is opened.

  write_file("\xfcber") do |fn|
    File.open(fn, "r:ISO-8859-1") do |f|
      is [Encoding::ISO_8859_1, nil],
        [f.external_encoding, f.internal_encoding]
      is "\xfcber".force_encoding("ISO-8859-1"),
        f.gets
      f.rewind
      is "\xfc".force_encoding("ISO-8859-1"),
        f.getc
    end
  end

# However, if you read bytes using read(), you always get ASCII_8BIT

  write_file("abc") do |fn|
    File.open(fn, "r:ISO-8859-1") do |f|
      s = f.read(3)
      is Encoding::ASCII_8BIT,
        s.encoding
    end
  end

# If the file is opened in binary mode (rb), you always get ASCII_8BIT.
# This also disables newline conversions on Windows machines.

  write_file("abc") do |fn|
    File.open(fn, "rb") do |f|
      s = f.gets
      is Encoding::ASCII_8BIT,
        s.encoding
    end
  end

# Pipes are the same

  IO.popen("echo abc", "r:ISO-8859-1") do |f|
    s = f.gets
    is Encoding::ISO_8859_1,
      s.encoding
  end

# IO#pos and IO#pos= are byte offsets, not character offsets. getc and gets
# do *not* raise an exception if it is positioned part-way through a
# multibyte character, but just return an invalid character or string.

  write_file("über\n") do |fn|
    File.open(fn, "r:UTF-8") do |f|
      f.getc
      is 2, f.pos
      f.pos = 1
      is "\xbc", f.getc
      f.pos = 1
      is "\xbcber\n", f.gets
    end
  end

# The method 'set_encoding' can be used to change the encoding of an
# open File or IO stream, affecting subsequent IO operations

  write_file("\xfcber\n\xfcber\n") do |fn|
    File.open(fn, "r:ISO-8859-1") do |f|
      s = f.gets
      is "\xfcber\n".force_encoding("ISO-8859-1"), s
      f.set_encoding("UTF-8", nil)   # external, [internal]
      s = f.gets
      is "\xfcber\n", s
    end
  end

#### OPENING FOR READ ####

# If you do not specify the external encoding when the file is opened, then
# it is taken from Encoding.default_external, which is initialised based on
# Encoding.locale_charmap.  That is, the encoding that strings get when read
# from a file is determined at run-time based on the environment.  This is a
# bit awkward to demonstrate unless you have some interesting locales
# installed - here I will choose UTF-8 from the environment, but the source
# encoding is ISO-8859-1.

  res = %x{ echo "abc" | env LC_ALL=en_US.utf8 #{RUBY} -e "#encoding:ISO-8859-1" -e "puts ''.encoding; puts STDIN.gets.encoding"}.chomp
  is "ISO-8859-1\nUTF-8", res

# There is an accessor, Encoding.default_external=, which can be used
# to reset the default external encoding. This also updates the encoding
# alias "external".
# 
#     >> Encoding.default_external = "ISO-8859-1"
#     => "ISO-8859-1"
#     >> Encoding.find("external")
#     => #<Encoding:ISO-8859-1>

# The other property is internal encoding, and if not specified it is
# copied from Encoding.default_internal, which defaults to nil.
# If it is set, then the input stream is transcoded from the external
# encoding to the internal encoding automatically, for gets and getc,
# but not for read.

  write_file("\xfcber\n") do |fn|
    File.open(fn, "r:ISO-8859-1:UTF-8") do |f|
      is Encoding::UTF_8,
        f.internal_encoding
      is "über\n", f.gets
      f.rewind
      is "\xfcber".force_encoding("ASCII-8BIT"), f.read(4)
    end
  end

#### OPENING FOR WRITE ####

# Writing to a file is different. Firstly, if you don't specify an external
# encoding when opening the file, then the external_encoding property is
# nil, and no transcoding is done on output.

  begin
    str = 'помоник'
    str.force_encoding("ISO-8859-1")
    File.open(TMPFILE, "w") do |f|
      is [nil, nil],
        [f.external_encoding, f.internal_encoding]
      f << str
    end
    # Demonstrate that str is NOT transcoded from ISO-8859-1 to UTF-8
    File.open(TMPFILE, "rb") do |f|
      is str.force_encoding("ASCII-8BIT"),
        f.read
    end
  ensure
    File.delete(TMPFILE)
  end

# ----- ASIDE -----
# Let me say this again: the external encoding for write is NOT
# automatically set to the encoding from the locale/environment. This leads
# to some unexpected behaviour in irb, e.g.
#
#    >> str = 'помоник'
#    => "помоник"
#    >> str.force_encoding("ISO-8859-1")
#    => "помоник"
#
# You would expect to see garbage here, but it appears that the bytes
# contained in str are squirted directly to the (UTF-8) console, and so
# they are displayed as UTF-8. If you want the ISO-8859-1 characters to
# be transcoded to UTF-8, you have to ask for it explicitly:
#
#    >> str.encode("UTF-8")
#    => "Ð¿Ð¾Ð¼Ð¾Ð½Ð¸Ðº"
#
# Or you can request transcoding to take place on STDOUT:
#
#    >> STDOUT.set_encoding "locale"
#    => #<IO:<STDOUT>>
#    >> str
#    => "Ð¿Ð¾Ð¼Ð¾Ð½Ð¸Ðº"
#
# There is some more irb strangeness depending on the string content:
#
#    >> str = "über"
#    => "über"
#    >> str.force_encoding("ISO-8859-1")
#    => "über"
#    >> str = "groß"
#    => "groß"
#    >> str.force_encoding("ISO-8859-1")
#    => "gro�\x9F"
#    >> puts str
#    groß
#    => nil
#
# I believe this is just an artefact of String#inspect, which "knows" that
# \x80 to \x9f are not printable ISO-8859-1 chars and converts them to
# hex representation, thus breaking the UTF-8 display.
# ----- END ASIDE -----

# If you have specified the external encoding then transcoding takes place
# from the encoding of whatever String you are writing, to the external
# encoding of the file. As far as I can tell, the internal encoding is
# ignored in this case.

  begin
    File.open(TMPFILE, "w:ISO-8859-1") do |f|
      is [Encoding::ISO_8859_1, nil],
        [f.external_encoding, f.internal_encoding]
      f.puts "über"
    end
    File.open(TMPFILE, "rb") do |f|
      is "\xfcber\n".force_encoding("ASCII-8BIT"),
        f.gets
    end
  ensure
    File.delete(TMPFILE)
  end

# Note that unlike read(), even data written using write() is transcoded.

  begin
    File.open(TMPFILE, "w:ISO-8859-1") do |f|
      f.write "über"
    end
    File.open(TMPFILE, "rb") do |f|
      is "\xfcber".force_encoding("ASCII-8BIT"),
        f.gets
    end
  ensure
    File.delete(TMPFILE)
  end

# If you don't want to transcode, then open the file in binary mode.

  begin
    File.open(TMPFILE, "wb") do |f|
      f.write "über"
    end
    File.open(TMPFILE, "rb") do |f|
      is "\xC3\xBCber".force_encoding("ASCII-8BIT"),
        f.gets
    end
  ensure
    File.delete(TMPFILE)
  end

# When you open a socket, the default_external_encoding is ignored and
# ASCII-8BIT is always used.

  require 'socket'
  s = TCPServer.new("127.0.0.1", nil)
  is [Encoding::ASCII_8BIT, nil],
    [s.external_encoding, s.internal_encoding]
  s.close

# Like Strings, there are also some methods on IO which explicitly deal
# only in bytes, such as IO#getbyte and IO#bytes

############# POSTAMBLE ##################

end # def test_string19

private
  def execute_in_file(str)
    write_file(str) do |fn|
      %x{ env LC_ALL=en_US.utf8 #{RUBY} #{fn} 2>&1 }.chomp
    end
  end

  def write_file(str)
    File.open(TMPFILE,"wb") { |f| f << str }
    yield TMPFILE
  ensure
    File.delete TMPFILE
  end
end

# TODO:
# - how to write C extensions which are encoding-aware
#   (rb_str_modify etc)

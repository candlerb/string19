=begin rant
Skip this section if you are not interested in my personal opinion.

All this stuff scares me, and I absolutely detest it. I have been with ruby
since 1.6; what I love is that code you write is simple and compact, and the
language usually doesn't bite you.  With ruby 1.9, I find this is no longer
the case.

* Every time I write a simple statement like "a << b", I have to
  consider the possibility that my program may crash. With ruby 1.8,
  if I know that a and b are both strings, this will not happen.
  
  What's worse, it doesn't *always* crash if strings with two different
  encodings encounter each other. This means a program may crash when it
  receives unforeseen data, which means you need a lot more work to ensure
  your tests have sufficient coverage.

* Unless you take explicit steps to avoid this, the behaviour of the program
  will vary dependent on what system it is run on.  That is, the *same*
  program running with the exact *same* data and the *same* version of ruby
  will behave *differently* on different systems, possibly crashing on one
  where it worked on the other.  Again, it's possible to defend against
  this, but it requires additional work.

* It's ridiculously complicated. This document contains around 200 examples
  of behaviour, and could form the basis of a small book.  It's a +String+
  for crying out loud!  What other language requires you to understand this
  level of complexity just to work with strings?!  The behaviour is full of
  arbitrary rules and inconsistencies (like /abc/ having encoding US-ASCII
  whilst "abc" having the source encoding, and some string methods raising
  exceptions on invalid encodings and others not)

* It's buggy as hell. I found loads of bugs just in the process of
  documenting this. To me this two could imply two things:
  
  - even Ruby's creators, who are extremely bright people, don't understand
    their own rules sufficiently to implement them properly. In that case,
    what chance do the rest of us have?
    
  - very few people are actually using this functionality, in which case,
    what's it doing as a core part of the language?

* Of course, it's very hard to categorise something as a "bug" if you don't
  know what the intended behaviour is.  Almost all the behaviour given in
  this file is undocumented.  By that I mean: when I look at the
  documentation for String#+, I expect at minimum to be told what it
  requires for valid input (i.e.  under what circumstances it will raise an
  exception), and what the properties of the result are.
  
  If Ruby has any ideas of becoming a standardised language, the ISO and
  ANSI committees will laugh down the corridor until all this is formally
  specified (and what I have written here doesn't come close)

* Even when I explicitly tag an object as "BINARY", Ruby tells me it's
  "ASCII-8BIT".  This may seem like a minor issue, but it annoys me
  intensely to be contradicted by the language like this, when it is
  so blatently wrong. All text is data; the converse is *not* true.

* It solves a non-problem: how to write a program which can juggle multiple
  string segments all in different encodings simultaneously.  How many
  programs do you write like that? And if you do, can't you just have
  a wrapper object which holds the string and its encoding?

* It's pretty much obsolete, given that the whole world is moving to UTF-8
  anyway.  All a programming language needs is to let you handle UTF-8 and
  binary data, and for non-UTF-8 data you can transcode at the boundary. 
  For stateful encodings you have to do this anyway.

* It's half-baked. You can't convert between uppercase and lowercase,
  and you can't compare strings using UCA. So anyone doing serious
  Unicode stuff is still going to need an external library.
  
* It's ill-conceived. Picking characters out of a string may depend only on
  the encoding, but other operations (such as collation) depend on the
  locale. And in any case, the encoding and/or locale information is often
  carried out-of-band (think: HTTP; MIME E-mail; ASN1 tags)

However I am quite possibly alone in my opinion.  Whenever this pops up on
ruby-talk, and I speak out against it, there are two or three others who
speak out equally vociferously in favour.  They tell me I am doing the
community a disservice by warning people away from 1.9.  The remainder are
silent, apart from the occasional comment along the lines of "I wish this
encoding stuff was optional."

I will now try very hard to find something positive to say about all this.

* You can write programs to truncate a string to N characters, e.g.

  if str.size > 50
    str = str[0,47] + "..."
  end
  
  I can only think of one occasion where I've ever had to do this. Maybe
  other people do this all the time.

* You can write regular expressions to match against UTF-8 strings.  Of
  course, ruby 1.8 can do that, by the much simpler approach of tagging the
  regexp as UTF-8, rather than every other string object in the system.

* I can see how it might appeal to be able to write programs in non-Roman
  scripts. Howver this is rather defeated by the fact that constants
  must start with a capital 'A' to 'Z'.

* Erm, that's all I can think of at the moment.
=end

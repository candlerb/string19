=begin rant

More discussion, and examples of problems, at
* http://www.ruby-forum.com/topic/173380
* http://www.ruby-forum.com/topic/179303
* http://www.ruby-forum.com/topic/192218
* http://www.ruby-forum.com/topic/216873

For me, I absolutely hate all this encoding stuff in ruby 1.9, and I'll try
to explain why here.

* As a programmer, the most important thing for me is to be able to reason
  about the code I write.  Reasoning tells me whether the code I write is
  likely to run, terminate, and give the result I want.
  
  In ruby 1.8, if I write an expression like "s3 = s1 + s2", where s1 and s2
  are strings, this is easy because it's a one-dimensional space.
  
               s3     =     s1   +   s2


             ----->       ----->    ----->
             string       string    string

  As long as s1 and s2 are strings, then I know that s3 will be a string,
  consisting of the bytes from s1 followed by the bytes from s2. End of
  story, move to the next line.

  But in ruby 1.9, it becomes a multi-dimensional problem:

               s3     =     s1   +   s2

          enc^         enc^      enc^
             |            |         |
             |            |         |
             +---->       +---->    +---->
             string       string    string
  
  The number possibilities now explodes. What are the possible encodings
  that s1 might have at this point in the program? What are the possible
  encodings that s2 might have at this point? Are they compatible, or will
  an exception be raised? What encoding will s3 have going forward in the
  next line of the program?

  The reasoning is made even harder because the *content* of the strings is
  also a dimension in this logic.  s1 and s2 might have different encodings
  but could still be compatible, depending on whether they are empty or
  consist only of 7-bit characters, as well as whether they are tagged with
  an ASCII-compatible encoding.  The encoding of s3 also depends on all
  these factors, including whether s1 is empty or s2 is empty.

  Analysing a multi-line program then multiplies this further, as you need
  to carry forward this additional state in your head to where it is next
  used.

* Now try reasoning about a program which makes uses of strings returned by
  library functions (core or third party), where those functions almost
  never document what encoding the string will be tagged with.  You need to
  guess or test what encoding you get, and/or reason that the encoding
  actually doesn't matter at this point in the program, because of what you
  know about the encodings of other strings it will be combined with.

* Whether or not you can reason about whether your program works, you will
  want to test it. 'Unit testing' is generally done by running the code with
  some representative inputs, and checking if the output is what you expect.
  
  Again, with 1.8 and the simple line above, this was easy. Give it any two
  strings and you will have sufficient test coverage.
  
  With 1.9, there is an explosion of test cases if you want to get proper
  coverage: the number of different encodings and string contents
  (empty/ascii/non-ascii) you expect to see for s1, multiplied by the same
  for s2, plus testing the encoding of the results.

  Third-party libraries need this sort of test coverage too, but generally
  don't have it. For an example of the problems this can cause, see
  http://www.ruby-forum.com/topic/476119

  Here a user is taking a string returned by Sinatra (which tags it as
  ASCII-8BIT) and passing it as a query argument to sqlite3-ruby. The
  sqlite3-ruby query fails, even though the string contains only ASCII
  characters, but the query works if given the same string tagged US-ASCII
  or UTF-8.
  
  You can argue weakly that this is a bug in Sinatra (for not tagging the
  string UTF-8, which it could have done from the Content-Type:...encoding
  header), or more strongly that this is a bug in sqlite3-ruby; but neither
  library documents or tests its encoding-related behaviour, so you're
  basically relying on undefined behaviour in your application.
  
  Such problems can be a real nightmare to debug.

* Unless you take explicit steps to avoid it, the behaviour of a program
  under ruby 1.9 may vary depending on what system it is run on.  That is,
  the *same* program running with the exact *same* data and the *same*
  version of ruby can behave *differently* on different systems, even
  crashing on one where it worked on the other.  This is because, by
  default, ruby uses values from the environment to set the encodings of
  strings read from files.
  
  Even on the same system, your program could work when run from an
  interactive shell but fail when run from a daemon such as cron. See
  http://www.ruby-forum.com/topic/211476#918885

  It's possible to override ruby's policy on this, but it requires
  remembering to use some incantations.  If you accidentally omit one, the
  program may still work on your system but not on someone else's.

* It's ridiculously complicated. string19.rb contains around 200 examples of
  behaviour, and could form the basis of a small book.  It's a +String+ for
  crying out loud!  What other language requires you to understand this
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
  string19.rb is undocumented.  By that I mean: when I look at the
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
  
* It's ill-conceived. Knowing the encoding is sufficient to pick characters
  out of a string, but other operations (such as collation) depend on the
  locale.  And in any case, the encoding and/or locale information is often
  carried out-of-band (think: HTTP; MIME E-mail; ASN1 tags), or within the
  string content (think: <?xml charset?>)

* It's too stateful. If someone passes you a string, and you need to make
  it compatible with some other string (e.g. to concatenate it), then you
  need to force it's encoding. That's impolite to the caller, as you've
  mutated the object they passed; furthermore, it won't work at all if they
  passed you a frozen string. So to do this properly, you really have to
  dup the string you're being passed, which needlessly copies the entire
  content.

  # ruby 1.8
  def append(str)
    @buf << str
  end
  
  # ruby 1.9
  def append(str)
    @buf << str.dup.force_encoding("ASCII-8BIT")
  end

* The arbitrary rules are constantly changing. For example, the behaviour
  of \w and \s in a regexp will be different in the 1.9.2 release.
  http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-core/30543

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

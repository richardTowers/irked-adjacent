irked-adjacent
==============

> Like, I'm feeling a little irked, or at least like irked-adjacent, and then
these guys bring in their bad vibes - Bro, I'm straight up not having a good
time.

- [Johnny Mendez](https://youtu.be/Qp1oN23xotM?si=iYR8rCRiRIPWKTUv)

`irked-adjacent` is a project looking at using AI agents and coding assistants
to build content management systems (CMS).

Content management systems are a notoriously well explored space in open source,
so LLMs trained on open source code should have plenty of training data.  At the
same time, good content management systems are complex and require a lot of
features to be competitive in a crowded market.

`irked-adjacent` also hopes to compare a few different programming languages and
ecosystems, by building roughly the same content management system using
different technologies.

Hypotheses (2026-02-24 - before beginning the project)
------------------------------------------------------

LLM based coding agents (e.g. Claude code / Opus 4.6) will be able
to produce a mostly functional content management system with relatively limited
prompting.

Agents will have an easier time building (or perhaps,
plagiarising) CMSs in popular languages used for other CMS (PHP, Python, Ruby on
Rails) than in languages like Rust / Haskell where CMSs are less common.

With a good harness (i.e. good prompting, linting and automated testing), agents
should be able to do a reasonably good job of accessibility and security (but this
is something I'll want to keep a close eye on).

Approach
--------

The primary implementation is going to be a ruby on rails application, as this is
currently the language and framework I'm most confident in, so I should be able to
help the agent more effectively.

A secondary implementation in Rust will be built in parallel - each plan will be
translated by the agent from Rails to Rust, and then implemented. I don't know Rust
(yet - I'm learning it at the moment), so I'll be basically unable to help the agent out.

Structure
---------

The tickets directory contains markdown files which specify the features of the CMSs. They
will be mostly AI authored, with edits according to my personal taste.

The acceptance-tests directory will contain end-to-end tests which every implementaion must pass.
They'll be AI authored against the ruby-on-rails implementaion, but other implementations should also
pass the same tests.

The language-framework directories (e.g. ruby-rails) will contain individual implementations of the CMSs.

Ethical issues
--------------

I'm aware of, and uncomfortable about, the ethical issues around the current generation
of AI. In particular, energy demands, the use of intellectual property gathered without
consent for traning models, and the real world harm that use of these tools can cause.

However, my personal use or abstinence of LLMs is such a tiny factor that it
won't move the needle one way or the other.

I am also increasingly persuaded that, for software engineers like me, AI
assisted coding is an economically inevitable part of our future. Since I need
to earn a living, and I do not want to change career, I will at some point have
to learn to use these tools effectively.

These may be weak justifications, and you are welcome to judge me for the
rationalisation.

# Asking for support

The app can mention, once, that it can be supported. Two things had to be decided before
writing it, and one of them is still open.

## What is built

- A note at the **end of a session**, never during one, after **seven days** and **five
  sessions**. Asked **once, ever** — not once a week, not once a version.
- A row in Setup, behind the child lock, where a caregiver can find it deliberately.
- Both are invisible unless `SupportURL` is set in `Info.plist`. A button that promises a
  way to give and opens nothing is worse than no button.

The harness checks the timing: asked after a week of real use, never on day two, never to
somebody who opened it twice, and never twice over a simulated year.

## Why it is addressed to the caregiver

The person holding the iPad may have memory difficulties. They may not remember having
been asked, may not remember whether they already gave, and cannot meaningfully consent to
a purchase in the middle of a game. So the wording speaks to whoever set the app up, it
never appears mid-round, and the Setup entry sits behind the child lock with everything
else that is not the player's business.

## The open question: what may go in `SupportURL`

This is an App Store rule, not a design choice, and the answer depends on Mission Peak's
status.

- **A registered nonprofit** may collect donations through an external link or an approved
  in-app donation flow.
- **A for-profit developer** generally may not link out for donations. The supported route
  is a consumable in-app purchase — a tip jar — with Apple's cut. Linking to an external
  donation page is the kind of thing that gets a build rejected under §3.1.1.

Spec §12 also lists a pay-what-you-want model as **out of scope for v1**, so shipping this
is a scope decision as well as a legal one.

Until `SupportURL` is set, none of this appears anywhere in the app.

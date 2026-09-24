# Putting the photo packs in OneBucket

Spec §5 and §10: the packs live on Wasabi and reach the app through OneBucket. Until now
every pack photograph has been hotlinked from Wikimedia Commons at play time, which is
fragile in a way that shows up as a blank card — a file renamed on Commons disappears from
somebody's round — and it means the photograph that was vetted is not necessarily the
photograph that ships.

## The three steps

```bash
python3 Tools/PackBuilder/to_onebucket.py     # stage 930 photos + rewritten manifests
./Tools/PackBuilder/upload_packs.sh wasabi    # your keys, your shell
```

Then, and only then:

```bash
python3 Tools/PackBuilder/to_onebucket.py --apply   # point the app at the bucket
```

The order matters. `--apply` rewrites the bundled manifests to fetch from Wasabi, so
running it before the bucket can be read replaces every pack photograph with a blank card.

## The bucket is private, and that is the open decision

`timerolls` answers requests with **403** to anyone without credentials. The app has no
credentials and must never have any — keys in an app binary are extractable by anybody
who downloads it, and the key that can write is the one you would least like extracted.

So one of these has to be true before the app can fetch a pack photograph:

**Make `packs/*` public to read.** One bucket policy. These are freely licensed
photographs that are already public on Commons, so nothing is being exposed that was not
already; what it costs is Wasabi egress, and anyone with a URL can read them. This is the
simple answer and almost certainly the right one.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": "*",
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::timerolls/packs/*"
  }]
}
```

**Or put OneBucket in front of it**, which is what §10 actually describes — the app asks
OneBucket, OneBucket holds the credentials. That keeps the bucket shut and gives you a
place to count downloads, and it needs an endpoint that does not exist yet.

Presigned URLs are not a third option: they expire in about an hour, so a shipped app
would need a service to mint them, which is the second option wearing a hat.

## What the copies carry

Hosting our own copy of a CC BY photograph is allowed exactly because the credit and the
licence travel with it. Every item in the rewritten manifests now carries:

- `originalURL` — where the photograph came from, kept so a credit can be checked
- `licenseURL` — the licence deed, including the ported ones (`by-sa/3.0/de/` and friends
  point at their own jurisdiction rather than the unported licence, which would credit the
  photograph under terms it was not released under)
- `isResizedCopy` — true, because these are resized

The credits screen should show all three. That is not done yet.

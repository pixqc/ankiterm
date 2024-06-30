# Ankiterm

Ankiterm is a terminal-based spaced repetition software.

Guiding principle: data is plaintext, no external deps, unix philosophy. The north star is having a spaced repetition software reliable for the next 20 years.

Ankiterm currently implements the SM2 spaced repetition algorithm. Read more: https://archive.ph/lWz4N

"Why bother doing spaced repetition?": https://gwern.net/spaced-repetition

To install:

```
not ready to be used yet, but soon!
```

Ankiterm's commands:

```
ankiterm [command] <filename>

Commands:
  init <filename>         Initialize a new deck
  review <filename>       Review due cards
  stats <filename>        Show statistics
  tidy <filename>         Tidy up the deck

Global Options:
  --help                  Show help message and exit
  --version               Show version information and exit
```

To initialize a new deck:

```
ankiterm init deck.ndjson
```

deck.ndjson:

```
// card data has the following format:
{"type":"card","id":1,"front":"2^8","back":"256"}
{"type":"card","id":2,"front":"what is string in zig","back":"pointer to null-terminated u8 array"}
{"type":"card","id":3,"front":"what is a symlink file","back":"pointer to file/dir"}

// review data has the following format:
{"type":"review","id":1,"card_id":1,"difficulty_rating":5,"timestamp":1718949322,"algo":"sm2"}
{"type":"review","id":2,"card_id":2,"difficulty_rating":0,"timestamp":1718949322,"algo":"sm2"}
{"type":"review","id":3,"card_id":3,"difficulty_rating":3,"timestamp":1718949322,"algo":"sm2"}
```

The nice thing about plaintext: grep, sed, jq works:

```
# sed a word
sed -i 's/bocchi/kitaaan/g' deck.ndjson

# grep cards
grep '"type":"card"' deck.ndjson

# calculate stats with jq
jq -s 'map(.difficulty_rating) | add / length' deck.ndjson

# get all hard cards
jq -r 'select(.difficulty_rating == 0) | .front' deck.ndjson | uniq

# backup to s3
aws s3 cp deck.ndjson s3://mybucket/deck.ndjson
```

Alias `<youralias>` to `nvim ~/path/to/deck.ndjson` for quickly adding card.

Alpha software, please reach out if it breaks: https://x.com/pixqc

I am using this software daily, more improvements and stability coming soon!

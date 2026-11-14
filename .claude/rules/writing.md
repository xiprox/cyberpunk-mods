# Writing

```text
Purpose:  How everything an agent writes for people to read is written.
Covers:   READMEs, RECORD.md files, ideas, code comments, commit messages, words in
          the game, instructions for agents, and replies in chat. A rule made for
          files, such as one sentence per line, holds only in files.
Source:   Adapted from Choom Collector's .claude/rules/writing.md, which adapts
          Dual Input's.
```

## The test

Can it be read once, at speed, and understood?
A sentence that needs a second pass has failed, however accurate it is.
A reader who has to work stops reading, and a reader who stops reading acts on half a document.

When a rule below disagrees with this test, the test wins.

## Kinds of document

Before the first sentence, know which kind you're writing.
The kind decides who reads it and what shape it takes.
The root [CLAUDE.md](../../CLAUDE.md) says which files every mod has.

| Kind                     | Lives in                                 | The reader wants to                                                     |
| ------------------------ | ---------------------------------------- | ----------------------------------------------------------------------- |
| README, for players      | `mods/<mod>/README.md`, first            | know what the mod does in the game, what it needs, and how to install it |
| README, for developers   | `mods/<mod>/README.md`, after the players' part | build and test it, or use it from another mod                     |
| Record                   | `mods/<mod>/RECORD.md`                   | know what we found and decided, and why the mod is this way             |
| Idea                     | `ideas/<mod>.md`                         | know what scouting found before the mod started                         |
| Reference                | beside what it describes                 | look one thing up                                                       |
| Agent instructions       | `CLAUDE.md` files and `.claude/`, this file included | act correctly without asking                                |

A document that's two kinds at once serves neither reader.

### README

The players' part comes first, and it's also the mod's Nexus Mods page, so its reader has never seen the code and stops reading once they know enough.
It runs in this order, leaving out what a mod doesn't have:

1. What the mod does, in the game's terms, in two or three sentences.
2. Using it: keys, menus, and what you see and hear.
3. What it needs: the other mods by name, without links, since the Nexus Mods page lists them, and the game version it was made for.
4. Installing, updating, and removing it.
5. What it works with and against: co-op, other mods, a game patch, Linux.
6. Known limits.
7. What to send with a bug report.

The players' part uses only headings, paragraphs, lists, bold, and code, so it carries over to the Nexus Mods page.
It names no file a player won't open, and no internal name, such as a bus, a native, or a TweakDB record.
Something only a tinkerer would touch, such as a tuning file, belongs in the developers' part or nowhere.

The developers' part says how the mod works in a few sentences and links the RECORD for why, then covers what other mods can use, building and testing, and how the crew gets it.

### Record

A RECORD is a log: what we found and decided, newest entry first, one dated heading per entry, `## <YYYY-MM-DD>: <what changed>`.
Each entry says what we asked or saw, what we found, and what changed because of it.
A result that didn't work gets the same care as one that did, because what was tried and abandoned is the part git history can't tell anyone.
An entry isn't rewritten when a later one overturns it: the later entry says what it overturns.

Its top keeps the status lines, "Installed" and "Not yet checked in the game" among them, and they're the only place that says what's installed and what's waiting for a game test.
A mod is small enough that a plan of its own would be one more file to keep true, so these lines are the plan.

### Idea and reference

An idea holds what scouting found, with the same evidence markers as a record, and becomes the mod's first RECORD entry when the mod starts.
A reference is tables and lists with no argument, and links to the record for the reasoning.

## Structure

**Lead with the answer.**
The first paragraph says what the document establishes.
Background, history, and caveats come after the reader knows what they're for.
So no heading is called Overview, Introduction, Summary, or Conclusion: the first paragraph is the overview, and a closing summary repeats the document.

**One document, one job.**
A document runs as long as its job needs, and a second job goes into a document of its own.

**Write a value down once.**
Everywhere else links to it.
A value written twice is two values that haven't disagreed yet, as Headset's README and code do over `recoil_db`'s starting value.
This holds for numbers, rules, status, and vocabulary alike.

**Describe the current state, not the edit.**
Don't write "now", "updated to", or "no longer", except in a record entry or a commit message.
Git holds the change, and a reader arriving next year doesn't care what the text used to say.

**Headings name the content.**
Write "Known limits", not "Limits, stated rather than discovered".
Use sentence case, and never a question.

**Procedures are numbered steps.**
Each step is one action and says what you'll see when it worked.
The condition comes before the action, "If the game is running, close it", so the reader doesn't act before reaching it.

**Delete an empty template section**, unless the emptiness is the information.
"No known limits" is worth a line.

**Links within the repository are relative, and every link's text names the target.**
Write `[RECORD.md](RECORD.md)`, never "here" or "this doc".

**Folders and new Markdown files are kebab-case**, except the names every mod shares: `README.md`, `RECORD.md`, `CLAUDE.md`, and `CHANGELOG.md`.
A code file follows the names of the files beside it, as `HeadsetNative.reds` and `headset_test.cpp` do.
Dates are `YYYY-MM-DD`.

## Sentences

**One sentence per line** in the source, list items included.
A diff then shows the sentence that changed rather than the paragraph that reflowed, and a sentence that runs off the edge of the editor is visibly too long.
A table cell is the exception, because it can't span lines.
Older files wrap whole paragraphs on one line; split a paragraph into sentences when you next change it.

**Show the mechanism, not a property of it.**
Naming a property makes the reader rebuild the concrete case to check the claim.
Showing the case carries the conclusion and costs fewer words.

```text
✗  The clamp only catches real bangs.
✓  A detector on each gun and blast bus estimates that sound's real-world loudness,
   and the clamp turns the world down only when one estimate passes 85 dB.
```

**Be concrete.**
Give a name, a number, a version, or a path.
"Some mods" is a claim nobody can check, and naming the mods makes it one they can.

**Never invent a specific.**
Every name, number, version, API, and path is real, or is labeled hypothetical where it appears.
The push to be concrete is exactly what makes a plausible fabrication tempting, and a made-up bus name costs an evening in the game to disprove.

**Main clause first.**
A sentence that opens with three conditions makes the reader hold all three before learning what they're conditions on.
Procedures and agent instructions are the exception: there the condition comes first.

**Name who does it.**
Write "Wwise ends a bus's effect while the bus is quiet", not "the effect is ended".
The passive hides the fact a debugging reader needs most: which part to blame.

**Say it once.**
A restatement three paragraphs later, dressed to feel like it adds something, is the same sentence twice.
Before calling a paragraph done, ask what the reader loses if it goes.
If the answer is nothing, it goes.

**Cut the trailing clause that restates the sentence.**
The pattern is an em dash, then a clause that sounds like an explanation and repeats the sentence in a more pleased-with-itself register.

```text
✗  A new clamp starts already worn — which is what a real headset would do.
```

"Which is what X would do", where X does no such thing, is the commonest form.

**No rhetoric.**
Don't argue against a doubt nobody raised: "not just a sound mod".
Don't ask rhetorical questions, in a document or in the game: "Plugged something in? This finds it."
Don't build suspense: "The catch?" and "The result: nothing" hold back the fact the reader came for.

**One word for one thing.**
Define a term at its first use in each document, then use exactly that term.
Switching between "partner", "friend", and "the other player" for variety makes the reader wonder whether they're three things.
Expand an acronym at its first use in each document, unless every reader of this repository already knows it: API, UI, HUD, CI, DLL, and the game's own, like CET, RED4ext, TweakXL, and ArchiveXL.

**Use modal verbs precisely.**
Must is required, should is recommended, and may is optional.
State expected behavior as fact, "the clamp lets go", because "the clamp should let go" can't tell a requirement from a prediction.

**Use an analogy only if it predicts correctly**, and say where it stops holding.

**Tense follows time.**
Use the present for how things work, the past for what we did, and the future for plans and consequences.

## Evidence

A mod built on a wrong claim fails in a session with the crew days later, far from the sentence that caused it.
So every claim about the game, Wwise, NightCoop, Windows, Linux, Proton, or a library, and any other claim a reader could ask "says who?" about, says where it came from:

- **Heard or seen:** the user in the game.
  A record marks it "(user)", and quotes the user where the words matter.
- **Measured:** we ran it, and a log or test shows it.
  For the game, name its version: `(measured on Cyberpunk 2077 2.5, 2026-11-14, headset log)`.
- **Documented:** a vendor or project says so.
  Link the page.
  Before a mod leans on a documented claim, we measure it.
- **Read:** we read it in code or game files, ours or someone else's.
  Name the file and, where it changes, the version: `(read in init.bnk, bank version 150)`, `(read in nightcoop_sdk.h)`.
  Code says what would happen, not that it runs that path, so a claim that turns on which path runs stays unverified until measured.
- **Unverified:** an inference, a forum post, or a guess.
  Mark it unverified, and if anything depends on it, say what would settle it.

A README's players' part and words in the game carry no markers: the RECORD holds the source.

For a source in another of our repositories, cite the repository, the path, and the heading as text, because a link would break for anyone else: `(read in Choom Collector, README.md, "Share and follow mods")`.

A claim with no marker is knowledge a working developer accepts without a source, like "a DLL the game has loaded can't be replaced until it closes".

Say what we don't know.
A gap that's stated can be closed, and a gap that's skipped is a trap.

Quote exactly.
Copy error messages, log lines, and identifiers verbatim, because the reader will search for them.

Code in a document runs as shown, or is labeled a sketch.

## Units, identifiers, and numbers

- Every quantity carries its unit.
- Measurements, and anything a reader might look up or compare, are digits: 41 places, 12 dB, 50 m.
  A count under 10 in running prose can be a word: three players, one em dash.
- Every unit takes a space: 20 ms, 2 s, 32 MB, -14 dB, 120 Hz, 50 m.
- Printed counts handle the singular: "1 file", never "1 files".
- Dates are absolute, like 2026-11-14.
  A fact about the world that's true only for now, such as how a game version behaves, says "as of" and a date.
- Versions are specific: "Cyberpunk 2077 2.5", never "the latest patch".
- Paths in the game folder are written from the game folder, with forward slashes, as the mod places are: `red4ext/plugins`, `archive/pc/mod`.
  The game folder itself is `<game>`, written out once in the root CLAUDE.md.

## Voice

**We, not I.**
A committed document outlives the session that wrote it, and "I" leaves the reader guessing whether a person or an agent wrote it, and which one.
"We" is the project.
Admissions stay in the first person: "we haven't heard this on Linux" is someone talking, and "this has not been tested" reads as evasion.

**You, for the reader**, in procedures, agent instructions, and a README's players' part: "tap the key", "you hear the world come back".

**Plain.**
No enthusiasm, no apology, no emoji, and no exclamation marks.
Contractions are fine wherever you'd say them aloud.

**American English**, with the Oxford comma.
Names keep their own spelling, in code and game files too.
Text a mod already shows players keeps its spelling until all of that mod's strings change together, so one menu never mixes "colour" and "color".

**Names.**
The game is Cyberpunk 2077, or the game, and its hero is V.
A mod is called what its README's title says, as in Headset or NightCoop Voice, and its folder is the kebab-case form, as in `mods/nightcoop-voice`.
Name the player rather than writing "he" or "she", so the reader knows which of the crew it was.

## Words in the game

Everything a player reads in the game, such as a Native Settings page, the HUD, or a notification, follows these rules, on top of the ones above.

- Labels and headings are in sentence case: "Headset key", "Voice gate".
- A setting's description is whole sentences, each with a period, and says what the setting does before when to change it.
- Something happening now takes the progressive, as in "Connecting", and the present simple stays for how things work.
- One word for one thing, the same in every menu and on the HUD: a mode called Active Hearing Protection is never "the clamp" where a player can read it.

## Words and patterns to cut

Each of these usually marks a sentence written on autopilot.
The fix is almost always to delete the word or say the concrete thing it stood in for.
A word doing real work can stay: "actually" correcting a belief the text just stated is fine.

| Cut                                                                                       | Why                                                          | Instead                                           |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------- |
| `genuinely`, `truly`, `really`, `actually`, `honestly`                                    | Sincerity markers imply the rest is less sincere             | Delete                                            |
| `crucial`, `importantly`, `critically`, `vital`                                           | Asserts importance instead of showing it                     | State the consequence                             |
| `essentially`, `basically`, `fundamentally`                                               | Announces an approximation without saying what it leaves out | Say the exact thing                               |
| `simply`, `obviously`, `clearly`, `of course`, `straightforward`                          | Tells the reader how easy it should feel                     | Delete                                            |
| `robust`, `seamless`, `powerful`, `elegant`, `immersive`                                  | Praise that says nothing checkable                           | What it survives or does                          |
| `comprehensive`, `holistic`, `nuanced`                                                    | Same                                                         | What it covers                                    |
| `leverage`, `utilize`                                                                     | Longer words for "use"                                       | use                                               |
| `delve`, `streamline`, `empower`                                                          | Marketing verbs                                              | The literal verb                                  |
| `load-bearing`, `first-class`, `under the hood`, `game-changer`                           | Stock metaphors                                              | What depends on it, or how it works               |
| `worth noting`, `note that`, `it's important to`, `keep in mind`                          | Signposts that announce a sentence instead of writing it     | The sentence                                      |
| `let's`, `in summary`, `in conclusion`, `as mentioned`, `as noted above`                  | Tour-guide narration                                         | Delete                                            |
| `as requested`, `as discussed`, `as you mentioned`, `you asked`                           | Leftovers from a conversation the reader wasn't in           | Delete                                            |
| `don't worry`, `rest assured`, `you might be wondering`                                   | Reassurance nobody asked for                                 | Delete                                            |
| `in order to`                                                                             | Two wasted words                                             | to                                                |
| `a wide range of`, `a variety of`, `various`                                              | A quantity nobody counted                                    | Count them or name them                           |
| `currently`, `recently`, `at the moment`, `as of now`                                     | True only on the day it was written                          | A date, or nothing                                |
| `could potentially`, `might possibly`, and other stacked hedges                           | Two hedges where one would do                                | One hedge, or a marker from [Evidence](#evidence) |
| `not just`, `not only`, `not merely`                                                      | Argues with a claim nobody made                              | The positive claim                                |
| `successfully`                                                                            | Success is the default, so only failure needs saying         | Delete                                            |
| British spellings: `behaviour`, `colour`, `centre`, `grey`, `licence`, `-ise` verbs such as `recognise`, `travelled` | American English | behavior, color, center, gray, license, recognize, traveled |

These patterns are harder to spot, so the `doc-reviewer` agent looks for them too:

- **The reflexive three:** three adjectives or clauses where one would do, chosen for rhythm.
- **The punchy restatement:** a paragraph that ends by saying itself again in a shorter sentence.
- **"It's not X, it's Y"** in any wording, when nobody claimed X.
- **Hedging a measurement:** if we measured it, it "does", not "appears to".
- **A missing Oxford comma.**
- **Unparallel lists:** list items, and headings at the same level, share a grammatical form.
  In agent instructions, a trigger heading ("While the game runs") can sit among noun headings, because the trigger is what gets it followed.

## Formatting

- Use prose for reasoning and lists for parallel items.
  A "because" chain broken into bullets loses its "because".
  Use a list when the items could be reordered without changing the meaning.
- Use a table to compare items on two or more attributes, outside a README's players' part.
  A cell that needs a paragraph means the table is the wrong shape.
- Keep lists to two levels of nesting.
- Fence code blocks and give each a language tag: `bash` for a command, `text` for anything that isn't code.
  Put one command per block, with no prompt character and no output mixed in.
- Draw a diagram as text in a code block when it fits in 20 lines, and use Mermaid when it doesn't.
  A diagram shows a real mechanism with real names, not boxes labeled "Component A".
- Bold at most one phrase per paragraph: the one a skimmer must catch.
- Use at most one em dash per paragraph, with a space on each side.
  A colon, a period, or a pair of commas usually does better.
- Put a callout box (`> **Note**`) only on a warning that costs something if ignored.
- Quote sources briefly, and link to them or cite them as [Evidence](#evidence) says.

## Code comments

A comment's reader is working on the code and hasn't read the RECORD.
The code already states what it does, so a comment earns its place by saying what the code can't: why it's this way, the input that breaks it, the ordering that matters, or the thing that was tried and didn't work.
This holds for C++, Lua, redscript, Python, and YAML alike.

1. **When a comment explains why the code is this way, open with the stakes:** what the code makes possible or prevents, then the fact that shapes it, then the choice the code makes because of it.
   A fact that doesn't lead to the code below gets cut, because a reader forgets facts that connect to nothing.
2. **Define a project term in a clause before using it**, as in "a detector, the effect that reads a bang bus's level", and explain an oddity before the rule that handles it.
3. **Cite only what a reader would doubt and couldn't check quickly**, with at most one pointer, at the end.
   A workaround for the game's, Wwise's, NightCoop's, or Proton's behavior always cites how we know, as a document does: a RECORD entry or a vendor page.
   Skip the citation for anything a compiler or tool reports the moment it breaks.
4. **Where a value lives in two places, say so in both:** "the declaration in `HeadsetNative.reds` must match, so change both together."
5. **Show a format by example, and make the example explain itself:** "`Guns_Firing` is the bus of your own gun", not "a bus such as `X`".
6. **Make each sentence follow from the one before.**
7. **Start a sentence that tells the reader what to do on a later change with its trigger:** "When you add a bus, add it to the README's table."
8. **Use the present tense for what holds:** "the game loads the bank that defines the buses after it starts Wwise", not "loaded".

```text
✗  // Wait before installing.
✓  // The game loads the bank that defines the buses only after it starts Wwise, so
   // the installer waits 10 s from Wwise being up before putting the effect on them.
```

A TODO names the condition that ends it.
Leave out the code's own history, such as "added for the radio change", because git keeps it.
Leave out status, such as a version number in a comment, because it goes stale.
Leave out commented-out code.

## Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org/), because release-please reads them to choose a mod's next version and to write its changelog.
A `feat` or `fix` title is the changelog line, so it says what changed for a player, in the voice above: `feat(siren): partners hear the siren of the police car you drive`.

- `feat` is something a player, or the author of another mod, notices, and `fix` is a bug either could hit.
- `docs` is the README, the RECORD, or ideas, `test` is tests, `ci` and `build` are the pipeline and the build, `refactor` is a change no player notices, and `chore` is the rest.
- The description says why, and what went unchecked in the game.
- A change that needs every player to update together, such as raising a NightCoop protocol number, says so in the description.

Each mod's CLAUDE.md names its scopes, and the root CLAUDE.md says how commits are split.

## Instructions for agents

`CLAUDE.md`, skills, agent definitions, and prompts are read by a model that follows them literally and can't ask what they meant.

- **Every line changes behavior.**
  Delete a line and ask whether an agent would act differently.
  If not, leave it deleted.
  A new rule's reason sentence names the failure that prompted it.
- **Rule first, then the reason in one sentence.**
  The reason is what lets an agent handle the case the rule didn't name.
- **Name the trigger.**
  "While the game runs" gets followed, and a free-floating rule is forgotten by the time it applies.
- **No shouting.**
  Capitals, "IMPORTANT", and "you must always" make a model apply a rule to cases it was never meant for.
  A calm rule with a reason is followed more accurately.
- **One example beats three adjectives.**
  A before-and-after pair teaches what "concise" can't.
- **Point, don't paste.**
  Link to the canonical document.
  A rule that must be seen before an action lives inline in a `CLAUDE.md`, and then only there.
- **Keep each `CLAUDE.md` under 150 lines.**
  It's read at the start of every session, whether or not it's relevant.
- **An agent definition that writes tells its agent to read this file**, rather than relying on Claude Code loading it for the agent.

## Finishing a document

1. Read it once, at speed, as its reader, and note each place you slowed down.
2. Rewrite each of those places.
3. If you wrote or substantially changed a README, a `CLAUDE.md`, or a Markdown file in `.claude/`, run the `doc-reviewer` agent.
   Fix each finding, or tell the user why you didn't.

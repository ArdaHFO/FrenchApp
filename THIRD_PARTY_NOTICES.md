# Third-party data notices

`assets/db/content.db` is a compiled derivative of several external datasets.
The application source code is covered by the repository's MIT `LICENSE`.
That software license does not relicense the external datasets listed here.

## Sources

- **Lexique 3.83**, Boris New and Christophe Pallier. The publisher describes
  Lexique as Creative Commons Attribution-ShareAlike. Preserve attribution and
  the applicable share-alike terms when distributing derived content.
- **FLELex**, François, Gala, Watrin and Fairon. The official download page
  permits use for research or teaching and requests citation of the FLELex
  publication. It does not state a general-purpose software distribution grant.
- **Wiktionary extracts via kaikki.org and DBnary.** These records derive from
  Wiktionary. Preserve the source attribution, provenance and applicable
  Creative Commons share-alike terms for the exact source snapshots.
- **Tatoeba textual sentences.** Default text license is CC BY 2.0 FR and
  requires attribution to sentence authors. The database retains the sentence
  IDs and authors for French, English and Turkish text; cards display those
  author names with the examples.
- **FrequencyWords.** Repository code is MIT; the repository states that its
  generated content is CC BY-SA 4.0.

## Optional online dictionary enrichment

Explicit online dictionary actions use [WiktApi](https://wiktapi.dev/) to read
French entries from English Wiktionary, via structured Kaikki/Wiktextract data.
[WiktApi service software is MIT](https://github.com/TheAlexLichter/wiktapi.dev/blob/main/LICENSE).
Its software license is **not** the license of dictionary content.

Dictionary text is attributed to **Wiktionary contributors**. See the
[entry's source/history](https://en.wiktionary.org/) and
[Wiktionary copyright information](https://en.wiktionary.org/wiki/Wiktionary:Copyrights).
[Kaikki's source/license notice](https://kaikki.org/dictionary/#copyright-and-license)
identifies CC BY-SA and GFDL. Current Wikimedia terms identify
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/); exact source
history and separately credited material may carry additional conditions.
Preserve attribution, source links, modification notices and applicable
share-alike terms when redistributing derived dictionary content.

FrenchApp normalizes and filters the provider response for display, including
omission of tagged inappropriate senses. Each detail view retains the source
entry URL, provider label and retrieval time. Retrieval time is not the
upstream dump/version date, which remains unknown. The cache contains selected
normalized fields rather than raw payloads, is separate from progress, and is
not included in progress backups. Local approved learning content remains
authoritative and works offline.

No remote lexical pronunciation audio is played or downloaded. The inspected
projection contains filenames without sufficient per-file author/license
metadata. Existing device TTS remains available. Upstream quotation examples
are not displayed in the enrichment panel; per-quotation rights/provenance
would need separate handling before enabling them. This is an engineering
attribution record, not legal advice or clearance of all existing datasets.

## Streamed song recordings

Audio is streamed from Wikimedia Commons and is not bundled into the APK.
Traditional lyrics used by the learning view are public domain.

- **Frère Jacques.ogg**, CambridgeBayWeather — CC BY-SA 3.0.
- **Sur le pont d'Avignon.ogg**, CambridgeBayWeather — CC BY 3.0 / GFDL.
- **Alouette (song).ogg**, derived from a transcription by Ixnay — public
  domain according to the Commons file description.

Each song screen displays its source page, attribution and license label. Keep
those notices with any redistributed build.

## Embedded YouTube music videos

Music videos are not copied or redistributed by the application. They are
embedded from the source YouTube channel with YouTube's IFrame Player API in
privacy-enhanced mode. Availability, captions and playback are controlled by
YouTube and the video owner. Traditional compositions may be public domain,
but each embedded performance and video remains the property of its owner.
The application does not store copied commercial lyrics; its short Turkish
vocabulary notes are independently authored learning material.

Traditional video sources currently include Les comptines de Gabriel (Au
clair de la lune), Didier Jeunesse (Une souris verte), HeyKids France
(Meunier tu dors, Ah ! Vous dirai-je maman, À la claire fontaine), Titounis
(Savez-vous planter les choux ?) and Comptines françaises (Cadet Rousselle).

- **youtube_player_iframe 6.x** — BSD 3-Clause; Flutter wrapper around the
  official YouTube IFrame Player API.

Use of embedded videos remains subject to the YouTube Terms of Service and API
Services policies. Commercial recordings or full lyrics must not be bundled
without the necessary rights.

## Distribution gate

The current `content.db` is suitable for local research and teaching use. Do
not publish the APK or database as a generally distributable artifact until:

1. FLELex redistribution terms or permission are confirmed for the intended
   use.
2. Attribution and share-alike notices for the exact Lexique, Wiktionary,
   DBnary and FrequencyWords snapshots are bundled with the artifact.

This notice is a compliance checklist, not legal advice.

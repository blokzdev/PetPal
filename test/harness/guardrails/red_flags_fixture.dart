/// Coverage fixture for the red-flag screener (CLAUDE.md §10 + DECISIONS
/// row 29). Each category ships ≥30 positive phrasings + ≥20 negative
/// phrasings here; the parameterised test in
/// `red_flags_fixture_test.dart` walks every entry. New patterns
/// require new fixtures in the same commit (DECISIONS row 29 coverage
/// rule).
///
/// Built incrementally across multiple commits — one or two
/// categories per commit — to keep diffs reviewable and the
/// regression surface honest. Categories are added in the canonical
/// order from `lib/harness/guardrails/red_flags.dart`.
library;

/// Phrases that MUST flag the named category.
const positives = <String, List<String>>{
  'blood_in_stool': [
    'I noticed blood in his stool this morning',
    'There was blood in her stool',
    'Blood in the stool again',
    'Blood in his poop overnight',
    'Bloody stool today',
    'Bloody diarrhea twice today',
    'Bloody diarrhoea — really worried',
    'There is blood in his diarrhea this morning',
    'Found blood in her diarrhoea',
    'Saw blood in his feces',
    'Blood in his faeces',
    'Loki passed bloody poop',
    'Loki passed a bloody stool',
    'There is blood in the diarrhea',
    'Blood in the poop, second time',
    'His stool is black',
    'Her stool is dark',
    'Stool is tarry',
    'Stool looks black',
    'Stool looks tarry',
    'His stool looks dark and sticky',
    'Her poop is black',
    'Poop is bloody',
    'Poop seems red',
    'Faeces appear black',
    'Black diarrhea',
    'Tarry stool today',
    'Red stool, no idea why',
    'Dark stool, like coffee grounds',
    'Loki has melena',
    'Suspect melena',
  ],
  'blood_in_vomit': [
    'There was blood in his vomit',
    'Blood in her vomit twice',
    'Blood in the vomit this morning',
    'She vomited blood last night',
    'He vomited blood right before bed',
    'Loki vomited blood',
    'Threw up blood',
    'Threw up blood twice in an hour',
    'Throwing up blood',
    'He throws up blood after meals',
    "She's been throwing up blood",
    'Throw up blood — vet now?',
    'Coughing up blood',
    'Loki is coughing up blood',
    'He started coughing up blood',
    'Hematemesis since yesterday',
    'Possible hematemesis',
    'Blood in his throw up',
    'Blood in her throw-up',
    'Blood in her puke',
    'Blood in his puke',
    'Vomits blood every few hours',
    'Vomited blood overnight',
    'There is blood in his vomit on the rug',
    'Found blood in the vomit',
    'Saw blood in her vomit',
    'Blood in throw up — second time',
    'He threw up blood after dinner',
    'She vomited blood and bile',
    'Vomits blood-tinged liquid',
    'He has been vomiting blood',
  ],
};

/// Phrases that MUST NOT flag the named category. These are
/// deliberately textually adjacent to the positive set — the
/// false-positive-tolerant principle (DECISIONS row 29) means we
/// allow some over-matching, but we still want the obvious adversarial
/// cases (e.g. "chocolate-coloured fur") to stay clean.
const negatives = <String, List<String>>{
  'blood_in_stool': [
    'His stool was brown and normal',
    'Normal stool today',
    'Loki had a great walk and a normal poop',
    'Stool sample at the vet went fine',
    'No blood, no diarrhea, all good',
    'Reading a book about blood lineages in dogs',
    'The trainer talks about blood-tracking dogs',
    'Bought a poop bag at the store',
    'Brown poop, firm, healthy',
    'Asked the vet about stool consistency',
    'No issues with his stool this week',
    'She had a tiny scratch but no bleeding',
    'Stool looks brown and firm',
    'Stool consistency improved',
    'Diarrhoea cleared up overnight, no blood',
    'No blood at all in his poop',
    'Vet asked us to bring a stool sample',
    'Loki licked some red paint earlier',
    'Just a stain on the rug — not blood',
    'Reddish carpet, not stool',
  ],
  'blood_in_vomit': [
    'He vomited once after eating grass',
    'Threw up some hair, looked normal',
    'Vomited bile this morning',
    'She vomited foam',
    'Loki vomited a chew toy',
    'No blood in any of his vomit',
    'The vomit looked yellow',
    'Vomit was clear liquid',
    'Threw up his food whole',
    "Loki's blood test came back fine",
    "We're going for a blood draw next week",
    'Coughed twice but no blood',
    'Coughing — vet says kennel cough',
    'Reading about blood types in cats',
    'Brought a vomit sample to the vet',
    'Blood pressure check next week',
    'Donated blood for a transfusion drive',
    'Watching Bloodhound rescue videos',
    'No blood, no concern',
    'The puke was clear and small',
  ],
};

# Logging reactive episodes

Reactivity progress is invisible week-to-week and obvious month-to-
month, but only if there's a log to compare against. When the user
describes an episode, prompt them for the variables that matter and
write a `behavior/` entry:

- **Date and time of day.** Morning walks vs evening walks differ in
  context (other dogs out, light, owner energy).
- **Location.** Specific street, dog park, hallway. Patterns cluster
  geographically.
- **Trigger.** Other dog (size? on/off leash?), person (hat, beard,
  child?), bike, skateboard, sudden noise.
- **Distance at first notice.** "Spotted at 40 feet" vs "spotted at
  10 feet" tells you whether the dog is scanning ahead.
- **Reaction intensity.** Stiffened only / barked / lunged / could
  not be redirected.
- **Recovery time.** How long until the dog could take food / walk
  loose-leashed / sniff again.
- **What the user did.** Retreated, reoriented, fed, ignored.

The user doesn't need to write all of this freeform — they can tell
PetPal "Loki barked at the brown lab on Maple at 5pm, recovered in
about a minute" and PetPal fills in the structure when saving the
memory.

Over weeks, this log answers questions the owner can't otherwise
hold in their head:

- Is recovery getting faster?
- Are working distances shrinking?
- Are mornings worse than evenings?
- Is one specific trigger doing most of the damage?

Frame the log as **for the trainer, the vet behaviorist, and Future
You**, not as a chore.

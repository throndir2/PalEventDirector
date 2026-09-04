# Mandatory invasions and bounty sieges

## Decision

Base-invasion events are mandatory world events. Pal Event Director will not add registration, consent, guild opt-in, or an online-defender requirement before targeting a base.

A scheduled all-base event attempts to attack every base known to Palworld's invasion manager at the same event boundary. Warnings are informational, not requests for permission. A base can still fail for technical reasons—no valid invasion start point, blocked navigation, invalid/unloaded model, an existing invasion, or a native engine restriction—but that is not treated as player choice.

Palworld 1.0 has a native Negotiator phase that may let players buy off a declared raid. Event profiles can either preserve that native mechanic or use the exact-group debug/server path's `bSkipInvaderDeclaration` option for a forced assault. The forced all-base profile should skip declaration if testing confirms this also bypasses the Negotiator phase.

Consent remains relevant to unrelated mechanics that directly take control of an individual player, such as forced teleportation or experimental PvP rules. It is not part of base-invasion targeting.

## Evidence snapshot

This design was checked on 2026-08-31 against:

- Palworld Modding Kit commit `e6632458b97af0083eb81715775651b08104ef6a`;
- the installed `Pal-WindowsServer.pak`, SHA-256 `BFFAB47CBD3B3C6D14D616376D4E0B060B2429A5EB4C2022820D4F38D36A0770`, dated 2026-08-12 UTC;
- `repak` 0.2.3 for read-only pak extraction;
- UAssetGUI/UAssetAPI 1.1.0 for temporary JSON decoding.

No extracted game assets or table dumps belong in this repository.

Current installed data contains:

- 240 `DT_PalInvader` rows;
- 76 distinct invasion `GroupName` values;
- numeric row keys for all 240 rows, while descriptive `GroupName` values repeat across compatible variants;
- up to five character archetype slots per row;
- up to 16 attackers per stock row and up to five waves in stock data;
- no stock invasion member whose `CharacterID` begins with `BOSS_`;
- one `DT_PalInvaderReward` entry for each of the 76 stock group names;
- 34 special-enemy `DT_PalDropItem` rows that grant `BountyProof_1` at 100%.

## Level selection and base alignment

### Native behavior

Pocketpair's Palworld 1.0 notes state that raid-enemy level automatically scales according to the level of Work Pals assigned to the deployed base. For an all-base event, “the deployed base” means the particular base receiving that incident. Two bases in the same guild can therefore be evaluated from different assigned workforces; there is no evidence that Palworld uses one guild-wide level for every guild base.

That statement does **not** mean every invader has the same level as one Pal, or that the maximum/average worker level is copied directly. Current structures show an indirect pipeline:

1. Palworld examines the target base and derives an invasion grade. Assigned Work-Pal levels are an official input; the aggregation formula is unknown.
2. `SelectInvaders(Grade, Biome, ...)` chooses an eligible row whose `InvadeGradeMin`/`InvadeGradeMax` and biome match.
3. The row supplies a minimum/maximum level for each of its five member slots, plus a `WaveLevelOffset` field.
4. Selection produces one `FPalInvaderSpawnCharacterParameter` per concrete member, each with a final integer `Level`.
5. The native spawn Blueprint passes `SpawnParameter.Level` into character initialization.

The current installed grade bands are 1–10, 11–20, 21–40, 41–60, and 61–80. All current row wave offsets are zero. Those facts describe the current data, not permanent engine constraints. Some low-grade rows in endgame biomes still specify high member levels, proving that grade is a row-selection tier rather than guaranteed equality with attacker level.

### Event Director control

Yes, the event can specify boss levels. Route A transforms selected members at the final pre-spawn parameter, so changing `FPalInvaderSpawnCharacterParameter.Level` changes the exact level consumed by native character initialization. The transform should expose only these bounded policies:

| Policy | Effective level | Use |
|---|---|---|
| `native` | Preserve the level Palworld selected for that member and target base. | Default; retains official per-base balance. |
| `fixed` | A configured exact level, clamped to validated global/profile limits. | A deliberately uniform boss event. |
| `relative` | Native final level plus a bounded signed offset, then clamped. | Harder/easier than the base's normal raid. |
| `workerDerived` | A named, versioned project statistic over a snapshot of that base's assigned Work-Pal levels, then clamped. | Transparent custom scaling; experimental. |

For the first bounty siege, use `native`: replace `CharacterID` and optionally `Otomo`, but leave `Level` unchanged. Each base then receives bounty actors at the levels Palworld had already selected for that base's invasion members. This preserves relative balance without claiming knowledge of Pocketpair's hidden grade formula.

`fixed` and `relative` are technically direct and do not require changing a DataTable row. `workerDerived` is also possible once the base worker roster can be read reliably, but it is a separate Pal Event Director rule. It must name its statistic explicitly—for example, median or highest-N mean—rather than being presented as native parity.

### Unknown native aggregation

The exact Work-Pal aggregation remains unresolved. Generated SDK implementations are stubs, the native server binary does not expose a useful formula string, and the official note identifies only the input relationship. A live disposable-world experiment must vary one factor at a time and record native grade and final levels:

- one assigned worker at controlled levels;
- full bases where every worker has the same level;
- one high-level worker among low-level workers and the inverse;
- ascending mixed distributions to distinguish maximum, mean, median, and highest-N behavior;
- empty slots and no assigned workers;
- two different-workforce bases belonging to the same guild;
- worker changes before declaration, during declaration, and before wave selection.

Until that matrix is complete, documentation and player messaging may say “native per-base Work-Pal scaling,” but not “average worker level,” “highest worker,” or “bosses match your Pals.”

## Native invasion controls

### Scope

`UPalInvaderManager` exposes:

- `StartInvaderMarchRandom()`;
- `StartInvaderMarchForBaseCamp(FGuid campID)`;
- `StartInvaderMarchAll()`.

The manager owns a base-ID-to-observer map and a base-ID-to-incident map. `StartInvaderMarchAll()` is therefore the intended first spike for one mandatory attack against every registered base observer.

The word “all” still needs runtime confirmation. The generated Modding Kit implementation is a stub and cannot show whether Palworld internally excludes cooldown, unloaded, obstructed, or already-invaded bases.

### Exact named group

`APalPlayerController` exposes reliable server calls:

- `Debug_InvaderMarch(FName InvaderGropuName, bool bSkipInvaderDeclaration)`;
- `Debug_InvaderMarchForNearCamp(FName InvaderGropuName, bool bSkipInvaderDeclaration)`;
- `Debug_InvaderMarchRandom()`.

`UPalCheatManager` exposes parallel executable functions:

- `InvaderMarch(FName InvaderGropuName)`;
- `InvaderMarchForNearestCamp(FName InvaderGropuName)`;
- `InvaderMarchRandom()`.

The parameter typo is present in Palworld's reflected API. Current data strongly indicates that `InvaderGropuName` means the descriptive `GroupName`, not the DataTable row key: every stock row key is numeric, while group names have values such as `Invader_Group_NPC_Grade5_Hunter` and are shared by rows for the relevant biome/grade variants.

The contrast between `Debug_InvaderMarch()` and `Debug_InvaderMarchForNearCamp()` suggests that the former may apply the named group more broadly, potentially to all bases. That scope is not proven until a live disposable-world test observes which base IDs receive incidents.

### Lifecycle and client delivery

`UPalInvaderManager` exposes declaration, start, arrival, wave-start, wave-end, timeout, and invasion-end delegates. `APalInvaderInfo` replicates base ID, grade, current/max wave, and real-time deadlines.

`UPalNetworkInvaderComponent` sends reliable client RPCs for the same lifecycle. Those RPCs carry `FPalIncidentBroadcastParameter`, which includes:

- invasion type;
- target base model;
- the complete selected `FPalInvaderDatabaseRow`;
- group GUID;
- wave state.

This is favorable for vanilla clients: the client receives the selected row's values rather than only a custom row key. It does not eliminate the need for a clean-client test, particularly for an unknown custom `GroupName` or localization lookup.

## What “type of invader” can mean

### Broad native type

`EPalInvaderType` has only:

- `None`;
- `InvaderEnemy`;
- `VisitorNPC`.

It distinguishes an attack from a visitor event. It does not select Hunters, Free Pal Alliance, Pals, tower bosses, or bounty targets.

### Invasion group

`FPalInvaderDatabaseRow` selects actual composition. A row defines:

- `GroupName`;
- biome;
- minimum and maximum invasion grade;
- selection weight;
- five `CharactorID_*` slots;
- an optional `Otomo_*` companion for each slot;
- minimum/maximum level and count for each slot;
- wave count and interval;
- completion experience;
- per-wave level offset;
- an optional required build-object ID.

This is enough to create raids made from existing bounty humans, their normal companion Pals, ordinary faction troops, Alpha-like variants, predators, or any other validated existing character IDs.

## Bounty targets as invaders

### Why the idea is credible

The invasion member parameter contains `CharacterID`, `Level`, `Otomo`, and a visitor-leader flag. The current character-drop lookup is also keyed by `CharacterID` and level.

All current bounty drop rows use level `0`, which acts as the general row for that character archetype. Each corresponding `BOSS_*` character ID grants `BountyProof_1` at 100%. Therefore an invasion actor initialized with the exact bounty `CharacterID` is highly likely to retain its normal Successful Bounty Token drop regardless of event-selected level.

Current examples include:

| Tokens | Bounty character IDs |
|---:|---|
| 1 | `BOSS_Hunter_Rifle` (Hawk), `BOSS_Believer_CrossBow` (Ego), `BOSS_Ninja` (Fumble), `BOSS_Female_Soldier` (Jade), `BOSS_Male_Soldier` (Crash), `BOSS_Male_Soldier02` (Dart), `BOSS_Male_Soldier04` (Lasso), `BOSS_Female_People02` (Siren), `BOSS_Female_People03` (Turncoat), `BOSS_Male_People` (Dyna), `BOSS_Male_People2` (Mite), and `BOSS_Male_People03` (Scoot). |
| 2 | `BOSS_Hunter_Fat_GatlingGun` (Grill), `BOSS_Believer_Fat_GiantClub` (Brick), `BOSS_FireCult_FlameThrower` (Shadow), `BOSS_Police_Rifle` (Whip), `BOSS_Male_DesertPeople` (Phantom), `BOSS_Female_DesertPeople` (Whisper), `BOSS_Female_People` (Flare), `BOSS_Female_Soldier03` (Aloha), and the additional `BOSS_Hunter_Fat_GatlingGun_Quest_StrongOldMan` (Elder) row. |
| 3 | `BOSS_Male_Soldier03` (Clint), `BOSS_Female_Soldier04` (Nimble), `BOSS_Male_People02` (Quill), `BOSS_Male_NinjaElite` (Urchin), `BOSS_Scientist_LaserRifle` (Whisk), and `BOSS_Male_Trader01` (Skim). |
| 4 | `BOSS_Viking` (Gnaw), `BOSS_VikingElite` (Cache), `BOSS_Female_Soldier02` (Dazzle), `BOSS_Police_old` (Pinch), `BOSS_Male_Trader02` (Mimic), and `BOSS_Male_Trader03` (Billy). |
| 5 | `BOSS_DarkTrader` (Ram). |

The IDs, quantities, and rates above came from the installed server's current `DT_PalDropItem`, not from a proposed custom reward table.

### Expected retained behavior

High-confidence but still test-required:

- existing bounty body, weapon, combat parameters, client assets, and localized character name;
- normal hostility under invasion AI;
- normal ordinary loot and `BountyProof_1` drop;
- capturability where the original bounty archetype is capturable;
- an `Otomo` companion when the invasion member specifies one;
- normal server replication because the character IDs already exist on vanilla clients.

Community documentation also records that ordinary bounty targets drop tokens on capture and again on butchering. An invasion copy should probably do the same if its character initialization and drop component are unchanged, but this must be tested explicitly.

### Behavior that should not be expected

An invasion member has no `UniqueNPCID`. Consequently, an invasion copy should not be assumed to carry:

- the original fixed world-spawner identity;
- the purple bounty map marker or its cleared/respawn timer;
- one-time bounty discovery/defeat state;
- the first-clear Ancient Technology Point;
- unique talk, quest, or scripted-location behavior;
- any link that suppresses or resets the original overworld bounty.

World-boss bookkeeping uses a spawner context such as `ProcessBossDefeatInfo_ServerInternal(BossActor, SpawnerName)`. A bounty spawned by an invasion has no original bounty spawner name, so the normal overworld target should remain independent. This is desirable for farming but needs save/restart verification.

### Invasion completion rewards are separate

Individual bounty tokens come from `DT_PalDropItem`. Native full-wave rewards come from `DT_PalInvaderReward`, keyed by invasion `GroupName`.

A bounty siege can therefore yield both:

1. tokens and ordinary drops from each defeated/captured bounty actor; and
2. the selected group's native completion reward, or a separately controlled Event Director reward.

A custom group should have a matching completion-reward policy. All 76 stock groups have matching reward rows, which suggests Palworld expects that relationship.

## Preferred implementation

### Route A: native selection transform

This is the preferred first bounty-siege spike because it avoids a custom DataTable row and a PalSchema dependency.

1. Acquire an exclusive invasion-system lease for the occurrence.
2. Build the target set from every base ID known to the base/invasion managers. Do not filter by consent or online ownership.
3. Register an always-present but normally inert hook around `UPalInvaderIncidentBase.SelectInvaders()`.
4. Let Palworld select a valid stock row for each base's biome and invasion grade.
5. In the post-hook, and only for occurrence-targeted base incidents, replace each `FPalInvaderSpawnCharacterParameter` in `OutInvaderMember` before `SpawnMemberCharacters()` runs. Set `CharacterID` to an allowlisted bounty `BOSS_*` ID, preserve or replace `Level` according to the event's bounded level policy, and set an existing companion Pal ID in `Otomo` where desired. Preserve the array length unless a bounded count transform has been tested separately.
6. Start the world event with `StartInvaderMarchAll()` or the proven exact-group all-base path.
7. Keep the transform armed until every targeted native incident has selected its members; do not assume selection is synchronous.
8. Track each base and incident through native lifecycle delegates.
9. Disarm the transform and release the lease only after every incident resolves or is classified for recovery.

Advantages:

- no custom client content;
- no new replicated row identity;
- native per-base biome/grade selection still establishes a valid incident context;
- native pathfinding, group ownership, waves, UI notifications, and completion rewards remain intact;
- each existing output member can be transformed without requiring Lua to resize a reflected array;
- the normal stock group name remains known to vanilla client localization.

Unknowns:

- whether UE4SS can safely mutate every output struct element in this exact post-hook;
- whether `SelectInvaders()` runs before all data required by the character initializer is fixed;
- whether a captured bounty is removed cleanly from the active invasion group;
- whether stock group completion rewards remain appropriate after member substitution.
- the exact native statistic that maps assigned Work-Pal levels to invasion grade.

### Route B: exact named group rows

Add server-side `DT_PalInvader` rows with one project-owned group and variants covering every biome/grade that should receive the event. Invoke the group by `Debug_InvaderMarch()` with `bSkipInvaderDeclaration=true`.

Advantages:

- direct authoring of character slots, counts, levels, companions, waves, offsets, and experience;
- easier deterministic profiles;
- proven general pattern in community tower-boss/predator raid mods.

Costs and risks:

- requires a runtime DataTable editor such as PalSchema or a validated Lua/native row-injection path;
- introduces a group/row identity absent from vanilla client data;
- needs a matching `DT_PalInvaderReward` policy;
- custom group localization may be absent on vanilla clients;
- current community mods that add large raid tables recommend matching client data, so they are not vanilla-client proof.

The client RPC carries the complete selected row, making server-only operation plausible. However, a new row/group identity conflicts with the current no-new-data-identity contract. Route B therefore remains laboratory-only unless it reuses and temporarily patches a stock identity without exposing a new one, or the project contract is explicitly revised after clean-client proof.

### Route C: independent character wave

Spawn bounty characters near every base with the general character manager and command them toward the base.

This is not preferred. It recreates AI targeting, navigation, wave state, client notifications, capture/death cleanup, and completion logic that the native invasion system already provides. It should be used only if native composition control proves impossible.

## Mandatory all-base event model

A future definition should express policy explicitly:

```jsonc
{
  "targeting": {
    "mode": "allRegisteredBases",
    "policy": "mandatoryWorldEvent",
    "requiresOnlineOwner": false,
    "onNativeIneligibleBase": "recordFailureAndContinue"
  },
  "invasion": {
    "startBoundary": "simultaneous",
    "declaration": "skip",
    "composition": {
      "mode": "replaceSelectedMembers",
      "profile": "bounty.mixedByGrade",
      "levelPolicy": {
        "mode": "native"
      }
    }
  }
}
```

`simultaneous` means one logical occurrence and no Event Director policy stagger. Palworld may still schedule declarations, pathfinding, or actor spawning over different frames internally.

Health protection should reduce the per-base profile size before it excludes bases. For example, every base can receive one bounty leader rather than only some bases receiving sixteen attackers. An emergency server-health stop remains necessary, but it is a failure response rather than a consent or eligibility rule.

### Chat activation

Alpha.2 provides the fixed command `!siege start <profile>`. The default `operatorOnly` policy resolves the sender's stable player UID against `operatorUids`; display names never authorize a start. An optional `anyUser` policy permits any player to start one allowlisted profile, subject to a persistent global cooldown plus the ordinary active-event, recovery, compatibility, base-count, and native-concurrency guards.

The recommended live policy is operator-direct start and, later, a separately implemented player vote. `anyUser` is useful for a trusted private server but must retain a substantial cooldown. User text can select only fixed profile IDs and cannot supply character IDs, Unreal paths, levels, item IDs, or function names.

The flagship command is:

`!siege start all-bounty`

The `all-bounty` profile attempts to replace every concrete member in each intercepted array Palworld selected. It does not enlarge that array. A deterministic cursor rotates through all 34 audited bounty IDs across base selections; therefore all 34 are attempted when the event supplies at least 34 concrete slots, while a smaller event receives a deterministic subset. The transform leaves native levels, companion fields, counts, waves, pathfinding, lifecycle, and completion context untouched; live tests must prove the game consumes those values as expected.

## Leaderboard and reward decision

### Primary ranking

Use **damage contribution**, not final hits, for the first/second/third individual podium. A final-hit leaderboard is easy to explain and has a strong native signal, but it rewards waiting for the last attack, makes burst timing more valuable than sustained defense, and turns allies into kill-stealing competitors. It also has no natural answer when an invader is captured instead of killed.

The production metric should be target-budgeted effective damage rather than unrestricted raw damage. At spawn, the adapter records one immutable scoreable-health budget $H_t$ from the validated maximum-HP source. The initial profile excludes shields; if a target unexpectedly has a shield, regeneration, a second health bar, or a maximum-HP mismatch, it is unranked and the event degrades to completion-only rewards.

Accepted hit records are deduplicated and consumed in canonical server callback order. For each target, let $e_{p,t}$ be eligible direct or active-Pal damage credited to player $p$, and $u_t$ be all ineligible or unresolved accepted damage. Each hit consumes only the target's remaining budget, so:

$$
\sum_p e_{p,t} + u_t \le H_t
$$

For each event-owned invader $t$:

$$
C_{p,t} = V_t \times \frac{e_{p,t}}{H_t}
$$

and the player's event score is:

$$
S_p = \sum_t C_{p,t}
$$

where:

- $V_t$ is the bounded point value assigned to that target profile;
- $H_t$ is the target's immutable scoreable-health budget for one validated unshielded life;
- $e_{p,t}$ is accepted, deduplicated, non-overkill damage caused by player $p$ directly or by that player's validated active owned Pal, after shared-budget consumption.

Scores use signed 64-bit fixed-point micro-points: each configured $V_t$ is stored as an integer number of $10^{-6}$ points, each $C_{p,t}$ is calculated with integer multiplication/division, and fractional micro-points round down once per target after its ledger closes. Profile validation rejects any actor/base/wave bound that could overflow the event sum. Targets and accepted hits reduce in recorded server sequence order.

Damage from structures, base workers, other NPCs, the environment, or an unresolved source contributes to $u_t$: it consumes the same target health budget but does not become an individual's score. This prevents a one-damage tag from claiming all target points after a turret or unrelated actor does the work. Those sources can still count toward base/guild completion. Any unexplained ledger/HP divergence beyond a validated tolerance makes that target unranked rather than inventing points.

The first ranked profile uses only invasion actors proven noncapturable in this context, avoiding capture-based denial of scoring opportunity. Later capturable profiles must be explicitly unranked or use a separately validated capture-normalization rule. A captured target never fabricates a final hit or allocates its undamaged point budget. Overkill, unrelated targets, friendly fire, and post-resolution callbacks never score.

### Player and Pal credit

The individual podium combines direct player damage with damage from that player's validated active or ridden Pal. `activeAtHit`/`riddenAtHit` and ownership are snapshotted at each accepted hit and applied identically to damage and final-hit credit. Delayed projectiles and status damage use their validated source snapshot; unresolved delayed effects are ineligible rather than guessed. Immediate source identity is retained, allowing separate displayed totals for player damage, Pal damage, and each individual Pal even though the podium rolls them up.

Initially, base-worker Pals and automated defenses contribute to the base/guild outcome rather than an individual podium. Crediting an offline worker's historical owner or a shared structure to one person would be arbitrary and exploitable. That policy can expand only after participation and ownership semantics are proven.

### Final hits and ties

Final hits remain useful, but as a secondary statistic:

- show `Final Hits` beside contribution score;
- use final hits as a deterministic tie-breaker only after exact fixed-point contribution scores tie;
- if score and final hits remain equal, compare distinct targets on which the player consumed at least 5% of $H_t$, then order tied player UIDs lexicographically and apply an occurrence-seeded Fisher–Yates draw whose seed and resulting order are journaled before reward obligations;
- optionally announce an `Executioner` side distinction;
- do not attach the largest item grant to that distinction.

This keeps the satisfying finishing-blow statistic without making kill stealing the dominant strategy. Captures are displayed separately and never masquerade as final hits.

### Reward bands

Use two independent reward layers:

1. **Personal participation:** every assigned player above the configured minimum contribution receives a useful fixed reward even if that base later times out or a health abort ends the event; pure technical-start failure yields no combat participation reward.
2. **Successful-base completion:** eligible defenders of a base that completes its invasion receive a separate fixed reward, including qualifying capture-only defenders in a later capturable profile.
3. **Podium:** first, second, and third by contribution score receive additional exactly-once grants. The value gaps should be meaningful but modest so players still benefit from cooperation.

Native invasion completion rewards, per-actor bounty drops, personal participation grants, successful-base grants, and podium grants are five distinct economic channels. Preview computes a conservative bound from the actual mixed member profile, wave and base caps, maximum configured eligible players, all grant quantities, capture/butchering possibilities, and active drop multipliers. An unknown native reward or multiplier blocks ranked-reward activation. A failed or technically ineligible base cannot create phantom leaderboard points, while a successful defense can still issue completion rewards even if no individual reaches the podium globally.

### Cross-base scramble

The intended fantasy is “protect everything.” Players may move through every active event base, and eligible contribution from all of those bases enters the global individual podium. `Bases Defended` is displayed alongside score so cross-base response is visible rather than treated as an exploit.

All-base incidents can select different levels and stock member counts. Configured point value is therefore target-budgeted rather than raw-HP scoring: fully contributing to one ordinary target has the same bounded value across bases even when native HP differs. A player can earn more by reaching more genuine threats; that is intentional. The director caps bases, targets, runtime, and total reward channels, and rejects targets whose health/identity cannot be validated. Base/guild standings remain a separate table based on completion, survival, and time rather than individual damage.

## Suggested bounty profiles

### Bounty Patrol

- One low/mid-tier bounty leader per base.
- One or two ordinary faction escorts.
- One wave.
- Intended as a frequent token-farming event.
- Completion-only until its capture policy is proven fair for ranked play.

### Bounty Captain

- One selected member per base composition becomes a bounty target.
- Native escorts, levels, companions, counts, and waves remain.
- Preferred first substitution probe because it minimizes economic and AI impact.

### Most Wanted

- Three waves selected by current invasion grade.
- Early bases receive 1-token targets; stronger bases progress to 2–4-token targets.
- Existing companion Pals can be assigned through `Otomo`.

### Kingpin Siege

- One Ram (`BOSS_DarkTrader`) leader per base, optionally with lower-tier bounty escorts.
- Five-token drop per Ram before global drop-rate modifiers.
- Rare calendar event because all-base multiplication makes this economically significant.

### Fugitive Coalition

- Up to five distinct bounty archetypes in a row/profile.
- Dyna and Mite can occupy separate slots and each receive a Tocotoco companion.
- Multiple waves rotate target tiers rather than duplicating one high-value target.

### Bounty Jackpot

- Explicit economy event in which every wave uses 4–5-token targets.
- The event summary must forecast the maximum possible token creation from base count, attackers, waves, capture, and butchering.
- This is allowed if intentional; it should not be an accidental consequence of a generic raid preset.

### Native Alarm

- No member substitution.
- Baseline profile for lifecycle, scoring, performance, and vanilla-client comparison.

## Economy calculation

The upper-bound direct token output is approximately:

$$
T_{kill} = B \times W \times A \times D
$$

where:

- $B$ is the number of bases successfully attacked;
- $W$ is the number of waves;
- $A$ is the bounty actors per wave;
- $D$ is the token drop per actor.

If every actor is captured and later butchered, the community-documented second drop can make the eventual bound approximately:

$$
T_{capture+butcher} \approx 2T_{kill}
$$

before any game modifiers affecting drops or butchering. Event preview should display this bound so the operator can choose deliberately how easy bounty farming becomes.

## Required proof before enabling

1. Call `StartInvaderMarchAll()` on a disposable world with several bases and record every base observer, incident, and failure.
2. Call `Debug_InvaderMarch()` with a known stock `GroupName` and confirm whether it targets all bases; compare `Debug_InvaderMarchForNearCamp()`.
3. Confirm `bSkipInvaderDeclaration=true` bypasses declaration and the Negotiator rather than only hiding UI.
4. Hook `SelectInvaders()` observationally and verify timing, context, output-array meaning, and invocation count.
5. Replace one output member with `BOSS_Hunter_Rifle` before spawn.
6. Connect a completely unmodified remote client and verify name, model, AI, combat, token drop, and reconnect.
7. Test death, capture, and later butchering independently.
8. Verify captured actors count as removed so a wave cannot stall.
9. Verify the stock invasion completion reward and Event Director rewards do not duplicate unexpectedly.
10. Revisit the original overworld bounty and verify its map marker, respawn state, and first-clear state are unchanged.
11. Restart during declaration, every wave, and cleanup.
12. Scale through 2, 4, 8, and the actual maximum base count while recording FPS, frame time, actor count, pathfinding failures, and cleanup.
13. Repeat the final test with each client platform for which vanilla compatibility is claimed.
14. With two same-guild bases whose assigned Work Pals have deliberately different levels, prove native grade and final levels are evaluated independently per base.
15. Run the controlled workforce matrix and classify the native aggregation formula only if the observations distinguish it conclusively.
16. Verify `native`, `fixed`, and positive/negative bounded `relative` policies from selected member through initialized actor level, including every wave and restart boundary.
17. Compare identical scripted damage splits and final-hit orderings; prove that changing only the finishing attacker does not change the primary contribution ranking.
18. Test direct player, active Pal, ridden Pal, base-worker Pal, automated defense, environmental damage, unresolved damage, overkill, capture, and duplicate callbacks against the target health budget.
19. Simulate ties and verify exact contribution, final-hit tie-break, deterministic final fallback, and first/second/third reward settlement.
20. Compare low- and high-grade bases with different native actor counts and prove the configured per-base target-value budget prevents raw-HP opportunity from deciding the global leaderboard.
21. Move players through several event bases during staggered starts; verify all owned event groups score once, unrelated/natural incidents never score, and per-target/base/runtime ceilings bound the intended roaming advantage.
22. Vary capture timing and capturer identity; prove the first ranked profile is noncapturable and later capture policies cannot deny or fabricate ranked points.
23. Inject shields, regeneration, maximum-HP mismatch, duplicate/out-of-order callbacks, and ledger/HP divergence; verify the target becomes unranked rather than exceeding its immutable budget.

## Current conclusion

- **Every-base attack:** probable through `StartInvaderMarchAll()` and directly represented by the manager's per-base observer/incident maps.
- **Mandatory attack:** probable through the direct march path or `bSkipInvaderDeclaration=true`; no Event Director consent layer is required.
- **Choose a stock invader group:** probable-to-high confidence through `Debug_InvaderMarch(GroupName, ...)`.
- **Use bounty targets in a native invasion:** technically strong and supported by the row/member model.
- **Farm Successful Bounty Tokens:** high-confidence probable because the current 34 drop rows key 100% token drops directly to the `BOSS_*` character IDs.
- **Specify exact bounty level:** probable-to-high confidence by setting the final pre-spawn member `Level`; clean-client and boundary tests are still required.
- **Align independently to each base:** native policy should preserve Palworld 1.0's target-base Work-Pal scaling; it is indirect grade/row scaling, not proven exact equality to any worker statistic.
- **Rank the individual podium:** target-budgeted player-plus-active-Pal damage is preferred; final hits are a displayed secondary statistic and tie-breaker rather than the primary score.
- **Preserve original bounty-world progression:** not expected; event copies should be independent of fixed bounty spawners.
- **Vanilla-client safety:** promising with Route A, but not confirmed until the clean-client spike passes.

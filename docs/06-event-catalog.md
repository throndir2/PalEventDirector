# Event catalog

## Purpose

This catalog explores the full creative range of a server-only event director while respecting vanilla clients. It is a design backlog, not a claim that every event currently works.

The strongest events combine existing content in new sequences rather than adding content. A meteor can identify a gathering point, a capture goal can unlock an invasion wave, a race can finish at an oil rig, and a week of personal objectives can culminate in a guild boss night.

## Feasibility legend

| Tier | Meaning |
|---|---|
| **Confirmed foundation** | All essential primitive families have current server-only evidence. Project-specific integration and client testing are still required. |
| **Probable** | Reflected authoritative paths exist; one or more focused adapter spikes are needed. |
| **Experimental** | Pushes instance lifecycle, AI, prediction, temporary rules, or cleanup. Disabled by default until isolated proof and soak tests pass. |
| **Manual/external** | Director schedules, enrolls, messages, and records the event, but a host or external site judges part of it. |
| **Rejected** | Requires client content or an unsafe world mutation and is outside the contract. |

## Reusable event dimensions

Any template can vary across these dimensions:

- **Audience:** individual, random teams, staff teams, guild, everyone cooperative, everyone competitive.
- **Start:** schedule, game time, minimum online count, vote, operator, campaign threshold, prior event result, adaptive director.
- **Duration:** flash event, fixed window, attempt timer, all day, weekend, week, or season.
- **Location:** global, natural landmark, configured zone, base, dungeon, tower, arena, oil rig, meteor/supply impact, route.
- **Objective:** count, distinct set, first-to-N, best result, fastest time, ordered route, survival, occupancy, bracket, staged chain.
- **Presentation:** notice, public chat, private chat, signboard, optional Discord/web page.
- **Reward:** participation, milestone, placement, guild share, raffle, global unlock, delayed grant, text recognition.
- **Difficulty:** fixed profile, progression bands, online-count scaling, recent-performance scaling, or host selection.
- **Failure:** skip, delay, degrade, partial rewards, resolve, or abort/cleanup.

This means a “spotlight capture” family can produce hundreds of safe variants without adding engine code.

---

## Calendar and community events

| ID | Event | Player loop | Needed primitives | Tier |
|---|---|---|---|---|
| COM-01 | Daily Dispatch | Read the day's objectives with `!event`; complete any one for a small reward. | schedule, messaging, objective bundle, rewards | Confirmed foundation |
| COM-02 | Welcome Quest | A newly seen player receives a short private sequence using normal actions: gather, capture, visit. | join, records, private chat, objectives | Probable |
| COM-03 | Event Ballot | Players vote among compatible templates; deterministic tally starts the winner. | chat commands, eligibility, scheduler | Confirmed foundation |
| COM-04 | Community Meter | Every valid action contributes to one server-wide quota with progress announcements. | any observation, global score, messaging | Confirmed foundation |
| COM-05 | Guild Commission Board | Each guild receives the same or seeded-equivalent weekly objectives. | guild lookup, objectives, sign/private chat | Probable |
| COM-06 | Daily Streak | One qualifying contribution per real-world day advances a server-owned streak. | wall clock, player UID, persistence, rewards | Confirmed foundation |
| COM-07 | Newcomer Hour | New or low-progression players receive bounded catch-up objectives and rewards. | records, eligibility, rewards | Probable |
| COM-08 | Returner Weekend | Players absent for a configured period get a private comeback track. | last-seen persistence, objectives, rewards | Confirmed foundation |
| COM-09 | Server Anniversary | Multi-stage retrospective: trivia, community goal, boss finale, recognition. | scheduler, chat, scoring, boss adapter | Probable |
| COM-10 | Happy Hour | A short scheduled modifier plus one matching objective, with clear start/end notices. | modifier lease, scheduler, messaging | Probable per modifier |
| COM-11 | Mystery Envelope | Private seeded objective revealed only to each player; all choices are value-equivalent. | private chat, per-player objectives, seed | Confirmed foundation |
| COM-12 | Chapter Campaign | Daily events unlock a weekend finale and contribute season points. | dependencies, campaign state, templates | Confirmed foundation |
| COM-13 | Server Choice Fork | Completion of one global goal permanently selects one of two later event branches in director state. | campaign state, vote/objective, audit | Confirmed foundation |
| COM-14 | Quiet-Day Autopilot | When population is low, run noncompetitive micro-events instead of cancelling the calendar. | online count, adaptive selection | Confirmed foundation |
| COM-15 | Host's Challenge | An authorized host instantiates an allowlisted objective with bounded parameters. | admin command, validator, scheduler | Confirmed foundation |

## Capture, ecology, and fishing events

| ID | Event | Player loop | Needed primitives | Tier |
|---|---|---|---|---|
| CAP-01 | Pal of the Day | Capture the spotlight existing species; score first, best, or count. | capture attribution, Pal IDs | Confirmed foundation |
| CAP-02 | Element Expedition | Capture distinct Pals from one existing elemental group. | capture, Pal metadata groups | Probable |
| CAP-03 | Biome Safari | Capture an allowlisted set associated with a natural region. | capture, zones/metadata | Probable |
| CAP-04 | Night Hunter | Capture selected nocturnal Pals between native night start and end. | capture, game time | Probable |
| CAP-05 | Dawn and Dusk | Short capture windows around configured game hours. | time events, capture | Probable |
| CAP-06 | Lucky Hunt | First or most valid Lucky captures during a window. | capture rarity/size metadata | Probable |
| CAP-07 | Alpha Album | Capture or defeat distinct existing Alpha/boss variants through normal spawns. | capture/kill classification | Probable |
| CAP-08 | Passive Jackpot | A captured Pal with an allowlisted passive condition wins a tiered prize. | capture parameter/passive inspection | Probable |
| CAP-09 | Safari Diversity | Distinct species matter; repeats give no score. | capture, distinct-set objective | Confirmed foundation |
| CAP-10 | Capture Streak | Consecutive qualifying captures within a rolling time limit; invalid targets reset. | capture, timer, streak | Probable |
| CAP-11 | Sphere Discipline | Capture a target under an allowlisted sphere-tier constraint. | capture plus consumed sphere attribution | Experimental |
| CAP-12 | Guild Field Guide | Guild members collectively fill a seeded species card. | capture, guild snapshot, distinct set | Probable |
| CAP-13 | Natural Outbreak | Announce a naturally common species and score normal wild captures without spawning. | schedule, capture | Confirmed foundation |
| CAP-14 | Directed Outbreak | Spawn bounded groups of an existing species in a safe zone, capturable through normal play. | network spawn, ownership, cleanup | Probable |
| CAP-15 | Rare Migration | Several low-count existing-species groups appear along a route over time. | waves, zones, cleanup | Experimental |
| CAP-16 | Predator Patrol | Defeat configured existing predator bosses or score record deltas. | predator defeat signal/records | Probable |
| CAP-17 | Fishing Derby | Most catches or first-to-N during a fixed window. | fishing result attribution | Probable |
| CAP-18 | Angler's Grand Slam | Catch distinct species/size classes; rare result breaks ties. | fishing details, distinct/best score | Experimental |
| CAP-19 | King of the Lake | Best single valid fishing result during scheduled one-hour heats. | fish size/rarity details | Experimental |
| CAP-20 | Catch-and-Release Honor | Staff/manual honor system or detect safe release behavior if a reliable signal exists. | capture plus release observation | Manual/experimental |
| CAP-21 | No-Repeat Safari | Each player receives a different seeded target and then swaps targets after success. | private objectives, capture, seed | Confirmed foundation |
| CAP-22 | Evolutionary Ladder | Capture target species in ascending level bands; only normal wild captures count. | capture level/source | Probable |
| CAP-23 | Weatherless Migration Story | Use time, biome, and announcements to tell an ecology story without pretending Palworld has a controllable weather API. | schedule, spawn/capture, narrative | Probable |
| CAP-24 | Conservation Balance | Global goal requires captures across several common species rather than farming one. | capture, weighted quotas | Confirmed foundation |

## Combat, bosses, invasions, and instances

| ID | Event | Player loop | Needed primitives | Tier |
|---|---|---|---|---|
| CBT-01 | Base Siege | A scheduled or selected base receives one mandatory native invasion; survive waves for rewards. | base/guild, invasion start/end | Probable |
| CBT-02 | Siege Roulette | A seeded draw chooses a base and invasion profile; no owner registration or consent is required. | base selection, invasion, seed | Probable |
| CBT-03 | All-Base Alarm | Start one mandatory native invasion occurrence against every registered base at the same logical boundary. | invasion-all, health, cleanup | Experimental |
| CBT-04 | Horde Night | Spawn bounded waves of existing hostile Pals/NPCs in a neutral configured zone. | network spawn, AI, zones, cleanup | Experimental |
| CBT-05 | Boss Roulette | Draw an existing field boss and announce its normal location or spawn an approved encounter. | boss metadata, optional spawn | Probable |
| CBT-06 | Boss Rush | Sequential existing bosses, next wave only after owned prior wave resolves. | spawn, defeat attribution, cleanup | Experimental |
| CBT-07 | Alpha Circuit | Defeat normal overworld alphas in a seeded order; no forced reset required. | boss defeat, route/objective | Probable |
| CBT-08 | Tower Time Trial | Measure entry-to-success for a normal player-initiated tower boss. | stage entry, boss success | Probable |
| CBT-09 | Dungeon Sprint | Time normal dungeon entry through boss completion; compare within dungeon bands. | stage/dungeon state, timers | Probable |
| CBT-10 | Dungeon Decathlon | Complete distinct dungeon tiers, captures, and boss kills over a weekend. | dungeon/capture/kill records | Probable |
| CBT-11 | Raid Boss Weekend | Score normally summoned raid bosses and participant/guild completions. | raid start/finish, guild, attribution | Probable observation-first |
| CBT-12 | Directed Raid Night | Director assists native raid lifecycle after complete altar/item/guild flow is proven. | raid manager/network component | Experimental |
| CBT-13 | Oil Rig Assault | Fastest normal oil-rig clear or first goal-crate opening in a window. | oil-rig state, crate/record | Probable |
| CBT-14 | Arena Solo Ladder | Score native solo arena clears and rank bands. | arena/record observations | Probable |
| CBT-15 | Arena Bracket | Register players into native arena rooms and advance a bracket. | arena lifecycle/results | Experimental |
| CBT-16 | King of the Hill | Teams accumulate time in a configured world zone; optional PvP must use native settings. | zones, teams, optional PvP lease | Experimental |
| CBT-17 | Survival Circle | Remain alive and inside a shrinking sequence of preconfigured zones. No custom boundary is drawn. | position, death, zone stages | Probable |
| CBT-18 | Wanted Pal | A seeded existing species/variant is worth bonus defeat points for a short window. | defeat classification, schedule | Probable |
| CBT-19 | Meteor Guardian | A native meteor begins a timed fight against director-owned existing enemies near the event zone. | meteor, spawn, zone, cleanup | Experimental |
| CBT-20 | Escort Caravan | Protect and follow existing spawned NPCs/Pals along waypoints using native AI movement. | spawn, AI move, health, cleanup | Experimental |
| CBT-21 | Glass Cannon Hour | Opt-in combat zone applies an approved damage profile and rewards survival/speed. | setting/status leases, zone | Experimental |
| CBT-22 | Mercy Trial | Defeat targets while an approved mercy/capture condition is active. | combat/capture rule adapter | Experimental |
| CBT-23 | No-Heal Gauntlet | Opt-in run tracks disallowed healing signals and invalidates attempts, rather than blocking client input. | item/status observation, attempts | Experimental |
| CBT-24 | Weapon Class Cup | Score kills with an allowlisted existing weapon class if attacker weapon attribution is reliable. | kill/weapon attribution | Experimental |
| CBT-25 | Pal-Only Cup | Score combat where the credited attacker is a player's Pal. | kill owner/source attribution | Probable |
| CBT-26 | Human-Only Cup | Score player attacks while excluding Pal-attributed defeats. | kill source attribution | Probable |
| CBT-27 | Roaming Champion | One high-level existing Pal is spawned in a safe region with a server-wide warning and expiry. | spawn, level bound, ownership | Experimental |
| CBT-28 | Twin Threat | Two complementary existing boss species spawn together under one encounter budget. | spawn, AI, defeat, cleanup | Experimental |
| CBT-29 | Last Stand | Success requires surviving a bounded wave timer, not killing every actor; survivors are cleaned safely. | waves, survival, cleanup | Experimental |
| CBT-30 | Base Defense League | Guilds earn points from normal or director-started invasion outcomes across a season. | invasion results, guild season | Probable |
| CBT-31 | Bounty Siege | Replace native selected invasion members with grade-appropriate existing `BOSS_*` bounty targets that retain normal token drops. | invasion selection hook, bounty IDs, drops | Experimental |
| CBT-32 | Most Wanted March | Every base receives escalating waves of 1-, 2-, 3-, and 4-token bounty targets. | all-base invasion, bounty profiles | Experimental |
| CBT-33 | Kingpin Siege | Ram (`BOSS_DarkTrader`) leads a mandatory assault on every base for a high-yield five-token event. | all-base invasion, exact bounty member | Experimental |
| CBT-34 | Fugitive Coalition | Up to five distinct bounty archetypes and their existing companion Pals form each native invasion wave. | bounty IDs, `Otomo`, native waves | Experimental |
| CBT-35 | Bounty Jackpot | A deliberately economy-altering all-base raid uses only high-token bounty targets and previews maximum token creation. | bounty profiles, economy preview | Experimental |

## Exploration, travel, races, and treasure events

| ID | Event | Player loop | Needed primitives | Tier |
|---|---|---|---|---|
| XPL-01 | Palpagos Grand Tour | Visit ordered configured landmarks; private messages confirm checkpoints. | positions, zones, ordered route | Confirmed foundation |
| XPL-02 | Open Checkpoint Race | Fastest valid ordered route wins; mounts/gliders remain normal gameplay. | zones, timer, anti-skip checks | Probable |
| XPL-03 | Mount Grand Prix | Race on a staff-tested route with mount presence used only if reliably observable. | zones, timer, optional riding signal | Probable |
| XPL-04 | Glider Rally | Descending checkpoint route; validate route, not client physics. | zones, timer | Probable |
| XPL-05 | No-Fast-Travel Pilgrimage | Complete a route with no observed fast-travel transition during the attempt. | zones, fast-travel/stage observation | Probable |
| XPL-06 | Dungeon Passport | Enter or clear distinct normal dungeons during a week. | stage/dungeon records | Probable |
| XPL-07 | Landmark Scavenger Hunt | Riddles point to configured coordinates/landmarks; proximity confirms finds. | private chat, zones | Confirmed foundation |
| XPL-08 | Signpost Trail | Staff-placed vanilla signs provide clues in sequence. | sign leases, zones | Probable |
| XPL-09 | Treasure Chest Trail | Staff stages vanilla containers/signs; director validates zones and host-reported completion. | zones, optional container observation | Manual/probable |
| XPL-10 | Meteor Chase | Native meteor start defines the destination; first eligible arrival or interaction scores. | meteor, dynamic zone, positions | Probable |
| XPL-11 | Supply Drop Scramble | Reach or complete a native supply incident; reward contribution rather than unsafe ownership stealing. | supply event, positions/completion | Probable |
| XPL-12 | Hide and Seek | Consenting hider registers; seekers score by entering a small proximity zone. | positions, teams, privacy safeguards | Probable |
| XPL-13 | Island Manhunt | One consenting runner gets a head start; hunters receive periodic coarse clues, not exact tracking. | positions, messaging, teams | Probable |
| XPL-14 | Guild Relay | Ordered team members complete different route legs; chat handoff advances the baton. | zones, teams, commands | Confirmed foundation |
| XPL-15 | Courier Contract | Carry an allowlisted existing token item from start to finish without granting transferable economic value. | inventory observation, zones | Experimental |
| XPL-16 | Pilgrim's Calendar | One landmark per day culminates in a weekly route-completion reward. | schedule, zones, persistence | Confirmed foundation |
| XPL-17 | Cartographer Race | First new configured area discoveries or fast-travel unlocks, based on record deltas. | player records | Probable |
| XPL-18 | Rescue Beacon | Reach a stranded consenting host/player or configured NPC zone before timeout. | zones, optional host role | Manual/probable |
| XPL-19 | Compassless Hunt | Coordinates are never given; staged clue messages progressively narrow the zone. | private messaging, zones | Confirmed foundation |
| XPL-20 | Reverse Race | Players visit checkpoints in a personally seeded order, reducing route congestion. | private route, zones, seed | Confirmed foundation |
| XPL-21 | Around the World | Long-duration distinct-region challenge with restorable progress. | zones, persistence | Confirmed foundation |
| XPL-22 | Base-to-Base Rally | Consenting guild bases become route nodes without revealing private coordinates globally. | base/guild lookup, private routes | Experimental/privacy review |
| XPL-23 | Dungeon Exit Dash | Timer begins on boss resolution and ends at normal field return; no forced travel. | dungeon state, stage exit | Probable |
| XPL-24 | Night Orienteering | A route runs only during native night and pauses or fails at sunrise per template. | time, zones | Probable |

## Gathering, crafting, building, and base-life events

| ID | Event | Player loop | Needed primitives | Tier |
|---|---|---|---|---|
| WRK-01 | Mining Mania | Gather selected ores; only validated world gathering counts. | item gathering attribution | Probable |
| WRK-02 | Lumber Run | Gather wood within the event window; transfers and admin grants excluded. | gathering source classification | Probable |
| WRK-03 | Harvest Festival | Collect a weighted basket of crops/ingredients. | gathering/production signals | Probable |
| WRK-04 | Ranch Roundup | Guilds produce selected ranch outputs through normal bases. | production/container attribution | Experimental |
| WRK-05 | Craftathon | Craft distinct or weighted existing items; avoid counting inventory transfers. | craft completion attribution | Probable |
| WRK-06 | Sphere Factory | Craft a tiered quota of existing Pal Spheres. | craft item/count | Probable |
| WRK-07 | Arsenal Drive | Craft ammunition or selected equipment for points, with economic caps. | craft completion | Probable |
| WRK-08 | Great Cake Bake | Craft cakes; personal and guild divisions. | craft completion | Probable |
| WRK-09 | Palpagos Cook-Off | Distinct prepared meals and best timed set; no custom recipes. | craft item IDs | Probable |
| WRK-10 | Angler Supply Drive | Gather/craft existing bait and fishing supplies before a derby. | item gather/craft | Probable |
| WRK-11 | Builder Sprint | Complete allowed vanilla structures in an event zone; dismantle abuse guarded. | build completion, zones | Probable |
| WRK-12 | Settlement Challenge | Guilds complete a balanced list of allowed structure categories. | build IDs, guild snapshot | Probable |
| WRK-13 | Repair Rally | Restore damaged existing structures through normal play if repair events can be observed. | repair observation | Experimental |
| WRK-14 | Cleanup Day | Destroy/dismantle player-owned abandoned structures under host/guild rules; never auto-destroy unknown ownership. | dismantle observation, ownership | Manual/experimental |
| WRK-15 | Guild Donation Drive | Deposit allowlisted resources into a registered vanilla container; count net contributions. | container operations, guild | Experimental |
| WRK-16 | Production Relay | One crafted output unlocks the next category in a staged server goal. | crafting, staged objective | Probable |
| WRK-17 | Worker Wellness Week | Reward guilds for maintaining healthy/sane base Pals if safe aggregate readings exist. | base worker status snapshots | Experimental |
| WRK-18 | Incubation Weekend | Lease a tested egg-timer setting and pair it with hatching objectives. | modifier, hatch observation | Experimental |
| WRK-19 | Breeding Bonanza | Lease tested breeding behavior or score normal breeding completions. | breeding completion/modifier | Experimental |
| WRK-20 | Fast Hands Hour | Bounded work-speed modifier with craft objective and deterministic revert. | modifier lease, crafting | Experimental |
| WRK-21 | Decay Holiday | Temporarily reduce a validated deterioration setting, then restore exactly. | setting lease | Probable per setting |
| WRK-22 | Restoration Project | Server-wide gathering/crafting tiers represent rebuilding after a narrative crisis. | multiple item objectives | Probable |
| WRK-23 | Zero-Waste Challenge | Score crafted outputs relative to selected gathered inputs using event-window deltas. | gather/craft ledger | Experimental |
| WRK-24 | Base Census | Noncompetitive event recognizes base creation, worker count, or guild milestones without mutating them. | base and guild reads | Probable |
| WRK-25 | Power Hour | Score existing electrical production/use signals if a reliable low-cost source is found. | base component observation | Experimental |
| WRK-26 | Ranch Bingo | Produce one of each item on a seeded vanilla ranch card. | production item IDs | Experimental |

## Social games and chat-driven events

| ID | Event | Player loop | Needed primitives | Tier |
|---|---|---|---|---|
| SOC-01 | Pal Trivia | First valid chat answer scores; aliases and answer windows are predefined. | chat, rounds, rate limit | Confirmed foundation |
| SOC-02 | Riddle Chain | Solve clues that alternate chat answers and location checkpoints. | chat, private messaging, zones | Confirmed foundation |
| SOC-03 | Simon Says | Follow safe movement/location/chat instructions; host or simple signals judge. | chat, zones, optional movement | Manual/probable |
| SOC-04 | Red Light, Green Light | Position samples during red invalidate movement beyond latency tolerance. | zones, position sampling | Experimental |
| SOC-05 | Musical Statues | Move between zones while music is represented by announcements/timers; no custom audio. | messaging, positions, rounds | Probable |
| SOC-06 | Tag | A proximity event transfers server-owned “it” state; no combat mutation required. | positions, teams/state | Probable |
| SOC-07 | Freeze Tag | Tagged players are marked in event state and must remain in a zone; actual input freezing is optional and experimental. | positions, state; optional input adapter | Probable without forced freeze |
| SOC-08 | Hot Potato | A chat or proximity handoff transfers a virtual event token before timeout. | commands/positions, timer | Confirmed foundation |
| SOC-09 | Secret Target | Each player gets another participant or objective privately; valid interaction scores. | private chat, seed, observation | Probable |
| SOC-10 | Capture Bingo | Personal or shared 3×3 card of existing species/traits. | capture, seeded cards | Confirmed foundation |
| SOC-11 | Crafting Bingo | Seeded card of existing craftable items. | crafting observation | Probable |
| SOC-12 | Pal Draft Cup | Players draft existing species through chat, then compete under host/native arena rules. | chat draft; arena/host result | Manual/experimental |
| SOC-13 | Raffle Night | Contributions buy only virtual event entries; seeded auditable draw grants capped rewards. | scoring, deterministic raffle, rewards | Confirmed foundation |
| SOC-14 | Auction House Night | Host-run chat auction with optional item verification; automatic escrow is deferred. | chat, inventory reads, host | Manual |
| SOC-15 | Pal Parade | Players meet in a zone with a chosen existing Pal; host awards categories. | zone, selected Pal read, host judging | Manual/probable |
| SOC-16 | Base Showcase | Schedule tours and ballots; judging is manual or external, rewards are director-managed. | schedule, vote, rewards | Manual/external |
| SOC-17 | Screenshot Safari | External submissions, director registration and awards; participation remains possible without software. | sidecar/host, rewards | Manual/external |
| SOC-18 | Guess the Pal | Progressive textual clues; first normalized answer scores. | chat, rounds | Confirmed foundation |
| SOC-19 | Twenty Questions | Players collectively query an allowlisted clue set to identify a Pal. | chat state machine | Confirmed foundation |
| SOC-20 | Guild Feud | Survey-style Palworld questions with team rounds and chat buzzers. | teams, chat, scoring | Confirmed foundation |
| SOC-21 | Scavenger Relay | Each team member receives a different private clue and must hand off. | private chat, zones, teams | Confirmed foundation |
| SOC-22 | Secret Gift Week | Director privately pairs consenting players; gifts are manual, completion is acknowledged. | registration, seed, private chat | Manual |
| SOC-23 | Story Choice Night | Chat votes branch a scripted narrative into different native events. | votes, phase graph, event actions | Probable |
| SOC-24 | Last Pal Standing Predictions | Spectators predict an approved boss/wave outcome; no wagering of real inventory. | chat, encounter result | Probable |

## Progression, rewards, and economy events

| ID | Event | Player loop | Needed primitives | Tier |
|---|---|---|---|---|
| PRG-01 | Daily Login Gift | One bounded reward per player UID per real-world day. | join, wall clock, reward ledger | Confirmed foundation |
| PRG-02 | Attendance Calendar | Milestones for distinct active days, with grace and no pay-to-win rewards. | persistence, rewards | Confirmed foundation |
| PRG-03 | Playtime Milestones | Active online time, excluding obvious AFK if a fair signal is proven. | roster/time, optional activity | Probable |
| PRG-04 | First Contribution | First qualifying event action each day gives a small reward. | objectives, reward ledger | Confirmed foundation |
| PRG-05 | Technology Scholarship | Completion grants bounded existing technology points through a validated path. | technology data, rewards | Probable/high persistence risk |
| PRG-06 | Relic Recognition | Native relic acquisitions contribute to milestones; direct relic grants remain separately gated. | relic record delegates | Probable |
| PRG-07 | Paldeck Marathon | Reward new species discoveries during a season using before/after record state. | Paldeck records | Probable |
| PRG-08 | Boss Passport | Distinct normal boss victories fill a persistent director passport. | boss records | Probable |
| PRG-09 | Dungeon Passport | Clear-count and distinct-stage achievements over a season. | dungeon records/stage IDs | Probable |
| PRG-10 | Catch-up Contract | Low-progression players choose one effort-based path for bounded aid. | record eligibility, objectives | Probable |
| PRG-11 | Personal Daily Commission | Deterministic per-player objective selected from equivalent difficulty bands. | private chat, templates, seed | Confirmed foundation |
| PRG-12 | Weekly Challenge Track | Several event families award director points toward reward tiers. | campaign state, reward caps | Confirmed foundation |
| PRG-13 | Guild Season | Guild results across events form a season table with roster-lock policy. | guild snapshots, campaign scoring | Probable |
| PRG-14 | Hall of Fame | Persist text-only champions and expose via commands/sign/web. | archives, messaging/sign | Confirmed foundation |
| PRG-15 | Underdog Bonus | Seeded lower-ranked participants receive score multipliers, not stronger game stats. | historical rank, scoring | Confirmed foundation |
| PRG-16 | Comeback Mechanic | Trailing teams unlock alternate bonus objectives rather than free score. | live standings, objective graph | Confirmed foundation |
| PRG-17 | Participation Pity | Repeated participation without placement gradually increases a capped raffle chance. | persistence, deterministic raffle | Confirmed foundation |
| PRG-18 | Mystery Crate Reward | Choose from allowlisted existing reward tables; grant directly instead of spawning an unknown container. | reward tables, item grant | Confirmed foundation |
| PRG-19 | Guild Treasury Goal | Virtual contribution points unlock equal member rewards; no automatic inventory removal initially. | objectives, guild, rewards | Probable |
| PRG-20 | Insurance Weekend | A participation reward offsets normal losses; never edits death drops retroactively. | death observation, item rewards | Probable |
| PRG-21 | Mentor Contract | Veteran and newcomer are paired for shared milestones; both must contribute. | eligibility, private teams | Confirmed foundation |
| PRG-22 | Server Renown | All events feed a non-gameplay server level that unlocks future templates, not custom content. | campaign persistence | Confirmed foundation |

## Seasonal, spectacle, chaos, and adaptive events

| ID | Event | Player loop | Needed primitives | Tier |
|---|---|---|---|---|
| SEA-01 | Night of Falling Stars | Several bounded native meteor events occur across a long window with cooldowns. | meteor adapter, health, concurrency | Experimental |
| SEA-02 | Endless Night | Lease world time/progression for a nocturnal hunt, then restore precisely. | clock lease, time/capture | Experimental |
| SEA-03 | Longest Day | Extend daylight using a validated time-speed setting, paired with exploration goals. | clock modifier, zones | Experimental |
| SEA-04 | Abundance Weekend | Lease tested collection/drop multipliers and run a global gathering goal. | setting leases, gathering | Probable per setting |
| SEA-05 | Lean Times | Narrative survival challenge using modest hunger/resource settings; opt-in if effects cannot be scoped. | setting leases | Experimental |
| SEA-06 | Capture Frenzy | Bounded capture-rate lease plus species objectives. | capture modifier, capture | Experimental/client UI review |
| SEA-07 | Breeder's Moon | Night schedule plus breeding/incubation objectives and carefully tested modifiers. | time, breeding, modifiers | Experimental |
| SEA-08 | Randomizer Weekend | Use Palworld's native randomizer settings only through a planned restart and dedicated test world/campaign. | config profile, restart, randomizer | Experimental/high save impact |
| SEA-09 | Invasion Marathon | Mandatory native base invasions occur in scheduled rounds with recovery breaks. | invasion lifecycle, health | Experimental |
| SEA-10 | World Boss Hour | Spawn one approved existing champion with global notices and strict expiry. | network spawn, cleanup | Experimental |
| SEA-11 | Chaos Wheel | Players vote; director draws one of several prevalidated, nonconflicting micro-modifiers/events. | vote, deterministic selection, leases | Probable |
| SEA-12 | Festival Week | Seven themed daily templates feed one cooperative finale. | campaign, multiple adapters | Probable |
| SEA-13 | Blackout Trek | Temporarily disable or discourage fast travel only if the native setting/request behavior is safe and reversible. | fast-travel adapter, routes | Experimental |
| SEA-14 | Revival Rally | Tested revive/healing rules support repeated cooperative combat with low penalty. | revive modifier/action | Experimental |
| SEA-15 | Adaptive Crisis Director | Select invasion, hunt, supply, or gathering events based on players, progression, recency, and health. | policy engine, capability pool | Probable after components mature |
| SEA-16 | Population Pulse | Flash events appear only when online count crosses thresholds and cooldowns allow. | roster, scheduler | Confirmed foundation |
| SEA-17 | Boss of the Hour | Rotate a normal target or controlled existing spawn every hour. | scheduler, boss metadata/spawn | Probable/experimental by mode |
| SEA-18 | Eclipse Narrative | Announcements and fixed-night lease create an “eclipse”; no custom sky assets are claimed. | clock lease, messaging | Experimental |
| SEA-19 | Meteor-to-Siege Chain | Meteor completion opens a capture stage, then a mandatory base-invasion finale. | meteor, capture, invasion | Experimental compound |
| SEA-20 | Server Versus Director | Adaptive waves scale only inside tested bounds based on completion speed and health. | spawn, scoring, health | Experimental |
| SEA-21 | Mercy Season | Season scoring rewards captures, nonlethal objectives, and community goals over kills. | capture/objectives/campaign | Probable |
| SEA-22 | Expedition Season | Region routes, dungeons, fishing, oil rigs, and bosses award passport points. | broad observation set | Probable after adapters |
| SEA-23 | Guild Wars Season | Native PvP/arena results and non-PvP guild challenges combine under roster locks. | guild, arena/PvP, campaign | Experimental |
| SEA-24 | Rest Day | No competition: free healing, social games, tours, and catch-up contracts. | messaging, heal/rewards | Probable |

---

## Detailed flagship designs

### 1. Meteor Safari

**Fantasy:** A falling star reveals an unusual migration. Players race to the impact region, capture a spotlight species, then defeat guardian Pals.

**Phases:** announce → impact → travel → capture quota → guardian wave → resolution → cleanup.

**Scoring:** cooperative global capture goal; personal contribution; guardian participation. A seeded raffle among contributors prevents only the highest-level player from benefiting.

**Safety:** one native meteor at a time, bounded dynamic zone, no spawning until the impact is valid, owned guardian handles, expiry, pause spawns on poor server health.

**Fallback:** if meteor initiation is unavailable, announce a natural safari at a configured landmark and omit the impact race.

### 2. Siege League: Siege Saturday

**Fantasy:** The island declares every base a target for a native invasion league.

**Phases:** global warning → base snapshot → simultaneous native invasion starts → native waves → recovery interval → standings.

**Scoring:** the individual podium aggregates target-budgeted effective damage from the player plus their validated active owned Pal across every event base they reach. `Bases Defended` rewards the “protect everything” scramble. Final hits are shown separately and break an otherwise equal contribution score; they do not drive the leaderboard. The initial ranked profile does not use capturable invaders. Base/guild standings still use survival, waves completed, completion time, and an optional no-player-death bonus. Base wealth or destruction amount is not used because it could incentivize unsafe builds or griefing.

**Rewards:** every player meeting a bounded contribution threshold receives a personal participation reward. Successful bases receive a separate defender-completion reward. First, second, and third receive additional exactly-once podium grants with deliberately modest gaps. Native invasion rewards and bounty drops remain separate. An optional “Executioner” announcement can recognize the most final hits without attaching the largest economic reward to kill stealing.

**Safety:** no consent or online-owner filter; every registered base is attempted. Technical failures such as an unavailable base model, blocked start point, or native cooldown are recorded. Per-base wave size is reduced before any base is omitted, and no cleanup operation touches unknown invaders.

**Bounty variant:** before native member spawning, replace selected members with existing bounty `BOSS_*` character IDs. Their current drop rows grant Successful Bounty Tokens at 100%. See [the mandatory invasion and bounty design](11-invasion-and-bounty-design.md).

### 3. Palpagos Grand Tour

**Fantasy:** A no-download island rally using natural landmarks and private checkpoint confirmations.

**Phases:** registration → private route assignment → synchronized start → ordered checkpoints → finish → verification.

**Scoring:** fastest valid route, clean-run bonus, team relay division. Different seeded route orders reduce crowding.

**Safety:** no forced movement, no custom markers, broad checkpoint hysteresis, impossible-speed samples flag review rather than auto-ban, instance/teleport transitions invalidate only when rules say so.

### 4. Guild Expedition League

**Fantasy:** A month-long league in which every style of play helps a guild.

**Weekly divisions:** safari, production, exploration, combat, fishing, and community service.

**Scoring:** normalized points with per-category caps prevent one industrial base or high-level fighter from dominating. Guild roster is snapshotted weekly. Personal contributions are visible privately.

**Finale:** top guild chooses one of several equivalent server-wide events; all players receive the global completion reward.

### 5. Night of Falling Stars

**Fantasy:** A rare spectacle night with meteor incidents at long, deterministic-jittered intervals.

**Loop:** announcements provide broad region clues; players locate events, complete native objectives, and collect virtual stamps. A final stamp threshold triggers one approved champion encounter.

**Safety:** supply-system exclusive lease, strict incident count/cooldown, active-event reconciliation, server entity/FPS gates, and no new impact if prior state is unresolved.

### 6. Dungeon Decathlon

**Fantasy:** Players earn points from ten dungeon-related feats rather than repeating one fastest route.

**Objectives:** enter distinct tiers, defeat bosses, capture a dungeon boss where native behavior permits, clear without death, complete a daily dungeon, and set a personal best.

**Fairness:** compare times only within the same dungeon identity/tier; no forced resets; use record deltas for reconciliation.

### 7. Island Restoration Project

**Fantasy:** A server-wide narrative campaign after a fictional disaster.

**Stages:** gather raw materials → craft tools/food/spheres → establish approved structures → defend a designated base → celebration hunt.

**Implementation:** all progress is virtual director state derived from normal actions. Resources are not removed automatically in the first version. This prevents inventory-loss bugs while preserving the cooperative story.

### 8. Adaptive Crisis Director

**Fantasy:** The island reacts to the current population without becoming unfair or unpredictable.

**Inputs:** online count, progression bands, recent templates, time of day, server FPS/frame time, unresolved claims, and current native-system availability.

**Choices:** micro safari, supply chase, community meter, mandatory invasion, route, trivia, or controlled wave. Each choice has minimum/maximum scale and cooldown.

**Non-goal:** machine-learning difficulty or unconstrained generation. Selection is deterministic policy over an approved template pool and recorded seed.

### 9. Story Choice Night

**Fantasy:** Players collectively direct a branching adventure through votes and achievements.

**Example branches:** investigate a meteor or defend a settlement; track a rare Pal or raid an oil rig; choose a capture finale or boss finale.

**Implementation:** narrative is text, branches are event graph nodes, and every gameplay action uses existing systems. A branch unavailable under current adapter health is removed before voting.

### 10. Server Versus Director

**Fantasy:** Cooperative players survive escalating rounds while the director responds to success.

**Scaling:** wave count and level select from discrete tested profiles using online count and prior completion time. There is no arbitrary runtime formula beyond policy bounds.

**Stop conditions:** poor server health, too many unresolved actors, participant withdrawal, timeout, or cleanup uncertainty. The director declares a draw and preserves earned participation rewards rather than pushing through failure.

---

## Event composition recipes

| Recipe | Composition |
|---|---|
| Hunt | schedule + target selector + capture/defeat observation + count/distinct score + reward |
| Outbreak | hunt + network spawn profile + dynamic zone + ownership cleanup |
| Race | registration + ordered zones + timer + anti-skip policy + placements |
| Relay | race + teams + per-leg participant + explicit handoff |
| Defense | scheduled/selected/all-base target + native invasion/waves + survival/kill objective + health gate |
| Passport | persistent distinct-set objectives across event families |
| Community drive | global weighted objective + progress thresholds + everyone/contributor reward |
| Tournament | registration + seed + rounds + native/host result + bracket archive |
| Story | directed phase graph + votes/objectives + adapter-aware branches |
| Festival | calendar of child occurrences + campaign points + finale dependency |
| Adaptive flash | online/health trigger + cooldown + approved micro-template selection |
| Treasure hunt | private clues + zones/signs + ordered objective + bounded hints |

## Fairness patterns

- Separate progression bands when level or gear dominates outcomes.
- Prefer personal best improvement, contribution thresholds, raffles, or cooperative goals over winner-takes-all.
- Cap repeat scoring from the same species, item, spawner, container, or action source.
- Snapshot guild rosters at declared boundaries.
- Require opt-in for forced teleportation, PvP, movement/input changes, or inventory-affecting rules. Base invasions are mandatory world events and do not use consent.
- Publish tie resolution before the event; use recorded deterministic seeds.
- Never rely on display names as identity.
- Do not reward actions that can be generated by the reward system itself.
- Mark staff-judged events clearly and retain the ruling in the audit record.

## Abuse controls by family

| Family | Typical abuse | Control |
|---|---|---|
| Capture | Director-spawn farming, repeat capture, admin spawn | Source classification, instance dedupe, allowlisted spawn eligibility. |
| Kill | Friendly/environmental credit, summon farming | Attacker/owner attribution, target origin, cooldown/dedupe. |
| Gather | Chest transfer or dropping/re-picking | Require validated gather source; use net/source-specific counters. |
| Craft | Craft/cancel loops or reward recursion | Count completed output once; exclude director-granted inputs/outputs where needed. |
| Build | Build/dismantle loop | Object identity dedupe, category caps, completion only, optional persistence duration. |
| Race | Teleport, reconnect, route skip | Ordered checkpoints, travel signals, attempt invalidation/review. |
| Zone | Boundary jitter/AFK | Hysteresis, minimum continuous dwell, activity rule if fair. |
| Login | Reconnect spam | One UID/day/occurrence ledger key. |
| Vote/chat | Multi-message spam | One ballot/UID, cooldowns, bounded parser. |
| Guild | Mid-event switching | Roster snapshot and minimum contribution. |

## World staging without client mods

Some events improve with staff-created vanilla infrastructure:

- Signboards registered as event boards or clue boards.
- Clearly named vanilla storage containers for manual donation events.
- Race start/finish landmarks and routes tested for traversal.
- A neutral arena built through normal construction.
- Safe spawn zones away from bases, fast-travel points, restricted volumes, and new-player starts.
- Recovery points for opt-in teleport events.

The director may update known sign text or observe known objects. It does not spawn these build objects itself.

## Ideas intentionally rejected

| Idea | Reason |
|---|---|
| Custom event boss or new Pal species | Vanilla clients do not know the new class/data/assets. |
| Custom event currency/item/recipe | Unknown item/data identity and save/UI dependency. Use virtual director points plus existing rewards. |
| Custom dungeon/map/island | Requires client cooked content. |
| Custom in-game calendar, HUD, scoreboard, quest log, or marker | Requires client UI/content. Use chat, notices, signs, or optional web views. |
| Custom event music, voice lines, icons, models, or VFX | Requires client assets. Existing native effects may only be reused through validated native actions. |
| Dynamic server-spawned event buildings | No safe general build-request context is proven; a bare call has caused server aborts. Staff pre-place vanilla structures. |
| Arbitrary low gravity or movement physics | Client prediction/desync risk and no established safe adapter. |
| Forced inventory confiscation/escrow | High loss/duplication risk. Start with observation and voluntary/manual transfer. |
| Unbounded all-base attacker multiplication | Mandatory all-base invasions are allowed, but an uncapped actor/pathfinding burst can crash the server. Scale composition per base and test the actual maximum base count. |
| Permanent hardcore/permadeath event on the main world | Disproportionate save risk. Use non-destructive scoring or an isolated world. |
| Automatic punishment/ban from race telemetry | Event sampling is not anti-cheat evidence. Flag for review only. |
| Arbitrary reflected function console | Bypasses capability validation, bounds, authorization, and cleanup. |

## Catalog rollout strategy

1. Release observation and messaging families first.
2. Add rewards with exactly-once delivery.
3. Add position/zone events.
4. Add normal-play boss/dungeon/fishing/oil-rig scoring.
5. Add one existing-character spawn profile and prove cleanup.
6. Add native meteor and one mandatory invasion, then prove all-base scope and bounty-member substitution.
7. Add setting leases one property at a time.
8. Add compound and adaptive templates only after each primitive has independent soak evidence.
9. Keep arena forcing, directed raids, AI escort, and mass invasion experimental until their full native lifecycle is understood.

The breadth of the catalog should come primarily from composition. The number of engine adapters should remain deliberately small, reviewed, and testable.

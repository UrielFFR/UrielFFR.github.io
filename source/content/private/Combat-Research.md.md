[FFResonanceCodex Source](https://ffresonancecodex.com/reference/combat-research.md)
## FINAL FANTASY RESONANCE DEMO: attack formula

Static reconstruction from the installed Steam demo, app 4474710, build 24032336. Examined 2026-09-07. This describes ordinary physical and magical HP damage. Fixed damage, HP-percentage damage, defense-ignoring skills, healing, and scripted overrides have separate paths. The equations below omit tiny floating-point epsilon terms where noted; this is an explanatory reference, not a bit-exact battle simulator.

## Ordinary damage

For a hit that lands, before special caps, minimum-damage handling and overrides:

```
r = effective attack / max(effective defense, 1)

F(r) = 0.5*r                       if r < 0.5
       r*r                         if 0.5 <= r < 1
       8/(1 + exp(1-r)) - 3         if r >= 1

raw damage for hit i = 0.6*(effective attacker level + 2)
                     * F(r)
                     * effective skill power
                     * random damage factor
                     * elemental damage factor
                     * critical damage factor
                     * staggered-target factor
                     * other applicable multipliers
                     * hit weight[i]
```

Ordinary positive damage is ultimately truncated to an integer. A configured minimum-one rule is applied before some later defensive effects, and a final damage cap can apply. Therefore simply wrapping this entire expression in `max(1, floor(...))` is not a faithful implementation of all cases.

The attack and defense inputs are the resulting combat attributes after applicable effects, not raw Strength or Stamina:

| Damage calculation | Attack input | Defense input |
|---|---|---|
| Physical | Physical attack | Physical defense |
| Magic | Magic attack | Magic defense |
| Light magic | Sanctity-derived attack | Magic defense |

Special effects can substitute the higher attack or defense attribute. Attacker level is itself read through a getter that applies an effective-level modifier.

| Attack / defense | Stat factor F(r) |
|---:|---:|
| 0.25 | 0.125 |
| 0.5 | 0.25 |
| 0.75 | 0.5625 |
| 1 | 1 |
| 1.5 | 1.9797 |
| 2 | 2.8485 |
| 3 | 4.0464 |
| 5 | 4.8561 |

The ratio contribution approaches 5 as attack becomes much larger than defense. That limits this factor, not total damage: level, power and other multipliers still act separately. Equal attack and defense gives the same ratio contribution whether both are 100 or both are 1,000.

Effective skill power has its own modification stage:

```
P = base skill power * (1 + applicable attacker power modifiers
                         + applicable target power modifiers)
    + applicable flat power additions
```

These modifiers are the values returned by the effect handlers, not an assumption that every UI percentage is stored identically. Base power is used directly: Lasswell's normal attack has power 12, and this stage does not divide it by 100. Certain special calculation types then modify P further.

## Three different random rolls

The executable imports the CRT functions `rand` and `expf`. Each relevant draw masks the returned random integer with `0x7fff`, producing N in 0..32767. The three formulas use separate calls; the same N is not reused among all three stages. Probability calculations below assume uniformly distributed masked draws and do not claim independence of a pseudorandom generator or measured in-game frequencies.

### Damage variance

```
V = 1 - s + (2*s*N)/32767
s = 0.05

V is approximately 0.95 through 1.05
```

Thus the underlying damage can vary by +/-5%, before integer truncation. Its mean multiplier is approximately 1. This roll does not cause a critical; critical damage is another multiplier. The actual float32 endpoints are 0.9499999881 and 1.0499999523.

### Critical check

```
T = skill's criticalHitRate + sum(applicable critical-rate bonuses)
Rcrit = 1 + N*(99/32767)
critical succeeds when T >= Rcrit
```

Rcrit is fractional, not rounded to an integer. Away from the endpoints, its success probability is approximately `(T-1)/99`, limited to 0..1. Float32 enumeration gives:

| Configured threshold T | Successful draws / 32768 | Predicted probability |
|---:|---:|---:|
| 0 | 0 | 0% |
| 1 | 1 | 0.00305% |
| 2 | 331 | 1.01013% |
| 3 | 662 | 2.02026% |
| 22 | 6951 | 21.21277% |
| 100 | 32768 | 100% |

Lasswell's normal attack starts at T=2. An applicable +20 bonus makes T=22, not 2.4. Because of the fractional 1..100 roll, adding 20 to the threshold corresponds to approximately 20.20 percentage points of actual chance in the uncapped region, not exactly 20.

The ordinary critical damage factor is `150 * 0.01`, approximately 1.5, plus applicable critical-damage effects. Normal noncritical damage has factor 1. Calculation flags and resistance/other eligibility checks can disable critical handling. Critical, elemental weakness and stagger are distinct mechanics.

### Hit / miss

The native diagnostic labels explicitly identify base accuracy, added accuracy, evasion, resistance, final hit rate and random value. In the ordinary applicable path:

```
Ev = min(sum(applicable evasion effects), 75)
H = truncate(clamp(skill accuracy + accuracy additions - Ev, 0, 100)
             * (1 - relevant resistance/100))

Rhit = 1 + min(99, truncate(N*(100/32767)))
attack misses when Rhit > H
```

The actual code adds a float epsilon to the resistance factor before truncation. Unlike the critical roll, Rhit is an integer from 1 to 100. This makes H approximately a percentage chance, with slight discrete-bin bias. At H=100, every possible draw succeeds; at H=0, none succeeds.

The resistance term is looked up from the target's resistance map using the skill's `statusCondition`; it is not the elemental damage multiplier. Ordinary attacks without an applicable status resistance have this term zero. Evasion's configured cap is 75. Some skill categories bypass the accuracy/evasion modifier collection. Full relevant resistance and forced avoidance are separate branches. The staggered-target branch explicitly bypasses the random hit check and marks a hit, after the full-resistance check.

Lasswell's normal attack has base accuracy 100, so it hits on every ordinary accuracy roll if there are no relevant accuracy reductions, evasion or special overrides.

## Damage multipliers and separate stagger damage

| Factor | Ordinary configured value |
|---|---:|
| Neutral element | 1 |
| Elemental weakness | 1.5 |
| Halved elemental damage | 0.5 |
| Elemental immunity | 0 |
| Critical | 1.5 |
| Target already staggered | 1.5 |
| Additional phase damage factor | 1.0 |
| All-target scaling, when the skill's `isApplyAllMag` flag applies | 0.4 |

An eligible critical against an elemental weakness on an already staggered target can therefore contribute `1.5*1.5*1.5 = 3.375` times the corresponding neutral, noncritical, unstaggered damage, before other effects. The all-target multiplier must not be applied indiscriminately to every area attack: its skill flag and effect overrides matter.

Absorption uses a negative resistance marker with separate handling; the main calculation uses its absolute magnitude. Reflection and other overrides also have explicit branches. Treat these as special outcomes, not ordinary negative HP damage from the displayed equation.

Other applicable multipliers include defensive effects, damage bonuses, configuration scalars for player attackers/targets, caller-provided scaling and artifact-specific behavior. Two configuration scalars are read at offsets 0x18/0x1c by helpers 0x14510b100/0x14510b0c0, with fallback 1. Their full runtime configuration ownership was not established, so they are deliberately not assigned an assumed difficulty-setting name here.

HP damage and stagger-bar damage are separate outputs. Skills have an independent `breakDamageValue`; Lasswell's normal attack stores 25. The stagger resistance table uses weakness multiplier 3 rather than the HP damage table's 1.5. A complete stagger-bar formula, including its effect handlers, was not reconstructed in this pass; do not use the HP formula as its substitute.

## Worked example using Lasswell's attack data

Assume effective level 10, physical attack 100, target physical defense 100, neutral element, no critical, target not staggered and all other factors 1. The level and stats here are illustrative, not a read of the player's save.

Lasswell's normal attack has power 12, two hits and weights 0.5/0.5. Its serialized weight array contains 31 slots, with the remaining 29 zero.

```
F(100/100) = 1
unweighted baseline = 0.6*(10+2)*1*12 = 86.4
each hit before variance = 86.4*0.5 = 43.2
each noncritical hit with variance = 41.04..45.36
each ordinary displayed hit after truncation = 41..45
```

The two noncritical hits therefore total 82..90 if both land under these assumptions. A critical hit's own raw interval becomes 61.56..68.04, or 61..68 after truncation. The damage routine accepts a hit index and uses its corresponding weight; both hit and critical calculations are located in per-hit processing. This reference does not simulate RNG call order across a whole battle.

## Native evidence and reproducibility

All addresses below use preferred executable image base 0x140000000. Files are in this directory.

| Evidence | Native address / source |
|---|---|
| Ratio curve, level factor, variance | `attack-base-and-resistance.txt`, 0x145222890..0x145222af6 |
| expf / rand import resolution | `resolve-math-imports.py`; IAT 0x147726bc8 / 0x147727140 |
| Physical/magic dispatcher | `attack-helper-ranges.txt`, 0x14522b5d0 |
| Effective power | `attack-helper-ranges.txt`, 0x1452319c0..0x145231bc4 |
| Main multiplier chain, crit comparison, hit weights, truncation, caps | `critical-calculation.txt`, 0x14522623b..0x145226978 |
| Crit damage multiplier | `critical-multiplier-function.txt`, 0x14522c500 |
| Hit calculation | `hit-function.txt` and `attack-final-details.txt`, 0x145227464..0x145227835 |
| Hit resistance map and effective level getter | `hit-modifiers.txt`, 0x1452312d0 and 0x144faec80 |
| Japanese diagnostic labels explaining hit variables | `attack-labels.py`, strings at 0x14894c7e0 and 0x14894c760 |
| Configuration constants and native offsets | `unit-parameter-calc.json`, decoded from DT_UnitParameterCalc |
| Lasswell normal attack data | `lasswell-skill-rates.json`, DT_SkillData row at .uexp offset 32090 |
| Weight array | DT_SkillData.uexp offset 32158, count 31, first two floats 0.5 |
| Enumeration and numeric examples | `verify-attack-formula.py` and `attack-arithmetic-checks.json` |

The simplified ratio curve omits a float epsilon of 2^-23 added to r, and another added in the r<0.5 branch. Percentage multipliers also sometimes receive this epsilon. Native expf and float32 operation order can affect values near truncation boundaries. No live combat measurement or game-file changes were performed.


---

# Calculator equipment, vision, and stat rules

Read-only reconstruction of the installed FINAL FANTASY RESONANCE DEMO, Steam build 24032336, 2026-09-07. Native addresses below are virtual addresses in `FFRS-Win64-Shipping.exe`. No game process, save, or installed file was modified.

## Rules ready to implement

### Equipment capacity and compatibility

- One weapon, one armor, **two accessories**, one equipped vision.
- `GetEquipSlotNum`'s reflected execution thunk at `0x144d68e50` calls `0x14522da30`. That function returns 0 for equipment type None (0), 2 for Accessory (3), and 1 for every other nonzero type. `wiki-enums.json` maps types 1 Weapon, 2 Armor, 3 Accessory, 4 Vision.
- Character weapon and armor compatibility comes directly from the eight decoded `DT_PlayableUnitData` rows (`wiki-decoded.json.playable` and `wiki.json.characters[].weaponType/armorTypes`). Honor item `equipmentLimitSex` too. Compatibility-granting passives can expand legal equipment; an optimizer which does not implement those must explicitly say it uses native character compatibility.
- Native reflected `eUnitSex` table at file offset `0x8876348` (VA `0x148876f48`) confirms None=0, Male=1, Female=2. A nonzero equipment restriction must equal raw character `Sex`. All 454 extracted equipment rows currently have restriction 0.
- `summonableVisionNum=1` in `unit-parameter-calc.json` is a different field. The native slot function above is the actual evidence for the equipped vision count.
- Duplicate copies of the same accessory and duplicate passive stacking were not fully traced here. Keep an explicit copy/stacking policy; do not silently assume unlimited copies or repeated identical passives.

### What a selected vision supplies for free

The currently equipped vision supplies its unlocked **awakening abilities and its character-specific MR abilities**, without separately paying their AP costs. It does not supply every ability from every selected/owned vision.

Evidence:

- Original English `Game.locres` strings 20358–20360: MR-earned abilities must be equipped and have costs; abilities belonging to the currently equipped vision activate without separately equipping the ability.
- Native passive-list rebuild begins at `0x145244870`. At `0x1452448df` it calls awakening-passive helper `0x145015120` with type 2; at `0x1452448f9` it calls synchro/MR helper `0x14501e030` with the same equipped vision ID, character ID, and type 2.
- It subsequently gathers passives from the weapon (`0x145244929`), armor (`0x145244939`), and both accessory slots (`0x14524495c`, `0x14524497b`). These equipment passives are not paid AP abilities.
- `0x14501e030` reads MR points using vision ID + character ID, resolves the MR, and requests synchro table rewards of the selected type.

Implementation: current vision free passive IDs = union of awakening rewards through selected awakening tier and MR passive rewards through that character's selected MR. Use set identity to avoid charging AP for an already free ability.

Other visions make only their **MR-earned abilities** available as selectable paid abilities. Awakening-only abilities from an unequipped vision are not part of that learnable pool merely because the vision is owned.

### MR stat rewards apply independently of equipment

All attained MR `BaseParameter` rewards from the character's learned visions contribute to its stat/AP baseline, even when those visions are not currently equipped and their Spirit ability is not equipped.

This is not an inferred additive model: native initialization at `0x14523491a–0x145234927` invokes `0x145014aa0` with `excludeEquipped=false`. That helper iterates every owned vision, reads that character's MR, and calls `0x14501b2e0` to accumulate BaseParameter rewards into the character's extra-parameter map. `0x14501b2e0` selects synchro table 0x2f when its fourth argument is true, includes ranks <= selected rank, and only processes benefit type 5, summing its `[parameterId, value]` pair.

For a stat S:

```
MRBonus[S] = sum(value of S rewards from all visions at or below
                 this character's configured MR for each vision)
```

Selecting only a subset of visions for the optimization candidate pool should not implicitly erase permanent MR bonuses from other configured visions. Either keep progression separate from candidate availability or clearly define the selected set as the complete modeled progression set.

### AP budget

- Native `DT_UnitParameterCalc.baseSkillEquipCost` is **100** (`unit-parameter-calc.json`, native struct +0x16c, serialized offset 320).
- Character initialization copies this into +0x2a4 at `0x145234878–0x145234883`.
- Base AP getter for parameter 11 adds raw MaxSkillEquipCost to +0x2a4 at `0x14522bb1c–0x14522bb22`; ordinary aggregate then adds MR bonuses, gear, and effects.
- Character level growth tables currently contain zero AP at all levels.

```
AP capacity = 100 + raw character MaxSkillEquipCost
              + attained MR EquipCost rewards across all modeled visions
              + any separately modeled AP bonuses
```

The actual cost of a selected ability is its data `equipCost`. Avoid hardcoding a universal passive cost. Gear/free-vision passives consume zero additional AP. A selected attack/command that needs AP must share this budget with paid passives; if the calculator only spends a passive budget, reserve or expose the active-skill AP cost.

### Spirit mastery bundles

- A Spirit becomes available from the MR reward containing its master ID (normally rank 9).
- Original tutorial string 20430 explains that a Spirit activates MR abilities together in one equipped ability slot.
- Native Spirit expansion `0x14501d7a0` resolves the corresponding vision and gathers synchro reward type 1 (active skill) and type 2 (passive skill), at that vision's maximum MR. It does **not** gather type 5 BaseParameter rewards.
- Therefore a Spirit bundles MR actives/passives, but **does not grant awakening-only passives and does not grant the MR stat/AP rewards a second time**.
- Spirit costs vary, using `wiki.json.masters[].equipCost`: Terra 95, Warrior of Light 95, Amelia 100, Tronn 110, Firion 120, Sephiroth 130. The full table ranges 90–130.
- If an individual ability is active via a Spirit or the equipped vision, charge no extra AP for that redundant individual. Original UI strings 20532 and 20536 explicitly report these redundant states; 20556 says redundant abilities were unequipped.

### Vision combat-unit stats are not equipped stat bonuses

Do **not** add `visions[].unit` or its level-growth table to the player's stats. The raw unit rows are separate battle-unit definitions (many are level 99).

Native equipped-item parameter lookup `0x145017020` recognizes vision IDs in the 13000 range and retrieves **awakening BaseParameter rewards** via `0x14501b2e0` with fourth argument false. It does not call the vision unit-level stat getter. None of the 26 extracted awakening tables currently has a BaseParameter reward, so their direct flat stat addition from this path is zero. Their passive modifiers still apply normally.

## Base and combat stats

### Level growth is cumulative

```
NakedBase[S, L] = character level-one base[S]
                 + sum(level-table row[S] for rows with level <= L)
```

This is verified by native `0x145233510`: it copies DT_UnitParameter, iterates the referenced level table until row level exceeds requested level, and adds each HP/MP/Strength/Stamina/Magic/Spirit/Speed/AP field (`0x1452335ce–0x145233600`). The level-one growth row is zero, so including it is harmless. Rows are increments, not totals.

Example naked Lasswell at level 10: **HP 602, MP 94, Strength 62, Stamina 70, Magic 45, Spirit 59, Speed 61**. This excludes MR, gear, and passive bonuses. The user's observed 103 MP must not be substituted for the naked baseline.

### Primary stats map one-to-one into combat stats

Native base parameter switch `0x14522ba80` has the following jump table at `0x14522bc08`:

| Combat stat (parameter ID) | Base source |
|---|---|
| Physical attack (12) | Full Strength / Attack (5) |
| Physical defense (13) | Full Stamina / Defence (6) |
| Magic attack (14) | Full Magic / Intelligence (7) |
| Magic defense (15) | Full Spirit / Mind (8) |
| Sanctity / Divine (16) | Full Spirit / Mind (8) + raw Divine |

No hidden coefficient converts Strength to physical attack, etc. The full primary getter already includes primary-specific MR, equipment, and passive modifications. Then the combat getter adds combat-specific equipment and passive changes. Do not collapse primary-stat percentage bonuses into a damage multiplier.

Aggregate getter `0x145232dd0`:

```
GetParameter(p) = clamp(
    BaseParameter(p)
    + EquipmentAndExtraParameter(p)
    + sum(each passive's integer contribution to p),
    0, MaxParameter(p))
```

`EquipmentAndExtraParameter`, `0x14522e0f0`, adds the character extra map (MR), all equipped item flat values via `0x1450139d0`, and saved permanent parameter increments via `0x145108eb0`. The passive loop `0x145231940` converts each contribution from float to integer with truncation separately before adding it.

### Percentage stat passives use a fixed gear-inclusive base

The native `ParameterContinuousVariation` handler at `0x14513afb0` processes two possible triples `[value, parameterId, variationMode]` at offsets 0–2 and 3–5. It uses the first matching parameter triple. Modes are 0 flat increase, 1 flat decrease, 2 percentage increase, and 3 percentage decrease.

For modes 2/3, it calls `0x14522bc50`, which returns the clamped sum of `BaseParameter(p) + EquipmentAndExtraParameter(p)` without invoking the same parameter's passive aggregate. Therefore ordinary HP, MP, and primary-stat percentage increases apply to raw character base + cumulative level growth + MR rewards + gear + saved permanent increases. They exclude both flat and percentage passive contributions targeting that same parameter.

```
PercentBase[p] = clamp(BaseParameter(p) + EquipmentAndExtraParameter(p), 0, cap[p])
Contribution[p, mode0] = value
Contribution[p, mode1] = -value
Contribution[p, mode2] = trunc(PercentBase[p] * (value / 100 + epsilon))
Contribution[p, mode3] = trunc(PercentBase[p] * (epsilon - value / 100))
Final[p] = clamp(BaseParameter(p) + EquipmentAndExtraParameter(p)
                 + sum(each individually truncated passive contribution), 0, cap[p])
```

Native arithmetic uses float32 operations, float32 `0.01`, and epsilon `1.1920928955078125e-7`. Faithful implementation can reproduce these with `Math.fround`; simple real-number calculations can differ at integer boundaries. Contributions truncate toward zero, not floor.

Separate percentage passives add without compounding: base Speed 61 with +20% and +10% produces 61 + 12 + 6 = 79. Adding a flat Speed +5 passive produces 84, because that +5 passive does not enter either percentage base. A +5 gear or MR reward instead raises the percentage base to 66, producing 66 + 13 + 6 = 85. The main aggregate performs individual contribution truncation at `0x145231940`.

Combat parameters 12–16 inherit the *full* relevant primary parameter through `BaseParameter(p)`, so primary-stat passives can already be incorporated before a combat-specific percentage is evaluated. Preserve the primary/combat two-stage structure.

The separate AllParamUp handler `0x14513af00` affects parameters 5–9 and uses the same fixed percentage base. Its stored value is a total scale: 125 means +25%, calculated as `PercentBase * (value * 0.01 + epsilon) - PercentBase`, then truncated by the aggregate.

Names are not enough to classify modifiers. For example, passive 1275 **Magic Attack+30%** uses effect type 98 `DamageMultiplier` (effect 16013), and passive 1309 **Physical Attack+20%** uses the same effect type (16002). They increase matching damage, not the displayed Magic Attack or Physical Attack stat. In contrast, Speed+20% (1317, effect 1403) and HP+20% (1378, effect 16302) use type 3 `ParameterContinuousVariation` with mode 2. Conditional applicability, effect deduplication, and non-stat modifiers still require their own effect handling.

## Boundaries for the calculator

- Use all extracted gear and visions as requested; this is a catalog build, not a promise that every entry is obtainable in the demo.
- MR is character-specific; awakening is vision-specific. Keep these distinct.
- The shipped demo native rank resolver `0x14501b880` filters records above rank 5 in one observed path, while the extracted synchro tables contain ranks 0–9. This is consistent with a demo/runtime restriction but has not been tested in play. Full extracted rank-9 builds should be labeled theoretical extracted-content builds.
- No save was read, so extra permanent gains beyond configured MR are unknown. A manual extra-stat/AP field can account for them.
- Effects such as armor-enabling passives, procs, temporary buffs, and mixed attack/defense substitution require their own support or explicit exclusions.
- Do not say 'exact best build' if the search is pruned or effect handling excludes relevant mechanics; name the supported scoring model and any ignored effects.

## Reproducing the native evidence

The existing `disasm-range.py` accepts RVA ranges (virtual address minus 0x140000000), e.g.:

```
py resonance-analysis/disasm-range.py 522da30:522da4b 522ba80:522bc48 5232dd0:5232e3d
py resonance-analysis/disasm-range.py 5233510:5233647 5234830:523492c
py resonance-analysis/disasm-range.py 5014aa0:5014be2 501b2e0:501b596
py resonance-analysis/disasm-range.py 5244870:5244a78 501d7a0:501d8e4
py resonance-analysis/disasm-range.py 513af00:513b1d0 522bc50:522bcb0 5231940:5231a50
```

Source data: `wiki-decoded.json`, `wiki-enums.json`, `unit-parameter-calc.json`, `equipment-modifier-catalog.json`, and original English localization at `extracted/FFRS/Content/Localization/Game/en/Game.locres`.


---

# Calculator modifier audit — build 24032336

Read-only local data/native audit for the wiki build calculator. The companion `calculator-effect-rules.json` records conservative normalized rules. A rule identifies a computable contribution, not a promise that every interaction on that passive is modeled.

## Ownership, equipment, AP, duplicates

- `equipment[].stats` are flat equipment contributions; `equipment[].passives` are associated passive IDs. Read the actual ID, not the equipment name. Dodanuki 10207 has no passive.
- All 454 extracted equipment rows currently store `equipmentLimitSex=0`. Weapons must match the character's `weaponType`. Armor subtype must be in their `armorTypes`; accessories are unrestricted by these fields. No decoded passive changes these restrictions. Multiple copies/party inventory limits were not established.
- Of 378 passive definitions, 312 are associated with at least one extracted vision or gear item. Do not treat the other 66 as freely selectable learned abilities merely because they are in the data. Debug definitions include Nullify Physical/Magic.
- Exact tutorial evidence from `english-strings.txt`: key 20358 says MR-gained abilities must be equipped and have ability costs. Key 20359 says abilities possessed by the currently equipped vision activate without separately equipping the ability. Key 20430 says a Spirit grants that vision's **MR abilities** using one ability slot. Keys 20532 and 20536 identify an ability as already active through a Spirit/current vision.
- Thus a currently equipped vision's native/awakening kit is innate; mastery reward abilities form the learned pool. **The tutorial alone does not settle whether a currently equipped vision's own MR abilities are also auto-active.** Use a declared calculator assumption or the separate native ownership audit for that membership boundary. Do not count the entire combined `vision.passives` as both innate and paid; use the separate `awakening[].benefits` and `mastery[].benefits` arrays.
- Spirit cost is `masters[].equipCost` (e.g. Amelia 100, Tronn 110), and its bundle is the mastery-granted skill/passive abilities of that vision. It does not bundle all awakening abilities. It does not repeatedly award mastery stat rewards.
- Prevent duplicate manually equipped ability IDs, and do not charge AP for a passive already active through the selected vision/Spirit. This is supported by the UI strings above. Whether two different equipment items carrying the same passive ID, or distinct IDs carrying the same effect ID, can stack in the runtime was **not established**. Deduplicate same passive/effect IDs as a conservative calculator assumption and display that assumption. Distinct applicable damage effects have a proven additive accumulator; that does not prove acquisition of duplicate runtime effects.
- A mastery stat reward is a permanent progression benefit, distinct from a vision's equipped stats and from an AP skill. Do not sum the same reward each time a Spirit/current vision is selected. Character-specific accumulated mastery needs user input/progression settings.

## Numeric representation

All parameter indices in this audit are **zero based**. Use `effect.raw.effectType` rather than the translated display name when possible. Relevant enums in `wiki.json`:

`eUnitParameterType`: HP 1, MP 2, LB 4, Strength/Attack 5, Stamina/Defence 6, Magic/Intelligence 7, Spirit/Mind 8, Speed/Agility 9, effective level 10, AP/equip cost 11, physical attack 12, physical defense 13, magic attack 14, magic defense 15, Sanctity/Divine 16.

`eUnitParameterVariationType`: flat increase 0, flat decrease 1, ratio increase 2, ratio decrease 3, set ratio 4.

`eSkillAttributeType`: Fight 1, Ability 3, Magic 4, Limit Burst 5, Resonance/FinishBlow 9, Throw 11, Spellblade 15. Exact normal-attack/battle-skill membership is a separate native filter and cannot be replaced by `skillAttrType == Ability`.

## Supported stat and HP-damage contributions

| Effect / native type | Contribution and filter | Evidence / limit |
|---|---|---|
| ParameterContinuousVariation / 3 | `[amount, statId, variationType]`; source HP/MP/Speed passives use percentage increase type 2. Poison Powered/Poisoned Magic require activation condition HasStatusCondition(Poison). | Decoded parameters + localization. Final percentage stacking/base and rounding require the stat assembly audit. Do not use these as damage bonuses. |
| DamageMultiplier / 98 | `p0/100` to the HP-damage additive bucket when its gate succeeds. | Native wrapper 0x14510b7a0, gate 0x1451020b0, accumulator 0x145231bd0. |
| DmgMulElement / 184 | `[percent, element]`; additive HP damage for `applyTiming=47`, stagger contribution for `applyTiming=50`. Resolved attack elements are checked; element 0 matches only a completely non-elemental resolved list. | 0x145141220 in `modifier-stacking-details.txt`. Use raw element ID where name conflicts. |
| HoningSense / 118 | `p0/100` HP damage and `p1` crit threshold for nine meikyo IDs only, five-turn equipment effect. | Native gates in `hone-senses.md`. |
| CriticalRateVariation / 77 | `p0` adds to crit threshold, never multiplies the base chance. | 0x14513b2f0 in `critical-modifier-handlers.txt`; complete tail exists separately. |
| CritMul / 101 | `p0/100` adds to the ordinary 1.5 crit multiplier; p1 is minimum own HP%, p2 optional command ID. Different from Critical Boost. | Native crit accumulator 0x14522c500 and handler0x14510af50..0x14510b035. Sourced rows have p1=0,p2=-1. |
| ResistMagVariation / 78 | For sourced Weakness Exploiter/Vital Strike, add `p1/100 - 1` to elemental weakness multiplier (1.5→1.7 or1.8). | 0x14513ef10 and 0x14522d8d0–906. Not part of generic additive damage bucket. |
| DmgMulAllToSingle / 180 | +p0/100 when skill target type is Group(2) or All(4), against a sole enemy. Random-target Tumult does not qualify. | Native 0x14510b830 checks target byte with `(target-2)&0xfd == 0`, then sole-enemy checks. |
| Defense / 26 | Source `[class, percent, oneUse, coverFlag]` means incoming damage reduction. class 0 all,1 physical,2 magic. Each applicable factor is clamp((100-p1)/100,0,1); factors multiply. | Battle-rules agent native confirmation: vtable0x86911b8 slots3e8/3f0; handlers0x14513c650/0x145141400. Ordinary3e8 is before hit share/minimum; one-usep2>0 uses3f0 after minimum. Defense-status enhancement can modify3e8. It is not a raw DEF increase. |

Simple physical damage passives 1308/1309/1273 add 10/20/30%. Magic equivalents 1310/1311/1275 add 10/20/30%. Critical Boost 1234 adds 40% to the damage bucket **only on physical crits**; it does not change 1.5 to1.9. Rearguard 1383 has a physical +40% effect and a separate turn-order effect. Power Stagger 1385 applies physical +35% only to already staggered targets. Bonus Damage 1335 is +40% during bonus phase.

### Full DamageMultiplier gate decoded in this audit

`calculator-damage-gate.txt` contains native 0x1451020b0 through 0x1451023f4. These gates are conjunctive:

- p1: minimum current stored LB points (actor+0x118).
- p2 != -1: required current command ID (actor+0x430).
- p3 != 0: skill attribute class must match.
- p4 > 0: target Libra-analyzed and attack is a weakness hit.
- p5 != 0: damage class must match (1 physical,2 magic).
- p6 > 0: target passes status/debuff predicate 0x1452343e0 (eligible ailments require further trace).
- p7 != -1: must be bonus phase.
- p8 != -1: caller's all/multicast flag OR Magic skill with target in2..5; unused by most sourced simple passives.
- p9: own HP ratio at least p9/100.
- p10 != -1: hit must be critical.
- p11 != -1: calls specific gate0x1451445d0; not generalized here.
- p12 != -1: actor field+0x55c must be <=0; Stealth Specialist source describes not being attacked yet, but this field's increment owner was not traced.
- p13 != -1: own current MP / current max MP >=p13/100.
- p14 != -1: **base skill element byte at skill+0x7e must equal0**.

**Correction to older Lasswell report:** Essence of Mundanity's DamageMultiplier has p14=1,p5=0. The native gate directly tests the base skill element, not the resolved imbue list, and contains no additional physical filter for this row. Its localization says physical damage, but the decoded gate is broader. Do not silently substitute the older report's resolved-element/physical-only assumption. Either model the native base-element condition with a discrepancy label or leave this interaction unscored until battle validation.

CriticalRateVariation: p1 !=-1 requires staggered target; p2 !=0 requires skill attribute; p3..p5 are an optional exact skill-ID allowlist (if all−1, unrestricted); p6 !=−1 requires current command ID; p7 !=−1 additionally gates current LB points. Sourced universal rate passives set other params to−1/0. Ultimate Aggression1494 provides two effects, attribute5 and9, +100 threshold each; never sum both on a single skill.

## MP cost, recovery, procs, timing

- CostVariation50 uses p0 resource (2 MP), p1 percentage multiplier, p2 skill attribute filter (0 all). Half MP Cost1045 stores50; Magic Boost1103 stores150 for Magic4; Spellblade Mastery1416 stores50 forSpellblade15; Staggeringly Risky1405 stores150 with physical filterp6=1. **Applicable factors multiply**, native0x14522c1e0..c282 and0x14522c290..c37f. MP cost helper0x14513fc10 returns0 for zero base, otherwise trunc(max(1,baseCost*productFactors)); native float epsilon and rounding can matter at boundaries.
- Full CostVariation handler0x14510ad10: p0 resource must match; p2 attribute0all; p3 minimum current LB points; p4 optional command ID; p6 damage class0all; p5!=-1 requires multicast; p7=-1 unrestricted,0 requires calculation profile doCalcSkillEffect plus raw.skillEffectType1 and raw.parameterVariationType1/3 (damage/decrease),1 requires raw.skillEffectType1 and raw.parameterVariationType0/2 (healing/increase). p8==1 uses additional skill gate0x1451445d0 or multicast (usual sourced effects have0). Failed gates return1. Cost is not a percentage subtraction bucket.
- MP Cost:1/20 passive1135 stores p1=1 despite its label. It has no current gear/vision source. Exclude rather than infer0.05 or0.01.
- Magic Boost1103 has two sourced effects: MP150% and a DamageMultiplier100% on Magic4. Duration flags differ; localization has an unresolved damage placeholder. Do not claim a settled sustained100% without respecting lifecycle. Unlock Magic1417 references effect61004, not Magic Boost's1228; that mismatch needs native identity handling before assuming cancellation.
- ParameterVariation2 gives recovery/cost with `[amount,parameter,mode,...]`. E.g Restore MP on Critical1323 is3%maxMP (`[3,2,2]`); Restore MP on Attack1124 is2%maxMP; AutoMP(S)1254 is5flat per turn; AutoMP(M/L)1255/1256 are3/5%maxMP per turn. Trigger frequency per multi-hit cast, rounding and overheal are not established. Do not price proc recovery as guaranteed damage efficiency.
- Add Deshell1132's target debuff effect is30% Spirit reduction for3turns,30base apply chance on DealNormalAtk. It is not flat damage, a guaranteed opening debuff or a passive increase to the user's magic damage.
- `trigger`/bundle `passiveSkillAddTiming`, `timing`/effect `applyTiming`, chance, duration/proceed timing, bundle condition and activation condition all matter. An effect marked a damage multiplier on a Crit/Break/OnDefeat trigger is not unconditional.
- Auto-Hone1507 and Auto-Placidity1514 have5turns; Auto-Bravery1489 and Auto-Faith1304 source constant versions have−1; Bravery/Faith/Protect/Shell/Haste Openers are3turns. Auto-Concentrate1512 has3turns and applies magic damage+100% plus Speed+100% in its raw bundle. Display temporary status assumptions.

## Other conditional contributions: label or require scenario

Native-support/localization and parameters allow explicit scenario controls for Sharp Mind, Hone, Power Stagger, elemental bonuses, Critical Boost and universal crit rate. Other definitions can be exposed but should not be made unconditional: Tip-Top Shape1428(+15% per qualifying buff; native0x14513bb00 has no physical-only filter or cap, contrary to physical wording); Aggravation1468(+15% per qualifying ailment up to60; native0x14513bdd0 has no physical-only filter; exact eligible set requires helper audit); Preemptive Strike1394(+30% before target acts); Skill Flow1464(history of skill types); Improvement1421(history of standard/battle attacks); Heroic Nature1409(attacks received); Dark Rite1431(HP-dependent formula); Jenova Cells1490(Spirit-derived scaling/cap); Dual Guns1443(+25% repeat chance, plus Trigger-Happy conditions); Dominant Power1410/1491(stat substitution); counters; one-use survival/absorption; imbues and reactive barriers.

These unmodeled effects can change rankings. A calculator must show supported-score results and list omitted build effects rather than call a partially modeled result globally optimal.

## Evidence files

`wiki.json`, `passive-modifier-catalog.json`, `equipment-modifier-catalog.json`, `all-skill-effects.json`, `wiki-decoded.json`, `english-strings.txt` keys20358/20359/20430/20532/20536; `attack-formula.md`; `lasswell-modifiers.md` except the Essence correction above; `hone-senses.md`; `critical-modifier-handlers.txt`; `critical-modifier-tail.txt`; `critical-multiplier-function.txt`; `modifier-stacking-details.txt`; `weakness-stacking-tail.txt`; new `calculator-damage-gate.txt`, `calculator-cost-crit-handlers.txt`, `calculator-cost-accumulator.txt`, `calculator-cost-rounding.txt`, `calculator-cost-filters.txt`.


---

# Battle rules audit for the build calculator

Installed FINAL FANTASY RESONANCE DEMO, Steam build 24032336. Static read-only audit on 2026-09-07. Preferred executable image base is 0x140000000. This extends `attack-formula.md`; it does not claim a full battle simulator or measured combat frequencies.

## Ordinary physical and magical HP damage

The prior reconstructed ordinary formula remains supported:

```
r = effective attacking combat attribute / max(effective defending combat attribute, 1)
F(r) = 0.5*r                  r < 0.5
       r*r                    0.5 <= r < 1
       8/(1+exp(1-r)) - 3      r >= 1

base = 0.6 * (effective attacker level + 2) * F(r)
effectivePower = basePower * (1 + attacker power bonuses + target power bonuses)
                 + flat power additions
rawHP_i = base * effectivePower * variance * abs(elementFactor)
          * criticalFactor * staggeredTargetFactor * eligibleAllTargetFactor
          * applicableHPDamageBonusFactor * otherContextFactors
          * ordinaryDefensiveFactor * hitShare_i
```

Physical uses physical attack versus physical defense; magic uses magical attack versus magical defense. Light magic has a separate Sanctity-derived attack path. The stat-rules audit covers how the displayed attributes are derived. Raw Strength is not substituted for physical attack. Defense does not subtract a fixed amount from damage and is not a universal percent reduction. Its effect depends on the attack/defense ratio. The ratio factor approaches 5 from below at high attack; total damage is not capped at five.

HP variance has its own CRT random draw: `0.95 + 0.1*N/32767`, N in 0..32767. Skill power is used directly, not divided by 100. +20 flat power changes power 10 to 30; +20% power changes 10 to 12. A final-damage modifier is a later layer.

Relevant source: `attack-base-and-resistance.txt`, `attack-helper-ranges.txt`, `critical-calculation.txt`, `attack-formula.md`.

## Criticals, accuracy, elements

Each eligible hit uses its skill's own critical threshold, not one character-wide base crit stat:

```
T = skill.criticalHitRate + sum(applicable threshold bonuses)
critical iff T >= 1 + N * float32(99/32767)
```

Under uniform masked draws, actual chance is approximately clamp((T-1)/99,0,1), with exact float32 enumeration already implemented in the wiki. Threshold 2 is about 1.01013%; threshold 3 about 2.02026%; threshold 22 about 21.21277%. Adding 20 is a threshold addition, not multiplication by 1.2. Baseline critical multiplier is 1.5; native critical-damage effects add to that multiplier. Expected factor without state-dependent proc changes is `(1-p)*1 + p*criticalMultiplier`. Calculate critical and noncritical cases separately when their effects differ.

Accuracy has a separate integer 1..100 roll. In the ordinary eligible path, evasion additions are capped at 75 before subtracting from accuracy; relevant status resistance is applied afterward. Full resistance and forced misses have separate branches. An already-staggered target bypasses the ordinary random hit check after the full-resistance check. Magic damage tables explicitly permit crit and ordinary damage calculation; do not globally say spells cannot crit.

The ordinary HP element table is neutral 1, weakness 1.5, half 0.5, immunity 0; absorption is a special outcome. Stagger uses a different element table, below. An already-staggered target has a separate 1.5 HP damage multiplier where the calculation flag allows it. Critical, weakness, and stagger are separate multipliers: baseline triple condition is 3.375, before other bonuses. The area penalty is 0.4 only where `isApplyAllMag` applies and no qualifying override removes it.

## Damage taken: defense stats and percentage mitigation are separate layers

Native `CPP_ContFxDeffence` is percentage damage mitigation, not physical/magical defense stat. Its parameters are:

- p0: damage type filter: zero any, otherwise exact native damage type (1 physical, 2 magical).
- p1: reduction percent.
- p2: selects the later one-use style path when positive.
- Other conditions/lifetime/activation still matter; do not rank a conditional effect as always-on.

Each applicable ordinary mitigation effect returns approximately `clamp(100-p1,0,100)/100`. Native loops MULTIPLY applicable mitigation factors. Two applicable 20% and 30% reductions give `0.8*0.7 = 0.56` damage taken, i.e. 44% reduction. They do not give 50% reduction. Duplicate status application may be resolved before this stage; this proves multiplication of effects present in the active list, not permission to equip duplicates or stack identical statuses.

Order is meaningful near integer boundaries:

1. Main HP damage chain including combat defense, power, element, critical, bonuses.
2. Product of target virtual slot 0x3e8 factors.
3. Hit share.
4. Configured minimum-one handling, where applicable.
5. Product of target virtual slot 0x3f0 factors (positive p2 Deffence path).
6. Survival/reprieve-like minimum selection, other zero/override branches, integer truncation and damage cap.

Thus `max(1,floor(allDamageFactors))` is not a faithful full simulator. A later defense or override can still yield zero. The ordinary Deffence handler also multiplies a defense-status enhancement helper: that helper takes the MINIMUM eligible slot-0x400 result starting at 1. Cover is another slot-0x3e8 reduction but only when its owner is currently covering.

Evidence: `calculator-defense-handlers.txt`; Deffence vtable file offset 0x86911b8: slot 0x3e8 -> 0x14513c650, slot 0x3f0 -> 0x145141400. Main loops at 0x14522653b..665e (`critical-calculation.txt`). Defense enhancement 0x14522c6f0..c766; cover 0x14510bbe0..bc3c. Effects are checked for active lifetime and applicability before participating.

For survivability scoring, compare predicted damage from an explicit enemy attack scenario, and optionally `HP / expected incoming damage`. More HP helps survive all HP damage; a defense stat helps only paths that consult it. Fixed/HP-percent/defense-ignoring attacks cannot be scored with the ordinary ratio equation. Avoid calling HP-times-defense an exact effective-HP formula.

## Stagger damage: newly reconstructed full ordinary arithmetic

The stagger-bar path is separate from HP damage. It uses `breakDamageValue`, not skill HP power and not attack/defense attributes. It also has a separate level-gap adjustment. No variance random call occurs in this stagger arithmetic routine.

Ignoring tiny float epsilon terms, for a landed applicable hit:

```
B = skill.breakDamageValue
Mbase = 1 + sum(attacker base-stagger bonuses) + sum(target base-stagger bonuses)
Fflat = sum(attacker flat stagger additions)
Mbreak = 1 + sum(eligible BreakDmgCalculation damage modifiers)
Mdef = product(target stagger-defense factors)

gap = effectiveAttackerLevel - effectiveTargetLevel
Lgap = 1 + 0.1 * gap^0.6                 gap > 0
       1                                gap = 0
       max(0.1, 1 - 0.1 * (-gap)^0.6)   gap < 0

rawStagger_i = (B*Mbase + Fflat)
               * eligibleAllTargetFactor
               * staggerElementFactor
               * criticalFactor
               * Mbreak * Mdef * hitShare_i * Lgap
staggerDamage_i = truncate(rawStagger_i + 0.5)
```

This is round-nearest for positive stagger damage, unlike ordinary HP damage truncation. Each hit rounds separately. A two-hit skill with base stagger 25 and shares 0.5/0.5 produces 13+13=26 at equal levels, neutral, noncrit, no other modifiers; a one-hit skill with the same base produces 25. If the first hit staggers the enemy, later hits do not keep reducing an already empty gauge.

Stagger element factors are neutral 1, weakness 3, half 0.5, immunity 0, absorption 0. The existing critical flag is passed into this path and the same critical-multiplier helper is called: eligible criticals increase stagger as well as HP damage. No new crit roll is drawn here.

The base multiplier pools correspond to attacker virtual slot 0x5b0 and target 0x5c0, summed together before multiplication by B. Flat additions come from attacker slot 0x5a0. Those pools are DISTINCT from the timing-50 factor and target-defense product. Do not flatten all stagger bonuses into a single sum.

`BreakDamageVariation` (effect type 92) with apply timing `BreakDmgCalculation` (timing 50) calls shared condition helper 0x145101e30. If applicable it returns p0/100 into the Mbreak sum. Its full filters are significant; it is not unconditional simply because its first parameter is positive. The generic helper checks weakness/result flags, target conditions, skill attribute, damage type, HP-ratio gate, critical flag, skill list and additional special gates. Exact raw gates are preserved in `calculator-condition-helper.txt` for the calculator implementation.

`BreakDefence` (effect type 27) returns p0/100 as a target multiplier, with no conversion from "increase" wording: raw 130 means 1.30, raw 75 means 0.75. Each applicable target BreakDefence factor multiplies. Native handler is 0x144dc23b0, virtual slot 0x3f8, vtable file 0x86863e0.

Concrete Lasswell example: Placidity effect 15132 is type92, timing50, p0=40, so Mbreak1.4 while active. Null Moon's target effect16090 is type27, p0=130, so Mdef1.3 while applied. Together those layers give 1.82 times the matching stagger result BEFORE per-hit rounding. This does not mean Null Moon's debuff retroactively boosts the hit that applied it; effect application timing has to be respected. Hone's +40 HP damage is not itself a stagger modifier, but its higher critical chance can improve expected stagger on eligible Meikyo hits.

The main stagger routine exits when the target is already staggered. It also excludes player-type targets and enemy-type attackers in the ordinary route. A support skill can store a nonzero default `breakDamageValue` while its damage calculation does not invoke this route: e.g. Placidity stores 25 but is not an attack. UI/calculator must respect the calculation flags and actual skill effect type, not treat every nonzero stagger field as an attack.

Evidence: `calculator-stagger-main.txt`, native 0x145225630..5c16. Formula multiply/level/round block 0x145225b15..5bc7. Level helper is powf: call stub 0x147576322 resolves to CRT powf IAT0x147726bf0. Element helper called in stagger mode at0x145225898. Crit helper call0x1452259cc. Area helper call0x145225ac3. Gauge remainder clamps to0..maximum and marks newly broken when remainder<=0. Data flags in `combat-flags-costs.json`.

## Stagger consequences and Resonance

The installed English tutorial states:

- Each enemy has its own stagger gauge; zero staggers it.
- Staggered enemies cannot act on their turn and take increased damage.
- The character that staggers an enemy receives an extra action at the end of the round (bonus phase).
- Stagger every enemy in a single turn for a sweeping stagger, granting all party members an extra action during the bonus phase.
- A sweeping stagger enables a vision's Resonance at the end of the bonus phase. Resonance effects differ by vision.

Source: `english-strings.txt`, indexed strings20391,20410,20414,20420. Do not invent a guaranteed stagger duration, recovery/reset rule or enemy behavior from these short tutorial statements; enemies have scripted exceptions and reactions in the extracted data.

## Limit Burst resource, power, charging

One LB gauge is100 units. The global max gauge constant is200/two gauges; the tutorial says characters gain the second gauge after learning a level2 LB. Do not assume a low-level character can bank200 before that unlock. Native reflection getters `GetLimitBurstPointMaxGauge`, `GetLimitBurstPointMaxGaugeNum`, `GetLimitBurstPointOneGauge` return200,2,100 at0x144d69480/4a0/4c0. Actual current-point updates clamp against the unit's dynamic maximum at native+0x2a0, not just the global constant.

An LB's cost is its skill's LB cost, e.g. Null Moon100 versus Transient Rite200. The level number in "level2 LB" describes the second LB/two-gauge unlock; it is separate from a character-level scaling effect on the skill's power. Lasswell's two LBs have `MulBaseSkillByLevel` effect12966, param1500, contributing effectiveLevel/15 to the base-power modifier pool. Their base power therefore becomes22*(1+L/15) and33*(1+L/15) before any other power changes. This scaling is an attached effect, not a universal hardcoded multiplier to add to every LB. See `limit-burst-power-scaling.txt` and per-skill effects.

New native trace of damage-received charge:

```
rawDamageReceivedLB = truncate(50 * min(HPdamage, HPbeforeHit) / maxHP)
```

The call is per damage-result processing for player-type targets. That integer then enters the LB addition helper, which applies permitted LB-gain rate effects, truncates again and clamps the current gauge. For example, a single damage result consuming10% of maxHP gives5 base gauge units before LB-gain modifiers. Small hits can round down to zero. It is not50 LB on every hit. The numerator is capped to remaining HP before the damage result, preventing overkill from charging as though all excess damage removed HP. This is static control-flow evidence, not gameplay measurement.

Native evidence: `calculator-lb-damage.txt`,0x144f7830d..7834c, reads unit-parameter-calc damagedLBIncrease at+0x1c8 (configured50) and passes to0x145223d00. MaxHP getter0x14522fa10.

Stagger completion code chooses the configured25 (`breakLBIncrease`,+0x1c0) or50 (`allBreakLBIncrease`,+0x1c4) before calling that same LB add helper. The two are alternatives in this branch, not25+50. The recipient is the acting unit passed through that event; do not claim the50 is automatically awarded to every party member merely because everyone gains a bonus action. Native0x144f6f186..6f1d7.

LB addition helper0x145223d00 has explicit no-LB/positive-gain blocker paths (virtual slots0x368 and0x550). Its applicable general resource-rate modifiers (slot0x360 with parameter enum4=LB) use a maximum-selection pool, not addition of every printed percent. It multiplies the raw integer gain by the selected rate, truncates, then clamps the new current value to0..the unit's dynamic maximum. Duration, trigger and source ownership still matter. Named passives can add LB at battle start, action end, on critical, etc.; their own timing/data must be used. No universal ordinary-attack LB charge amount is asserted here without tracing its attached effects/event path.

## Damage caps and model limits

Main HP damage calls0x14522f950 for the attacker cap after most effects. This helper begins at9999 for native unit type1 and99999 for other types, then takes the maximum cap returned by applicable slot0x470 effects. The already-confirmed player-type checks support9999 as the ordinary player cap; do not impose9999 on every vision/other attacker unconditionally. Native branches bypass this cap for calculation type0x12 and a forced-override flag. Consequently a per-hit player cap is appropriate only for the supported ordinary player attack path.

Native evidence: `calculator-battle-main.txt`,0x14522f950..f9d0; final min with cap at0x1452268bd..68da in `critical-calculation.txt`.

A build ranking is an explicit scenario estimate. It must expose attacker level, target level and relevant combat defenses, element state, already-staggered state, skill, hit distribution and relevant temporary conditions. The calculator should distinguish supported exact arithmetic from unsupported effect/state features instead of silently awarding every extracted passive its best-case benefit. Dynamic procs, chaining/counters, repeated turns, enemy scripts, buffs expiring mid-action, multi-target redistribution, immunity/absorption/reflection, LB bank timing and exact RNG sequencing require additional state modelling.

### Resonance attacker boundary

Exclude `skillAttrType=9` (`FinishBlow` / Resonance) from a calculator that only constructs playable-character combat stats until the Resonance event's attacker construction is traced. The native HP routine accepts a battle-unit attacker and reads that unit's resulting stats; this audit has not proven which unit instance the Resonance event passes. Therefore applying the playable character's stats to a vision's Resonance is unsupported, even when the skill itself uses the ordinary Physical/Magic equation.

Tutorial string20414 describes Resonance as a vision attack. String20366 distinguishes the character's Last Resonance strike from the equipped vision's following Resonance. These are evidence for keeping the two attacker contexts separate, but do not alone prove a precise separate-vision-stat formula. Conservative exclusion is the current reliable calculator boundary, rather than claiming the vision-unit ownership is fully native-verified. Ordinary equipped-vision commands and abilities remain character-usable according to tutorial20488/20495; those are different from the special Resonance event.
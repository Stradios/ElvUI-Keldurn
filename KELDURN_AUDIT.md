# ElvUI-Vanilla → Keldurn: compatibility audit

Static audit (text search only) of `ElvUI-Vanilla/ElvUI` (master, archived 2019) against the client gaps that
`ne0x86/keldurn-addons` documents in its Titan Panel / OmniCC patch commit (`31d8e3e`).
Nothing here was run on the Keldurn client, so "missing" means "the Keldurn patch author had to guard it",
not "confirmed absent". Only `TutorialFrameParent`, `SetSequence`, `<NormalText>`, `UNIT_MANA` and the
2-level dropdown limit are stated outright by the author.

## Size of the job

| Folder | Files (lua/xml/toc) | Lua lines |
| --- | --- | --- |
| `ElvUI` | 294 | 61,939 |
| `ElvUI_Config` | 69 | 36,559 |
| `!Compatibility` | 13 | 3,529 |
| `!DebugTools` | 5 | 1,317 |

For comparison, the whole Titan/OmniCC patch touched 27 files with about 820 added lines. ElvUI plus its config is
about 100,000 lines of Lua, so expect a much longer fix list, though each fix should be small.

## P0: will break loading or spam errors at startup

### 1. `!Compatibility` overwrites game functions unconditionally
`ElvUI.toc` depends on `!Compatibility`, so this loads first. It defines 45 top-level global functions
(15 in `api/luaAPI.lua`, 30 in `api/wowAPI.lua`) and I found no top-level "only if missing" guards.
Examples that Keldurn very likely already provides natively:

- `api/luaAPI.lua`: `select` (32), `string.join` (175), `string.match` (188), `table.wipe` (307), `print` (381)
- `api/wowAPI.lua`: `hooksecurefunc` (103), `securecall` (177), `tContains` (185), `UnitAura` (198),
  `GetItemCount` (674), `GetContainerNumFreeSlots` (698), `GetShapeshiftForm` (861)
- `api/luaAPI.lua:17-18`: `string.gmatch = string.gfind` and `gmatch = string.gfind`. If Keldurn has no
  `string.gfind`, this sets `gmatch` to `nil` and breaks every addon that uses it.

The Keldurn Titan patch hit the same class of problem (it stopped replacing `ToggleDropDownMenu`,
`OpenCoinPickupFrame`, `CooldownFrame_SetTimer`, `Localize`, because overriding them broke other UI).

**Fix:** wrap each definition as `if not X then ... end`, and make line 17-18 `if string.gfind and not string.gmatch`.

### 2. `!Compatibility/errorHandler.lua` depends on Blizzard error UI
Lines 13-41 install `_ERRORMESSAGE_NEW` via `seterrorhandler`; it calls `debuginfo()`, `ScriptErrors`,
`ScriptErrors_Message` and the `TOO_MANY_LUA_ERRORS` popup. Lines 43-48 also replace `message()`.
If any of those are missing in Keldurn, the error handler itself errors, which can produce an error loop
that hides the real problem.

**Fix:** replace with the "report once in chat" pattern from `TitanKeldurn.lua` (`pcall` + `DEFAULT_CHAT_FRAME:AddMessage`),
and keep `!DebugTools` optional (`slashCommands.lua` already loads it lazily).

## P1: breaks individual modules

| Area | Where | Problem | Fix |
| --- | --- | --- | --- |
| Frames that may not exist | `Modules/Blizzard/GM.lua:5-8` | Calls `TicketStatusFrame:ClearAllPoints()` with no nil check | Guard |
| | `Modules/Auras/Auras.lua:463-464` | `E:Kill(BuffFrame)`, `E:Kill(TemporaryEnchantFrame)` | Make `E:Kill` nil-safe (below) |
| | `Core/toolkit.lua:226-235` | `E:Kill` reads `object.UnregisterAllEvents` before checking `object` | `if not object then return end`; one change covers many callers |
| | `Modules/Blizzard/CaptureBar.lua:11,47` | Hooks `WorldStateAlwaysUpFrame_Update` | Guard hook target |
| | `Modules/Skins/Blizzard/Misc.lua:25,239-243` | Skins `TicketStatusFrame`, `CoinPickupFrame` and its buttons | Guard each |
| | `Core/StaticPopups.lua:15,294,308` | Uses `MoneyFrame_Update` (Titan patch guarded the `MoneyFrame_*` family) | Guard |
| | Action bars, bags, quest/watch/durability, minimap | 83 matching lines across 18 files for `MainMenuBar`, `MultiBar*`, `PetActionBarFrame`, `ShapeshiftBarFrame`, `CastingBar*`, `GroupLootFrame`, `QuestTimerFrame`, `DurabilityFrame`, `QuestWatchFrame`, `MinimapCluster`, `PartyMemberFrame`. Heaviest: `ActionBars.lua` (19), `BagBar.lua` (12), `Skins/Blizzard/QuestTimers.lua` (12), `Blizzard/WatchFrame.lua` (8), `Maps/Minimap.lua` (6) | Probe which exist, then guard those |
| Power/mana events | `Libraries/oUF/elements/power.lua:241-268` | Registers only `UNIT_MANA/RAGE/FOCUS/ENERGY`. Keldurn reports mana via `UNIT_POWER_UPDATE`, so mana bars and tags would freeze. 57 matching lines for `UNIT_MANA`/`UnitManaMax` across 7 files (`Modules/UnitFrames/Tags.lua` 28, `oUF/elements/tags.lua` 10, `LibDruidMana` 8, `power.lua` 6) | Also register `UNIT_POWER_UPDATE` via `pcall(frame.RegisterEvent, ...)`; add the 0.25 s mana poll fallback Titan's Regen module uses |
| Cooldown text | `Core/Cooldowns.lua:102` | `start > 0 and duration > MIN_DURATION and enable > 0` errors if `enable`/`start` is `nil` or boolean. The hook at 119-126 already calls the original first, which is the safe pattern the OmniCC patch uses | `tonumber()` the values; treat `nil`/`true` as "on" |
| Model animation | `Modules/Misc/AFK.lua:51,58` | `SetSequenceTime` / `OnAnimFinished` on a model (Keldurn has no `SetSequence`) | Guard, or disable the AFK module |
| XML text element | `Libraries/LibUIDropDownMenu/LibUIDropDownMenuTemplates.xml:183` | `<ButtonText name="$parentNormalText"/>` is the same kind of text element as the `<NormalText>` Keldurn does not create (inferred, verify) | Convert to a `<FontString>` layer, as the Titan patch did |
| Global dropdown calls | `Libraries/oUF/ouf.lua:227`, `Modules/Misc/Loot.lua:161` | Call Blizzard's global `ToggleDropDownMenu` | Verify against Keldurn's own menu system |

## Looks fine or low risk

- **Dropdown menus:** ElvUI ships its own `LibUIDropDownMenu` with `L_UIDROPDOWNMENU_MAXLEVELS = 2`
  (`LibUIDropDownMenu.lua:27`), which matches Keldurn's 2-level limit.
- **Memory datatext:** `Modules/DataTexts/System.lua:84` uses `gcinfo()` for a single value, so the "no GC threshold"
  problem that hit Titan Performance does not apply.
- **Tooltips:** `GameTooltip:SetOwner(this, ...)` appears 12 times in `ElvUI` and once in `ElvUI_Config`, and the
  ones I looked at are hover handlers where `this` is valid. The Titan failure was a scan tooltip with no valid `this`. `Bags.lua:74` passes only one argument.
- **Frames Titan guarded that ElvUI never touches:** `TutorialFrameParent`, `FramerateLabel`, `OpenCoinPickupFrame`.

## Not audited yet

`Developer/`, `Libraries/` (Ace3 and oUF internals beyond the hits above), `Locales/`, `Settings/`, and all of
`ElvUI_Config`. Also still to check: reliance on `this`/`arg1` globals (690 lines in `ElvUI`, 360 in `ElvUI_Config`,
58 + 20 `OnUpdate` scripts). Titan's own code still uses those globals on Keldurn, so they probably work, but the
Titan author also handles `OnUpdate` receiving `(frame, elapsed)` as parameters, so this needs a test.

## Suggested order

1. Guard `!Compatibility` (P0 #1) and replace its error handler (P0 #2). Get the client to load with zero errors.
2. Make `E:Kill` nil-safe and wrap each module's `Initialize` in `pcall` with a report-once message, so one bad module cannot stop the rest.
3. Run a probe on the Keldurn client that reports which of the globals above exist. This replaces guessing with a list.
4. Fix modules in this order: unit frames and power events, action bars, bags, chat, minimap, skins, config.

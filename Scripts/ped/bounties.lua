local util = require("ped.util")

local M = {}

local ROSTER = {
    { id = "BOSS_Hunter_Rifle", name = "Hawk", tokens = 1 },
    { id = "BOSS_Believer_CrossBow", name = "Ego", tokens = 1 },
    { id = "BOSS_Ninja", name = "Fumble", tokens = 1 },
    { id = "BOSS_Female_Soldier", name = "Jade", tokens = 1 },
    { id = "BOSS_Male_Soldier", name = "Crash", tokens = 1 },
    { id = "BOSS_Male_Soldier02", name = "Dart", tokens = 1 },
    { id = "BOSS_Male_Soldier04", name = "Lasso", tokens = 1 },
    { id = "BOSS_Female_People02", name = "Siren", tokens = 1 },
    { id = "BOSS_Female_People03", name = "Turncoat", tokens = 1 },
    { id = "BOSS_Male_People", name = "Dyna", tokens = 1 },
    { id = "BOSS_Male_People2", name = "Mite", tokens = 1 },
    { id = "BOSS_Male_People03", name = "Scoot", tokens = 1 },
    { id = "BOSS_Hunter_Fat_GatlingGun", name = "Grill", tokens = 2 },
    { id = "BOSS_Believer_Fat_GiantClub", name = "Brick", tokens = 2 },
    { id = "BOSS_FireCult_FlameThrower", name = "Shadow", tokens = 2 },
    { id = "BOSS_Police_Rifle", name = "Whip", tokens = 2 },
    { id = "BOSS_Male_DesertPeople", name = "Phantom", tokens = 2 },
    { id = "BOSS_Female_DesertPeople", name = "Whisper", tokens = 2 },
    { id = "BOSS_Female_People", name = "Flare", tokens = 2 },
    { id = "BOSS_Female_Soldier03", name = "Aloha", tokens = 2 },
    { id = "BOSS_Hunter_Fat_GatlingGun_Quest_StrongOldMan", name = "Elder", tokens = 2 },
    { id = "BOSS_Male_Soldier03", name = "Clint", tokens = 3 },
    { id = "BOSS_Female_Soldier04", name = "Nimble", tokens = 3 },
    { id = "BOSS_Male_People02", name = "Quill", tokens = 3 },
    { id = "BOSS_Male_NinjaElite", name = "Urchin", tokens = 3 },
    { id = "BOSS_Scientist_LaserRifle", name = "Whisk", tokens = 3 },
    { id = "BOSS_Male_Trader01", name = "Skim", tokens = 3 },
    { id = "BOSS_Viking", name = "Gnaw", tokens = 4 },
    { id = "BOSS_VikingElite", name = "Cache", tokens = 4 },
    { id = "BOSS_Female_Soldier02", name = "Dazzle", tokens = 4 },
    { id = "BOSS_Police_old", name = "Pinch", tokens = 4 },
    { id = "BOSS_Male_Trader02", name = "Mimic", tokens = 4 },
    { id = "BOSS_Male_Trader03", name = "Billy", tokens = 4 },
    { id = "BOSS_DarkTrader", name = "Ram", tokens = 5 },
}

local PAWN_CLASSES = {
    BOSS_Hunter_Rifle = "Normal/BP_NPC_Hunter_Boss",
    BOSS_Believer_CrossBow = "Normal/BP_NPC_Believer_BOSS",
    BOSS_Ninja = "Normal/BP_NPC_Male_Ninja01_BOSS",
    BOSS_Female_Soldier = "Normal/BP_NPC_Female_Soldier_BOSS",
    BOSS_Male_Soldier = "Normal/BP_NPC_Male_Soldier_BOSS",
    BOSS_Male_Soldier02 = "Normal/BP_NPC_Male_Soldier02_BOSS",
    BOSS_Male_Soldier04 = "Normal/BP_NPC_Male_Soldier04_BOSS",
    BOSS_Female_People02 = "Normal/BP_NPC_HumanNormal_Female_2_BOSS",
    BOSS_Female_People03 = "Normal/BP_NPC_HumanNormal_Female_3_BOSS",
    BOSS_Male_People = "Normal/BP_NPC_HumanNormal_Male_1_BOSS",
    BOSS_Male_People2 = "Normal/BP_NPC_HumanNormal_Male_1_BOSS",
    BOSS_Male_People03 = "Normal/BP_NPC_HumanNormal_Male_3_BOSS",
    BOSS_Hunter_Fat_GatlingGun = "Fat/BP_NPC_HunterFat_Boss",
    BOSS_Believer_Fat_GiantClub = "Fat/BP_NPC_BelieverFat_BOSS",
    BOSS_FireCult_FlameThrower = "Normal/BP_NPC_FireCult_BOSS",
    BOSS_Police_Rifle = "Normal/BP_NPC_Police_BOSS",
    BOSS_Male_DesertPeople = "Normal/BP_NPC_Male_DesertPeople_BOSS",
    BOSS_Female_DesertPeople = "Normal/BP_NPC_Female_DesertPeople_BOSS",
    BOSS_Female_People = "Normal/BP_NPC_HumanNormal_BOSS",
    BOSS_Female_Soldier03 = "Normal/BP_NPC_Female_Soldier03_BOSS",
    BOSS_Hunter_Fat_GatlingGun_Quest_StrongOldMan = "Fat/BP_NPC_HunterFat_Boss",
    BOSS_Male_Soldier03 = "Normal/BP_NPC_Male_Soldier03_BOSS",
    BOSS_Female_Soldier04 = "Normal/BP_NPC_Female_Soldier04_BOSS",
    BOSS_Male_People02 = "Normal/BP_NPC_HumanNormal_Male_2_BOSS",
    BOSS_Male_NinjaElite = "Normal/BP_NPC_Male_NinjaElite01_BOSS",
    BOSS_Scientist_LaserRifle = "Normal/BP_NPC_Male_Scientist_BOSS",
    BOSS_Male_Trader01 = "Normal/BP_NPC_Male_Trader_BOSS",
    BOSS_Viking = "Normal/BP_NPC_Viking_BOSS",
    BOSS_VikingElite = "Normal/BP_NPC_VikingElite_BOSS",
    BOSS_Female_Soldier02 = "Normal/BP_NPC_Female_Soldier02_BOSS",
    BOSS_Police_old = "Normal/BP_NPC_Police_old_BOSS",
    BOSS_Male_Trader02 = "Normal/BP_NPC_Male_Trader_2_BOSS",
    BOSS_Male_Trader03 = "Normal/BP_NPC_Male_Trader_3_BOSS",
    BOSS_DarkTrader = "Fat/BP_NPC_DarkTrader_BOSS",
}

function M.pawn_class(character_id)
    local relative = PAWN_CLASSES[character_id]
    if not relative then return nil end
    return "/Game/Pal/Blueprint/Character/NPC/" .. relative .. "." .. relative:match("([^/]+)$") .. "_C"
end

local PROFILES = {
    native = {
        id = "native",
        name = "Native Alarm",
        description = "Palworld's selected invasion composition with no bounty replacement.",
        mode = "native",
    },
    mixed = {
        id = "mixed",
        name = "Bounty Captain",
        description = "One bounty captain per selected composition; native escorts remain.",
        mode = "replace",
        maximumReplacements = 1,
        minimumTokens = 1,
        maximumTokens = 5,
    },
    patrol = {
        id = "patrol",
        name = "Bounty Patrol",
        description = "Every selected member becomes a one- or two-token bounty target.",
        mode = "replace",
        minimumTokens = 1,
        maximumTokens = 2,
    },
    ["all-bounty"] = {
        id = "all-bounty",
        name = "All-Base Bounty Assault",
        description = "Simultaneous PED-controlled bounty attackers at every eligible base; the full 34-target catalog rotates across bases.",
        mode = "replace",
        backend = "custom-assault",
        minimumTokens = 1,
        maximumTokens = 5,
    },
    ["most-wanted"] = {
        id = "most-wanted",
        name = "Most Wanted",
        description = "Every selected member becomes a two- through four-token bounty target.",
        mode = "replace",
        minimumTokens = 2,
        maximumTokens = 4,
    },
    kingpin = {
        id = "kingpin",
        name = "Kingpin Siege",
        description = "Every selected member becomes Ram, the five-token Dark Trader bounty.",
        mode = "replace",
        minimumTokens = 5,
        maximumTokens = 5,
    },
    jackpot = {
        id = "jackpot",
        name = "Bounty Jackpot",
        description = "Every selected member becomes a four- or five-token bounty target.",
        mode = "replace",
        minimumTokens = 4,
        maximumTokens = 5,
    },
}

local ALIASES = {
    all = "all-bounty",
    bounty = "all-bounty",
    catalog = "all-bounty",
    mostwanted = "most-wanted",
}

local function filtered_roster(profile)
    local result = {}
    for _, bounty in ipairs(ROSTER) do
        if bounty.tokens >= (profile.minimumTokens or 1) and bounty.tokens <= (profile.maximumTokens or 5) then
            result[#result + 1] = bounty
        end
    end
    return result
end

function M.normalize_profile_id(profile_id)
    profile_id = util.trim(profile_id or ""):lower()
    profile_id = ALIASES[profile_id] or profile_id
    return PROFILES[profile_id] and profile_id or nil
end

function M.profile(profile_id)
    local normalized = M.normalize_profile_id(profile_id)
    return normalized and PROFILES[normalized] or nil
end

function M.is_custom(profile_id)
    local profile = M.profile(profile_id)
    return profile ~= nil and profile.backend == "custom-assault"
end

function M.profiles()
    local result = {}
    for _, profile_id in ipairs({ "all-bounty", "patrol", "mixed", "most-wanted", "kingpin", "jackpot", "native" }) do
        result[#result + 1] = PROFILES[profile_id]
    end
    return result
end

function M.profile_ids()
    local result = {}
    for _, profile in ipairs(M.profiles()) do
        result[#result + 1] = profile.id
    end
    return result
end

function M.roster()
    return util.deep_copy(ROSTER)
end

function M.new_selector(profile_id, occurrence_id)
    local profile = assert(M.profile(profile_id), "unknown bounty profile")
    local roster = filtered_roster(profile)
    local offset = #roster > 0 and (tonumber(util.hash32(occurrence_id or profile.id), 16) % #roster) or 0
    return {
        profile = profile,
        roster = roster,
        cursor = offset,
        replacements = 0,
    }
end

function M.next(selector)
    if selector.profile.mode == "native" or #selector.roster == 0 then
        return nil
    end
    if selector.profile.maximumReplacements and selector.replacements >= selector.profile.maximumReplacements then
        return nil
    end
    local index = (selector.cursor % #selector.roster) + 1
    selector.cursor = selector.cursor + 1
    selector.replacements = selector.replacements + 1
    return selector.roster[index]
end

function M.reset_selection(selector)
    selector.replacements = 0
end

return M

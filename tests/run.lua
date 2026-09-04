local separator = package.config:sub(1, 1)
local function join(...)
    return table.concat({ ... }, separator)
end
local root = "."
package.path = table.concat({
    join(root, "Scripts", "?.lua"),
    join(root, "Scripts", "?", "init.lua"),
    package.path,
}, ";")

local Config = require("ped.config")
local Director = require("ped.director")
local Bridge = require("ped.palworld")
local Rewards = require("ped.rewards")
local Scoreboard = require("ped.scoreboard")
local Store = require("ped.store")
local bounties = require("ped.bounties")
local json = require("ped.json")
local util = require("ped.util")

local tests = {}
local failures = 0

local function test(name, callback)
    tests[#tests + 1] = { name = name, callback = callback }
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "values differ", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(value, message)
    if not value then
        error(message or "expected truthy value", 2)
    end
end

local function damage(board, values)
    local record = {
        record_sequence = values.record_sequence,
        target_id = values.target_id,
        base_id = values.base_id or "base-a",
        health_budget = values.health_budget or 100,
        actual_damage = values.actual_damage,
        source_kind = values.source_kind or "direct_player",
        player_uid = values.player_uid,
        player_name = values.player_name,
    }
    return board:record_damage(record)
end

test("JSON round-trips objects, arrays, escapes, and unicode", function()
    local source = json.object({
        text = "line\nquote\"",
        enabled = true,
        count = 3,
        list = json.array({ "a", "b", "☃" }),
        emptyObject = json.object(),
        emptyArray = json.array(),
    })
    local encoded = json.encode(source)
    local decoded = json.decode(encoded)
    equal(decoded.text, source.text)
    equal(decoded.list[3], "☃")
    equal(json.encode(decoded.emptyObject), "{}")
    equal(json.encode(decoded.emptyArray), "[]")
    equal(json.decode('"\\uD83D\\uDE80"'), "🚀")
end)

test("JSON rejects malformed numbers and surrogate escapes", function()
    for _, text in ipairs({ "01", "1.", "1e", '"\\uD800"', '"\\uDC00"' }) do
        local ok = pcall(json.decode, text)
        equal(ok, false, "expected invalid JSON: " .. text)
    end
end)

test("default configuration is safe and valid", function()
    local config = Config.defaults()
    local valid, validation_error = Config.validate(config)
    truthy(valid, validation_error)
    equal(config.capabilities.startAllInvasions, false)
    equal(config.capabilities.grantItems, false)
    equal(config.siegeLeague.allowCrossBaseRoaming, true)
end)

test("configuration arrays replace defaults and live grants fail closed", function()
    local merged = util.deep_merge(Config.defaults(), json.decode('{"rewards":{"podium":[]}}'))
    equal(#merged.rewards.podium, 0)
    local config = Config.defaults()
    config.capabilities.grantItems = true
    local valid, validation_error = Config.validate(config)
    equal(valid, false)
    truthy(validation_error:match("grantItems"))
end)

test("all-bounty profile cycles the complete audited roster", function()
    local roster = bounties.roster()
    equal(#roster, 34)
    local selector = bounties.new_selector("all-bounty", "occurrence")
    local selected = {}
    local tiers = {}
    for _ = 1, 34 do
        local bounty = bounties.next(selector)
        truthy(bounty)
        selected[bounty.id] = true
        tiers[bounty.tokens] = (tiers[bounty.tokens] or 0) + 1
    end
    equal(util.count(selected), 34)
    equal(tiers[1], 12)
    equal(tiers[2], 9)
    equal(tiers[3], 6)
    equal(tiers[4], 6)
    equal(tiers[5], 1)
    equal(bounties.normalize_profile_id("bounty"), "all-bounty")
    equal(bounties.profile("kingpin").minimumTokens, 5)
end)

test("bridge replaces every selected member while preserving native level and companion", function()
    local previous_fname = _G.FName
    _G.FName = function(value) return value end
    local members_data = {
        { CharacterID = "NativeA", Level = 17, Otomo = "PalA" },
        { CharacterID = "NativeB", Level = 29, Otomo = "PalB" },
        { CharacterID = "NativeC", Level = 41, Otomo = "PalC" },
    }
    local members = {
        GetArrayNum = function() return #members_data end,
        ForEach = function(_, callback)
            for index, member in ipairs(members_data) do
                local element = {
                    get = function() return member end,
                    set = function(_, replacement) members_data[index] = replacement end,
                }
                if callback(index - 1, element) then break end
            end
        end,
    }
    local camp = { IsValid = function() return true end, GetId = function() return "base-a" end }
    local incident = { IsValid = function() return true end, InvaderType = 1, GroupGuid = "group-a", GetTargetCampModel = function() return camp end }
    local composition
    local logger = { info = function() end, warn = function() end, error = function(_, message) error(message) end }
    local bridge = Bridge.new({ config = Config.defaults(), logger = logger })
    bridge.director = {
        state = { event = { bases = { ["base-a"] = { status = "pending" } } } },
        on_composition_result = function(_, ...) composition = { ... } end,
    }
    bridge.event_open = true
    bridge.selection_open = true
    bridge.profile_id = "all-bounty"
    bridge.expected_bases["base-a"] = true
    bridge.bounty_selector = bounties.new_selector("all-bounty", "occurrence")
    bridge:_on_select_invaders(incident, members)
    _G.FName = previous_fname
    for index, member in ipairs(members_data) do
        truthy(member.CharacterID:match("^BOSS_"), "member " .. index .. " was not substituted")
        equal(member.Level, ({ 17, 29, 41 })[index])
        equal(member.Otomo, "Pal" .. ({ "A", "B", "C" })[index])
    end
    equal(composition[2], 3)
    equal(composition[3], 3)
    equal(composition[4], nil)
end)

test("bridge never substitutes visitor selections", function()
    local previous_fname = _G.FName
    _G.FName = function(value) return value end
    local member = { CharacterID = "Visitor", Level = 10, Otomo = "None" }
    local members = {
        GetArrayNum = function() return 1 end,
        ForEach = function(_, callback) callback(0, { get = function() return member end, set = function() end }) end,
    }
    local camp = { IsValid = function() return true end, GetId = function() return "base-a" end }
    local incident = { IsValid = function() return true end, InvaderType = 2, GetTargetCampModel = function() return camp end }
    local bridge = Bridge.new({ config = Config.defaults(), logger = { info = function() end, warn = function() end, error = function() end } })
    bridge.event_open = true
    bridge.selection_open = true
    bridge.profile_id = "all-bounty"
    bridge.expected_bases["base-a"] = true
    bridge.bounty_selector = bounties.new_selector("all-bounty", "occurrence")
    bridge:_on_select_invaders(incident, members)
    _G.FName = previous_fname
    equal(member.CharacterID, "Visitor")
end)

test("failed bounty mutation restores every member and selector cursor", function()
    local previous_fname = _G.FName
    _G.FName = function(value) return value end
    local members_data = {
        { CharacterID = "NativeA", Level = 17 },
        { CharacterID = "NativeB", Level = 29 },
        { CharacterID = "NativeC", Level = 41 },
    }
    local failed_once = false
    local members = {
        GetArrayNum = function() return #members_data end,
        ForEach = function(_, callback)
            for index, member in ipairs(members_data) do
                callback(index - 1, {
                    get = function() return member end,
                    set = function()
                        if index == 2 and not failed_once then failed_once = true; error("injected set failure") end
                    end,
                })
            end
        end,
    }
    local camp = { IsValid = function() return true end, GetId = function() return "base-a" end }
    local incident = { IsValid = function() return true end, InvaderType = 1, GroupGuid = "group-a", GetTargetCampModel = function() return camp end }
    local composition_error
    local bridge = Bridge.new({ config = Config.defaults(), logger = { info = function() end, warn = function() end, error = function() end } })
    bridge.director = {
        state = { event = { bases = { ["base-a"] = { status = "pending" } } } },
        on_composition_result = function(_, _, _, _, failure) composition_error = failure end,
    }
    bridge.event_open = true
    bridge.selection_open = true
    bridge.profile_id = "all-bounty"
    bridge.expected_bases["base-a"] = true
    bridge.bounty_selector = bounties.new_selector("all-bounty", "occurrence")
    local original_cursor = bridge.bounty_selector.cursor
    bridge:_on_select_invaders(incident, members)
    _G.FName = previous_fname
    equal(members_data[1].CharacterID, "NativeA")
    equal(members_data[2].CharacterID, "NativeB")
    equal(members_data[3].CharacterID, "NativeC")
    equal(bridge.bounty_selector.cursor, original_cursor)
    truthy(composition_error:match("injected set failure"))
end)

test("second native group at the same pending base is never substituted", function()
    local previous_fname = _G.FName
    _G.FName = function(value) return value end
    local function member_array(member)
        return {
            GetArrayNum = function() return 1 end,
            ForEach = function(_, callback)
                callback(0, { get = function() return member end, set = function() end })
            end,
        }
    end
    local camp = { IsValid = function() return true end, GetId = function() return "base-a" end }
    local first = { IsValid = function() return true end, InvaderType = 1, GroupGuid = "group-a", BroadcastGroupGuid = "broadcast-a", GetTargetCampModel = function() return camp end }
    local second = { IsValid = function() return true end, InvaderType = 1, GroupGuid = "group-b", BroadcastGroupGuid = "broadcast-b", GetTargetCampModel = function() return camp end }
    local first_member = { CharacterID = "NativeA", Level = 10 }
    local second_member = { CharacterID = "NativeB", Level = 20 }
    local bridge = Bridge.new({ config = Config.defaults(), logger = { info = function() end, warn = function() end, error = function() end } })
    bridge.director = {
        state = { event = { bases = { ["base-a"] = { status = "pending" } } } },
        on_composition_result = function() end,
    }
    bridge.event_open = true
    bridge.profile_id = "all-bounty"
    bridge.expected_bases["base-a"] = true
    bridge.bounty_selector = bounties.new_selector("all-bounty", "occurrence")
    bridge:_on_select_invaders(first, member_array(first_member))
    bridge:_on_select_invaders(second, member_array(second_member))
    _G.FName = previous_fname
    truthy(first_member.CharacterID:match("^BOSS_"))
    equal(second_member.CharacterID, "NativeB")
    equal(bridge.owned_groups["group-b"], nil)
    equal(bridge.owned_groups["broadcast-b"], nil)
end)

test("journal and atomic snapshot survive reload", function()
    local files = {}
    local filesystem = {
        ensure_directory = function() return true end,
        exists = function(file_path) return files[file_path] ~= nil end,
        read = function(file_path) return files[file_path] end,
        write = function(file_path, content) files[file_path] = content; return true end,
        append = function(file_path, content) files[file_path] = (files[file_path] or "") .. content; return true end,
        remove = function(file_path) files[file_path] = nil; return true end,
        rename = function(source, destination)
            if files[source] == nil then return false, "not found" end
            files[destination] = files[source]
            files[source] = nil
            return true
        end,
    }
    local logger = { warn = function() end, error = function() end }
    local store = Store.new("memory", logger, filesystem)
    local appended = store:append("test", { value = 7 })
    truthy(appended)
    truthy(store:save_snapshot({ state = "ok", values = json.array({ 1, 2 }) }))
    local restored = Store.new("memory", logger, filesystem)
    equal(restored.sequence, 1)
    local snapshot = restored:load_snapshot()
    equal(snapshot.state, "ok")
    equal(snapshot.values[2], 2)
end)

test("uncheckpointed journal tail blocks stale snapshot recovery", function()
    local files = {}
    local filesystem = {
        ensure_directory = function() return true end,
        exists = function(file_path) return files[file_path] ~= nil end,
        read = function(file_path) return files[file_path] end,
        write = function(file_path, content) files[file_path] = content; return true end,
        append = function(file_path, content) files[file_path] = (files[file_path] or "") .. content; return true end,
        remove = function(file_path) files[file_path] = nil; return true end,
        rename = function(source, destination) files[destination] = files[source]; files[source] = nil; return true end,
    }
    local logger = { warn = function() end, error = function() end }
    local store = Store.new("memory", logger, filesystem)
    truthy(store:append("one", {}))
    truthy(store:save_snapshot({ value = 1 }))
    truthy(store:append("two", {}))
    local restored = Store.new("memory", logger, filesystem)
    local payload, _, restore_error = restored:load_snapshot()
    equal(payload, nil)
    truthy(restore_error:match("not anchored"))
end)

test("cross-base roaming accumulates contribution and kills", function()
    local board = Scoreboard.new({ occurrence_id = "event-1", target_points = 1000 })
    truthy(damage(board, { record_sequence = 1, target_id = "target-a", base_id = "base-a", actual_damage = 100, player_uid = "player-1" }))
    board:close_target({ target_id = "target-a", source_kind = "direct_player", player_uid = "player-1" })
    truthy(damage(board, { record_sequence = 2, target_id = "target-b", base_id = "base-b", actual_damage = 100, player_uid = "player-1" }))
    board:close_target({ target_id = "target-b", source_kind = "active_pal", player_uid = "player-1" })
    local result = board:player_result("player-1")
    equal(result.score, 2000)
    equal(result.finalHits, 2)
    equal(result.basesDefended, 2)
end)

test("uncredited and overkill damage consume the shared target budget", function()
    local board = Scoreboard.new({ occurrence_id = "event-2", target_points = 1000 })
    damage(board, { record_sequence = 1, target_id = "target", actual_damage = 60, source_kind = "uncredited" })
    local accepted, result = damage(board, { record_sequence = 2, target_id = "target", actual_damage = 100, player_uid = "player-1" })
    truthy(accepted)
    equal(result.credited, 40)
    equal(board:player_result("player-1").score, 400)
    local target = board:to_state().targets.target
    equal(target.consumedDamage, 100)
    equal(target.uncreditedDamage, 60)
end)

test("duplicate damage and duplicate death never score twice", function()
    local board = Scoreboard.new({ occurrence_id = "event-3", target_points = 1000 })
    damage(board, { record_sequence = 1, target_id = "target", actual_damage = 50, player_uid = "player-1" })
    local accepted, reason = damage(board, { record_sequence = 1, target_id = "target", actual_damage = 50, player_uid = "player-1" })
    equal(accepted, false)
    equal(reason, "duplicate")
    truthy(board:close_target({ target_id = "target", source_kind = "direct_player", player_uid = "player-1" }))
    local closed, close_reason = board:close_target({ target_id = "target", source_kind = "direct_player", player_uid = "player-1" })
    equal(closed, false)
    equal(close_reason, "already_closed")
    equal(board:player_result("player-1").finalHits, 1)
end)

test("contribution outranks final-hit stealing", function()
    local board = Scoreboard.new({ occurrence_id = "event-4", target_points = 1000 })
    damage(board, { record_sequence = 1, target_id = "target", actual_damage = 90, player_uid = "worker" })
    damage(board, { record_sequence = 2, target_id = "target", actual_damage = 10, player_uid = "finisher" })
    board:close_target({ target_id = "target", source_kind = "direct_player", player_uid = "finisher" })
    local rankings = board:rankings()
    equal(rankings[1].uid, "worker")
    equal(rankings[2].finalHits, 1)
end)

test("native same-base lifecycle is represented once", function()
    local now = 1000
    local config = Config.defaults()
    config.capabilities.startAllInvasions = true
    config.capabilities.observeCombat = true
    config.capabilities.observeInvasions = true
    local store = {
        records = {},
        load_snapshot = function() return nil end,
        append = function(self, kind, data) self.records[#self.records + 1] = { kind = kind, data = data }; return true end,
        save_snapshot = function(self, payload) self.payload = util.deep_copy(payload); return true end,
    }
    local bridge = {
        announcements = {},
        starts = 0,
        grants = {},
        preflight_start = function() return true end,
        begin_event_discovery = function() return { "base-a" } end,
        start_all_invasions = function(self) self.starts = self.starts + 1; return true end,
        announce = function(self, message) self.announcements[#self.announcements + 1] = message; return true end,
        active_invasion_count = function() return 0 end,
        grant_item = function(self, obligation) self.grants[#self.grants + 1] = obligation.key; return { status = "delivered", before_count = 0, after_count = obligation.count } end,
    }
    local logger = { info = function() end, warn = function() end, error = function() end }
    local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger, clock = function() return now end })
    local started = director:start("test", "native")
    truthy(started)
    equal(bridge.starts, 1)
    truthy(director:on_invasion_start("base-a", "group-a"))
    truthy(director:on_invasion_start("base-a", "group-a"))
    equal(util.count(director.state.event.bases), 1)
end)

test("damage from a different native group at the same base never scores", function()
    local now = 1500
    local config = Config.defaults()
    config.capabilities.startAllInvasions = true
    config.capabilities.observeCombat = true
    config.capabilities.observeInvasions = true
    local store = {
        load_snapshot = function() return nil end,
        append = function() return true end,
        save_snapshot = function() return true end,
    }
    local bridge = {
        preflight_start = function() return true end,
        begin_event_discovery = function() return { "base-a" } end,
        start_all_invasions = function() return true end,
        announce = function() return true end,
        active_invasion_count = function() return 0 end,
    }
    local logger = { info = function() end, warn = function() end, error = function() end }
    local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger, clock = function() return now end })
    truthy(director:start("test", "native"))
    truthy(director:on_invasion_start("base-a", "group-a"))
    local accepted, reason = director:on_damage({ record_sequence = 1, target_id = "foreign", base_id = "base-a", group_id = "group-b", health_budget = 100, actual_damage = 100, source_kind = "direct_player", player_uid = "player-1" })
    equal(accepted, false)
    equal(reason, "group_not_owned")
    equal(director.scoreboard:stats().targets, 0)
end)

test("composition failure removes existing score and final-hit tie credit", function()
    local now = 1700
    local config = Config.defaults()
    config.capabilities.startAllInvasions = true
    config.capabilities.observeCombat = true
    config.capabilities.observeInvasions = true
    local store = { load_snapshot = function() return nil end, append = function() return true end, save_snapshot = function() return true end }
    local bridge = {
        preflight_start = function() return true end,
        begin_event_discovery = function() return { "base-a" } end,
        start_all_invasions = function() return true end,
        announce = function() return true end,
        active_invasion_count = function() return 0 end,
    }
    local logger = { info = function() end, warn = function() end, error = function() end }
    local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger, clock = function() return now end })
    truthy(director:start("test", "native"))
    truthy(director:on_invasion_start("base-a", "group-a"))
    truthy(director:on_damage({ record_sequence = 1, target_id = "target", base_id = "base-a", group_id = "group-a", health_budget = 100, actual_damage = 100, source_kind = "direct_player", player_uid = "player-1" }))
    truthy(director:on_death({ target_id = "target", base_id = "base-a", group_id = "group-a", source_kind = "direct_player", player_uid = "player-1" }))
    equal(director.scoreboard:player_result("player-1").finalHits, 1)
    director:on_composition_result("base-a", 0, 1, "selection_identity_conflict")
    local result = director.scoreboard:player_result("player-1")
    equal(result.score, 0)
    equal(result.finalHits, 0)
end)

test("user chat can start the all-bounty alarm only under configured policy and cooldown", function()
    local now = 10000
    local config = Config.defaults()
    config.capabilities.startAllInvasions = true
    config.capabilities.observeCombat = true
    config.capabilities.observeInvasions = true
    config.capabilities.substituteBountyMembers = true
    config.siegeLeague.chatStartPolicy = "anyUser"
    local store = {
        load_snapshot = function() return nil end,
        append = function() return true end,
        save_snapshot = function() return true end,
    }
    local bridge = {
        announcements = {}, starts = 0,
        preflight_start = function(self, profile) self.preflightProfile = profile; return true end,
        begin_event_discovery = function(self, profile) self.discoveryProfile = profile; return { "base-a" } end,
        end_event_tracking = function() end,
        start_all_invasions = function(self, profile) self.starts = self.starts + 1; self.startProfile = profile; return true end,
        announce = function(self, message) self.announcements[#self.announcements + 1] = message; return true end,
        active_invasion_count = function() return 0 end,
    }
    local logger = { info = function() end, warn = function() end, error = function() end }
    local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger, clock = function() return now end })
    truthy(director:handle_chat("11111111-1111-1111-1111-111111111111", "!siege start bounty"))
    equal(bridge.starts, 1)
    equal(bridge.preflightProfile, "all-bounty")
    equal(bridge.discoveryProfile, "all-bounty")
    equal(director.state.event.profileId, "all-bounty")
    truthy(director:abort("test"))
    truthy(director:reset())
    now = now + 10
    truthy(director:handle_chat("11111111-1111-1111-1111-111111111111", "!siege start patrol"))
    equal(bridge.starts, 1)
    truthy(bridge.announcements[#bridge.announcements]:match("cooldown"))
end)

test("operator-only chat denies users and accepts canonicalized operator UID", function()
    local now = 20000
    local config = Config.defaults()
    config.capabilities.startAllInvasions = true
    config.capabilities.observeCombat = true
    config.capabilities.observeInvasions = true
    config.capabilities.substituteBountyMembers = true
    config.operatorUids = json.array({ "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" })
    local store = {
        load_snapshot = function() return nil end,
        append = function() return true end,
        save_snapshot = function() return true end,
    }
    local bridge = {
        announcements = {}, starts = 0,
        preflight_start = function() return true end,
        begin_event_discovery = function() return { "base-a" } end,
        start_all_invasions = function(self) self.starts = self.starts + 1; return true end,
        announce = function(self, message) self.announcements[#self.announcements + 1] = message; return true end,
        active_invasion_count = function() return 0 end,
    }
    local logger = { info = function() end, warn = function() end, error = function() end }
    local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger, clock = function() return now end })
    truthy(director:handle_chat("11111111-1111-1111-1111-111111111111", "!siege start all-bounty"))
    equal(bridge.starts, 0)
    now = now + 10
    truthy(director:handle_chat("aaaaaaaabbbbccccddddeeeeeeeeeeee", "!siege start jackpot"))
    equal(bridge.starts, 1)
    equal(director.state.event.profileId, "jackpot")
end)

test("full two-base Siege League resolves and creates unique reward channels", function()
    local now = 2000
    local config = Config.defaults()
    config.capabilities.startAllInvasions = true
    config.capabilities.observeCombat = true
    config.capabilities.observeInvasions = true
    local store = {
        records = {},
        load_snapshot = function() return nil end,
        append = function(self, kind, data) self.records[#self.records + 1] = { kind = kind, data = data }; return true end,
        save_snapshot = function(self, payload) self.payload = util.deep_copy(payload); return true end,
    }
    local bridge = {
        announcements = {}, starts = 0, grants = {},
        preflight_start = function() return true end,
        begin_event_discovery = function() return { "base-a", "base-b" } end,
        start_all_invasions = function(self) self.starts = self.starts + 1; return true end,
        announce = function(self, message) self.announcements[#self.announcements + 1] = message; return true end,
        active_invasion_count = function() return 0 end,
        grant_item = function(self, obligation) self.grants[#self.grants + 1] = obligation.key; return { status = "delivered", before_count = 0, after_count = obligation.count } end,
    }
    local logger = { info = function() end, warn = function() end, error = function() end }
    local director = Director.new({ config = config, store = store, bridge = bridge, logger = logger, clock = function() return now end })
    truthy(director:start("test", "native"))
    director:on_invasion_start("base-a", "group-a")
    director:on_invasion_start("base-b", "group-b")
    director:on_damage({ record_sequence = 1, target_id = "target-a", base_id = "base-a", group_id = "group-a", health_budget = 100, actual_damage = 100, source_kind = "direct_player", player_uid = "player-1", player_name = "Alice" })
    director:on_death({ target_id = "target-a", base_id = "base-a", group_id = "group-a", source_kind = "direct_player", player_uid = "player-1" })
    director:on_damage({ record_sequence = 2, target_id = "target-b", base_id = "base-b", group_id = "group-b", health_budget = 100, actual_damage = 100, source_kind = "active_pal", player_uid = "player-1", player_name = "Alice" })
    director:on_death({ target_id = "target-b", base_id = "base-b", group_id = "group-b", source_kind = "active_pal", player_uid = "player-1" })
    director:on_invasion_end("base-a", "group-a")
    director:on_invasion_end("base-b", "group-b")
    now = now + 80
    director:tick()
    equal(director.state.status, "completed")
    local rankings = director.state.lastEvent.rankings
    equal(rankings[1].score, 2000)
    equal(rankings[1].basesDefended, 2)
    local summary = director.rewards:summary()
    equal(summary.pending, 4, "participation + two base completions + first place")
    local processed = director.rewards:process(bridge, 8, function() return true end)
    equal(processed, 4)
    equal(#bridge.grants, 4)
end)

test("reward keys are idempotent across repeated resolution inputs", function()
    local persisted = 0
    local rewards = Rewards.new({ persist = function() persisted = persisted + 1; return true end })
    local spec = { occurrence_id = "e", definition_id = "podium", player_uid = "p", rank = 1, item_id = "BountyProof_1", count = 5 }
    local first, created = rewards:create(spec)
    truthy(created)
    local second, created_again = rewards:create(spec)
    equal(created_again, false)
    equal(first.key, second.key)
    equal(persisted, 1)
end)

test("reward grant never runs when durable intent fails", function()
    local rewards = Rewards.new({ persist = function(kind)
        if kind == "reward_grant_intent" then return false, "disk full" end
        return true
    end })
    local obligation = rewards:create({ occurrence_id = "e", definition_id = "podium", player_uid = "p", rank = 1, item_id = "BountyProof_1", count = 5 })
    truthy(obligation)
    local calls = 0
    local processed, process_error = rewards:process({ grant_item = function() calls = calls + 1; return { status = "delivered" } end }, 1, function() return true end)
    equal(processed, 0)
    equal(calls, 0)
    truthy(process_error:match("disk full"))
end)

for _, entry in ipairs(tests) do
    local ok, failure = xpcall(entry.callback, debug.traceback)
    if ok then
        io.write("PASS ", entry.name, "\n")
    else
        failures = failures + 1
        io.stderr:write("FAIL ", entry.name, "\n", tostring(failure), "\n")
    end
end

io.write(string.format("%d tests, %d failures\n", #tests, failures))
if failures > 0 then
    os.exit(1)
end

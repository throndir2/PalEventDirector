local util = require("ped.util")

local Bridge = {}
Bridge.__index = Bridge

local HOOKS = {
    damage = "/Script/Pal.PalEventNotify_Character:OnCharacterDamaged_ServerInternal",
    death = "/Script/Pal.PalEventNotify_Character:OnCharacterDead_ServerInternal",
    invasion_start = "/Script/Pal.PalInvaderManager:BroadcastInvaderStart",
    invasion_end = "/Script/Pal.PalInvaderManager:BroadcastInvaderEnd",
    invasion_timeout = "/Script/Pal.PalInvaderManager:BroadcastInvaderWaveTimeup",
    invasion_cancel = "/Script/Pal.PalInvaderManager:BroadcastInvaderCancel",
    chat = "/Script/Pal.PalPlayerController:EnterChat_Receive",
}

local function global(name)
    return rawget(_G, name)
end

local function unwrap(value)
    if value == nil then
        return nil
    end
    local ok, result = pcall(function()
        return value:get()
    end)
    if ok then
        return result
    end
    return value
end

local function valid(object)
    if object == nil then
        return false
    end
    local ok, result = pcall(function()
        return object:IsValid()
    end)
    return ok and result == true
end

local function property(object, name)
    object = unwrap(object)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object[name]
    end)
    return ok and unwrap(value) or nil
end

local function call(object, method_name, ...)
    object = unwrap(object)
    if not valid(object) then
        return false, "invalid object for " .. method_name
    end
    local arguments = { ... }
    local ok, result = pcall(function()
        local method = object[method_name]
        return method(object, table.unpack(arguments))
    end)
    return ok, result
end

local function to_string(value)
    value = unwrap(value)
    if value == nil then
        return ""
    end
    if type(value) == "string" then
        return value
    end
    local ok, result = pcall(function()
        return value:ToString()
    end)
    if ok then
        return tostring(result)
    end
    return tostring(value)
end

local function as_integer(value)
    value = unwrap(value)
    if type(value) == "number" then
        return math.floor(value)
    end
    local number = tonumber(to_string(value))
    return number and math.floor(number) or nil
end

local function guid_string(value)
    value = unwrap(value)
    if value == nil then
        return nil
    end
    if type(value) == "string" then
        return value:lower()
    end
    local components = {}
    for _, name in ipairs({ "A", "B", "C", "D" }) do
        local component = as_integer(property(value, name))
        if component == nil then
            components = nil
            break
        end
        components[#components + 1] = string.format("%08x", component & 0xffffffff)
    end
    local result = components and table.concat(components, "-") or to_string(value)
    result = result:lower():gsub("[{}]", "")
    if result == "" or not result:find("[^0%-]") then
        return nil
    end
    return result
end

local function full_name(object)
    object = unwrap(object)
    if not valid(object) then
        return nil
    end
    local ok, result = call(object, "GetFullName")
    return ok and to_string(result) or nil
end

function Bridge.new(options)
    return setmetatable({
        config = assert(options.config),
        logger = assert(options.logger),
        director = nil,
        hook_ids = {},
        damage_sequence = 0,
        timed_out_bases = {},
        event_open = false,
        discovery_open = false,
        owned_groups = {},
        member_context = {},
        player_names = {},
        utility = nil,
        loop_handle = nil,
        registered = false,
    }, Bridge)
end

function Bridge:attach_director(director)
    self.director = director
end

function Bridge:begin_event_discovery()
    self.event_open = true
    self.discovery_open = true
    self.owned_groups = {}
    self.member_context = {}
end

function Bridge:close_event_discovery()
    self.discovery_open = false
end

function Bridge:end_event_tracking()
    self.event_open = false
    self.discovery_open = false
    self.owned_groups = {}
    self.member_context = {}
end

function Bridge:_static_find(path)
    local finder = global("StaticFindObject")
    if type(finder) ~= "function" then
        return nil
    end
    local ok, object = pcall(finder, path)
    return ok and object or nil
end

function Bridge:_find_first(class_name)
    local finder = global("FindFirstOf")
    if type(finder) ~= "function" then
        return nil
    end
    local ok, object = pcall(finder, class_name)
    return ok and object or nil
end

function Bridge:_find_all(class_name)
    local finder = global("FindAllOf")
    if type(finder) ~= "function" then
        return {}
    end
    local ok, objects = pcall(finder, class_name)
    return ok and objects or {}
end

function Bridge:_utility()
    if valid(self.utility) then
        return self.utility
    end
    local class = self:_static_find("/Script/Pal.PalUtility")
    if valid(class) then
        local ok, cdo = call(class, "GetCDO")
        if ok and valid(cdo) then
            self.utility = cdo
            return cdo
        end
    end
    local default = self:_static_find("/Script/Pal.Default__PalUtility")
    if valid(default) then
        self.utility = default
        return default
    end
    return nil
end

function Bridge:_register_hook(name, path, callback)
    local register = global("RegisterHook")
    if type(register) ~= "function" then
        return false, "RegisterHook is unavailable"
    end
    local ok, pre_id, post_id = pcall(register, path, function() end, callback)
    if not ok then
        return false, tostring(pre_id)
    end
    self.hook_ids[name] = { path = path, pre = pre_id, post = post_id }
    return true
end

function Bridge:_base_id_from_parameter(parameter)
    parameter = unwrap(parameter)
    local base = property(parameter, "TargetBaseCamp")
    if not valid(base) then
        return nil
    end
    local ok, id = call(base, "GetId")
    return ok and guid_string(id) or nil
end

function Bridge:_lifecycle_context(parameter)
    parameter = unwrap(parameter)
    return self:_base_id_from_parameter(parameter), guid_string(property(parameter, "GroupGuid"))
end

function Bridge:_individual_id(actor)
    local utility = self:_utility()
    if not valid(utility) or not valid(actor) then
        return nil, nil
    end
    local ok, instance = call(utility, "GetIndividualIDByActor", actor)
    if not ok then
        return nil, nil
    end
    return guid_string(property(instance, "InstanceId")), guid_string(property(instance, "PlayerUId"))
end

function Bridge:_player_uid(actor)
    local utility = self:_utility()
    if not valid(utility) then
        return nil
    end
    local ok, uid = call(utility, "GetPlayerUIDByActor", actor)
    return ok and guid_string(uid) or nil
end

function Bridge:_unwrap_damage_source(actor)
    actor = unwrap(actor)
    local visited = {}
    for _ = 1, 4 do
        if not valid(actor) then
            return nil
        end
        local name = full_name(actor) or tostring(actor)
        if visited[name] then
            return actor
        end
        visited[name] = true
        local replacement
        for _, method in ipairs({ "GetWeaponAttacker", "GetOwnerCharacter" }) do
            local ok, candidate = call(actor, method)
            if ok and valid(candidate) and candidate ~= actor then
                replacement = candidate
                break
            end
        end
        if not replacement then
            return actor
        end
        actor = replacement
    end
    return actor
end

function Bridge:_source(actor)
    actor = self:_unwrap_damage_source(actor)
    if not valid(actor) then
        return { source_kind = "uncredited" }
    end
    local utility = self:_utility()
    local player_class = self:_static_find("/Script/Pal.PalPlayerCharacter")
    local is_player = false
    if valid(player_class) then
        local ok, result = pcall(function()
            return actor:IsA(player_class)
        end)
        is_player = ok and result == true
    end
    if is_player then
        local uid = self:_player_uid(actor)
        return {
            source_kind = uid and "direct_player" or "uncredited",
            player_uid = uid,
            player_name = self:_actor_display_name(actor, uid),
            source_id = select(1, self:_individual_id(actor)),
        }
    end

    local active_pal = false
    if valid(utility) then
        local ok, result = call(utility, "IsPlayersOtomo", actor)
        active_pal = ok and result == true
    end
    local instance_id, owner_uid = self:_individual_id(actor)
    if active_pal and owner_uid then
        return {
            source_kind = "active_pal",
            player_uid = owner_uid,
            player_name = self:_player_display_name(owner_uid),
            source_id = instance_id,
        }
    end

    if owner_uid then
        local parameter_ok, parameter = call(utility, "GetIndividualCharacterParameterByActor", actor)
        if parameter_ok and valid(parameter) then
            local camp_ok, camp_id = call(parameter, "GetBaseCampId")
            if camp_ok and guid_string(camp_id) then
                return {
                    source_kind = "base_worker",
                    player_uid = owner_uid,
                    player_name = self:_player_display_name(owner_uid),
                    source_id = instance_id,
                }
            end
        end
    end
    return { source_kind = "uncredited", source_id = instance_id }
end

function Bridge:_actor_display_name(actor, fallback_uid)
    local ok, name = call(actor, "GetFName")
    local text = ok and to_string(name) or ""
    if text == "" then
        text = util.mask_uid(fallback_uid)
    end
    return util.sanitize_text(text, 80)
end

function Bridge:_player_display_name(uid)
    if self.player_names[uid] then
        return self.player_names[uid]
    end
    for _, controller in ipairs(self:_find_all("PalPlayerController")) do
        if valid(controller) then
            local ok, candidate = call(controller, "GetPlayerUId")
            if ok and guid_string(candidate) == uid then
                local state_ok, player_state = call(controller, "GetPalPlayerState")
                if state_ok and valid(player_state) then
                    local name_ok, name = call(player_state, "GetPlayerName")
                    if name_ok and to_string(name) ~= "" then
                        local display_name = util.sanitize_text(to_string(name), 80)
                        self.player_names[uid] = display_name
                        return display_name
                    end
                end
                return self:_actor_display_name(controller, uid)
            end
        end
    end
    return util.mask_uid(uid)
end

function Bridge:_target_context(defender)
    defender = unwrap(defender)
    if not valid(defender) then
        return nil, "invalid defender"
    end
    local utility = self:_utility()
    if not valid(utility) then
        return nil, "PalUtility unavailable"
    end
    local handle_ok, handle = call(utility, "GetIndividualCharacterHandleByActor", defender)
    if not handle_ok or not valid(handle) then
        return nil, "defender handle unavailable"
    end
    local instance_id = select(1, self:_individual_id(defender))
    local target_id = instance_id or full_name(defender)
    if not target_id then
        return nil, "defender identity unavailable"
    end
    local cached = self.member_context[target_id]
    if cached then
        return cached
    end
    local base_id
    for _, incident in ipairs(self:_find_all("PalInvaderIncidentBase")) do
        if valid(incident) then
            local member_ok, is_member = call(incident, "IsGroupCharacter", handle)
            if member_ok and is_member == true then
                local camp_ok, camp = call(incident, "GetTargetCampModel")
                if camp_ok and valid(camp) then
                    local id_ok, id = call(camp, "GetId")
                    if id_ok then
                        base_id = guid_string(id)
                        break
                    end
                end
            end
        end
    end
    if not base_id then
        return nil, "defender is not a native invasion group member"
    end
    local parameter_ok, parameter = call(utility, "GetIndividualCharacterParameterByActor", defender)
    if not parameter_ok or not valid(parameter) then
        return nil, "defender parameter unavailable"
    end
    local hp_ok, maximum_hp = call(parameter, "GetMaxHP")
    maximum_hp = hp_ok and as_integer(maximum_hp) or nil
    if not maximum_hp or maximum_hp <= 0 then
        return nil, "defender maximum HP unavailable"
    end
    local context = {
        target_id = target_id,
        base_id = base_id,
        health_budget = maximum_hp,
        target_name = self:_actor_display_name(defender, target_id),
    }
    self.member_context[target_id] = context
    return context
end

function Bridge:_on_damage(damage_parameter)
    if self.config.diagnostics.traceHooks then
        self.logger:debug("Damage hook", { eventOpen = self.event_open })
    end
    if self.config.diagnostics.observationProbe and not self.event_open then
        local damage = unwrap(damage_parameter)
        self.logger:info("Damage observation probe", {
            actualDamage = as_integer(property(damage, "ActualDamage")),
            attacker = full_name(property(damage, "Attacker")),
            defender = full_name(property(damage, "Defender")),
        })
        return
    end
    if not self.director or not self.event_open then
        return
    end
    local damage = unwrap(damage_parameter)
    local defender = property(damage, "Defender")
    local target = self:_target_context(defender)
    if not target then
        return
    end
    local actual_damage = as_integer(property(damage, "ActualDamage"))
    if not actual_damage or actual_damage < 0 then
        return
    end
    local source = self:_source(property(damage, "Attacker"))
    self.damage_sequence = self.damage_sequence + 1
    target.record_sequence = self.damage_sequence
    target.actual_damage = actual_damage
    target.source_kind = source.source_kind
    target.player_uid = source.player_uid
    target.player_name = source.player_name
    target.source_id = source.source_id
    self.director:on_damage(target)
end

function Bridge:_on_death(dead_parameter)
    if self.config.diagnostics.traceHooks then
        self.logger:debug("Death hook", { eventOpen = self.event_open })
    end
    if self.config.diagnostics.observationProbe and not self.event_open then
        local dead = unwrap(dead_parameter)
        self.logger:info("Death observation probe", {
            deadType = as_integer(property(dead, "DeadType")),
            attacker = full_name(property(dead, "LastAttacker")),
            defender = full_name(property(dead, "SelfActor")),
        })
        return
    end
    if not self.director or not self.event_open then
        return
    end
    local dead = unwrap(dead_parameter)
    local target = self:_target_context(property(dead, "SelfActor"))
    if not target then
        return
    end
    local source = self:_source(property(dead, "LastAttacker"))
    local dead_type = as_integer(property(dead, "DeadType"))
    if dead_type ~= 1 then
        source = { source_kind = "uncredited" }
    end
    self.damage_sequence = self.damage_sequence + 1
    target.record_sequence = self.damage_sequence
    target.actual_damage = 0
    target.source_kind = source.source_kind
    target.player_uid = source.player_uid
    target.player_name = source.player_name
    self.director:on_damage(target)
    self.director:on_death({
        target_id = target.target_id,
        source_kind = source.source_kind,
        player_uid = source.player_uid,
        reason = "defeated",
        dead_type = dead_type,
    })
end

function Bridge:register()
    if self.registered then
        return true
    end
    local required = {}
    if self.config.capabilities.observeCombat then
        required[#required + 1] = { "damage", HOOKS.damage, function(_, parameter) self:_on_damage(parameter) end }
        required[#required + 1] = { "death", HOOKS.death, function(_, parameter) self:_on_death(parameter) end }
    end
    if self.config.capabilities.observeInvasions then
        required[#required + 1] = { "invasion_start", HOOKS.invasion_start, function(_, parameter)
            local base_id, group_id = self:_lifecycle_context(parameter)
            if self.config.diagnostics.traceHooks then self.logger:info("Invasion start hook", { base = util.mask_uid(base_id), group = util.mask_uid(group_id), discovery = self.discovery_open }) end
            if base_id and group_id and self.director and self.event_open and (self.discovery_open or self.owned_groups[group_id]) then
                self.owned_groups[group_id] = base_id
                self.director:on_invasion_start(base_id, group_id)
            end
        end }
        required[#required + 1] = { "invasion_timeout", HOOKS.invasion_timeout, function(_, parameter)
            local base_id, group_id = self:_lifecycle_context(parameter)
            if self.config.diagnostics.traceHooks then self.logger:info("Invasion timeout hook", { base = util.mask_uid(base_id), group = util.mask_uid(group_id) }) end
            if base_id and group_id and self.owned_groups[group_id] and self.director then
                self.timed_out_bases[base_id] = true
                self.director:on_invasion_timeout(base_id, group_id)
            end
        end }
        required[#required + 1] = { "invasion_end", HOOKS.invasion_end, function(_, parameter)
            local base_id, group_id = self:_lifecycle_context(parameter)
            if self.config.diagnostics.traceHooks then self.logger:info("Invasion end hook", { base = util.mask_uid(base_id), group = util.mask_uid(group_id) }) end
            if base_id and group_id and self.owned_groups[group_id] and self.director then
                self.director:on_invasion_end(base_id, group_id)
                self.owned_groups[group_id] = nil
                self.timed_out_bases[base_id] = nil
            end
        end }
        required[#required + 1] = { "invasion_cancel", HOOKS.invasion_cancel, function()
            if self.director then self.director:on_invasion_cancel() end
        end }
    end
    if self.config.capabilities.chatCommands then
        required[#required + 1] = { "chat", HOOKS.chat, function(context, message)
            if not self.director then return end
            local controller = unwrap(context)
            local ok, uid = call(controller, "GetPlayerUId")
            uid = ok and guid_string(uid) or nil
            if uid then self.director:handle_chat(uid, to_string(message)) end
        end }
    end

    for _, specification in ipairs(required) do
        local ok, hook_error = self:_register_hook(specification[1], specification[2], specification[3])
        if not ok then
            self:unregister()
            return false, specification[1] .. " hook failed: " .. hook_error
        end
    end

    local register_console = global("RegisterConsoleCommandGlobalHandler")
    if type(register_console) == "function" then
        pcall(register_console, "ped", function(command, parts)
            local arguments = {}
            if type(parts) == "table" then
                for index = 1, #parts do
                    arguments[#arguments + 1] = tostring(parts[index])
                end
            else
                local text = tostring(command or "")
                arguments[1] = text:match("^%S+%s+(.+)$") or "status"
            end
            local ok, result = self.director:handle_operator_command(table.concat(arguments, " "), "console")
            self.logger:info(ok and "Console command completed" or "Console command failed", { result = result })
            return true
        end)
    end

    local poll = function()
        if self.director then
            local ok, tick_error = xpcall(function() self.director:tick() end, debug.traceback)
            if not ok then
                self.logger:error("Director tick failed", { error = tick_error })
            end
        end
    end
    local loop = global("LoopInGameThreadWithDelay")
    if type(loop) == "function" then
        local ok, handle = pcall(loop, self.config.runtime.pollIntervalMs, poll)
        if ok then
            self.loop_handle = handle
        else
            self:unregister()
            return false, "periodic scheduler failed: " .. tostring(handle)
        end
    else
        local legacy_loop = global("LoopAsync")
        local execute_game_thread = global("ExecuteInGameThread")
        if type(legacy_loop) == "function" and type(execute_game_thread) == "function" then
            legacy_loop(self.config.runtime.pollIntervalMs, function()
                execute_game_thread(poll)
                return false
            end)
        else
            self:unregister()
            return false, "no supported periodic game-thread scheduler"
        end
    end
    self.registered = true
    return true
end

function Bridge:unregister()
    local unregister = global("UnregisterHook")
    if type(unregister) == "function" then
        for _, registration in pairs(self.hook_ids) do
            pcall(unregister, registration.path, registration.pre, registration.post)
        end
    end
    self.hook_ids = {}
    local cancel = global("CancelDelayedAction")
    if self.loop_handle and type(cancel) == "function" then
        pcall(cancel, self.loop_handle)
    end
    self.loop_handle = nil
    self.registered = false
end

function Bridge:active_invasion_count()
    local count = 0
    for _, incident in ipairs(self:_find_all("PalInvaderIncidentBase")) do
        if valid(incident) then
            local ok, executing = call(incident, "IsExecuting")
            if not ok or executing then
                count = count + 1
            end
        end
    end
    return count
end

function Bridge:preflight_start()
    if self.config.mode ~= "laboratory" then
        return false, "alpha invasion mutation is laboratory-only"
    end
    local version = require("ped.version")
    if self.config.compatibility.requiredAdapter ~= version.adapter then
        return false, "configured adapter identity does not match this runtime"
    end
    local observed_build_id = os.getenv("PAL_EVENT_DIRECTOR_SERVER_BUILD_ID")
    local build_allowed = false
    for _, candidate in ipairs(self.config.compatibility.allowedServerBuildIds) do
        if candidate == observed_build_id then build_allowed = true; break end
    end
    if not build_allowed then
        return false, "PAL_EVENT_DIRECTOR_SERVER_BUILD_ID is absent or not allowlisted"
    end
    local runtime = global("UE4SS")
    if runtime and type(runtime.GetVersion) == "function" and #self.config.compatibility.allowedUe4ssVersions > 0 then
        local ok, major, minor, patch = pcall(runtime.GetVersion, runtime)
        local current = ok and string.format("%d.%d.%d", major, minor, patch) or "unknown"
        local allowed = false
        for _, candidate in ipairs(self.config.compatibility.allowedUe4ssVersions) do
            if candidate == current then allowed = true; break end
        end
        if not allowed then
            return false, "UE4SS version is not allowlisted: " .. current
        end
    end
    local manager = self:_find_first("PalInvaderManager")
    if not valid(manager) then
        return false, "PalInvaderManager instance is unavailable"
    end
    if self:active_invasion_count() > 0 then
        return false, "a native invasion/visitor incident is already active; one incident per base is assumed and this alpha uses a global mutex"
    end
    local function_object = self:_static_find("/Script/Pal.PalInvaderManager:StartInvaderMarchAll")
    if not valid(function_object) then
        return false, "StartInvaderMarchAll is unavailable for this revision"
    end
    return true
end

function Bridge:start_all_invasions()
    local manager = self:_find_first("PalInvaderManager")
    local ok, result = call(manager, "StartInvaderMarchAll")
    if not ok then
        return false, tostring(result)
    end
    return true
end

function Bridge:announce(message)
    local game_state = self:_find_first("PalGameStateInGame")
    if not valid(game_state) then
        self.logger:warn("Announcement skipped; PalGameStateInGame unavailable", { message = message })
        return false
    end
    local string_constructor = global("FString")
    local payload = message
    if type(string_constructor) == "function" then
        local ok, converted = pcall(string_constructor, message)
        if ok then payload = converted end
    end
    local ok, announce_error = call(game_state, "BroadcastServerNotice", payload)
    if not ok then
        self.logger:warn("Announcement failed", { error = announce_error })
    end
    return ok
end

function Bridge:_online_player_guid(uid)
    for _, controller in ipairs(self:_find_all("PalPlayerController")) do
        if valid(controller) then
            local ok, guid = call(controller, "GetPlayerUId")
            if ok and guid_string(guid) == uid then
                return controller, guid
            end
        end
    end
    return nil
end

function Bridge:grant_item(obligation)
    if not self.config.capabilities.grantItems then
        return { status = "pending", reason = "item grants disabled" }
    end
    local item_allowed = false
    for _, item_id in ipairs(self.config.rewards.allowedItemIds or {}) do
        if item_id == obligation.itemId then item_allowed = true; break end
    end
    if not item_allowed then
        return { status = "operator_review", reason = "item ID is not allowlisted" }
    end
    local controller, guid = self:_online_player_guid(obligation.playerUid)
    if not controller then
        return { status = "pending", reason = "player offline" }
    end
    local utility = self:_utility()
    local world_ok, world = call(controller, "GetWorld")
    if not valid(utility) or not world_ok or not valid(world) then
        return { status = "pending", reason = "player world unavailable" }
    end
    local inventory_ok, inventory = call(utility, "GetInventoryDataByPlayerUID", world, guid)
    if not inventory_ok or not valid(inventory) then
        return { status = "pending", reason = "inventory unavailable" }
    end
    local name_constructor = global("FName")
    if type(name_constructor) ~= "function" then
        return { status = "operator_review", reason = "FName constructor unavailable" }
    end
    local name_ok, item_name = pcall(name_constructor, obligation.itemId, 1)
    if not name_ok then
        return { status = "operator_review", reason = "invalid item FName" }
    end
    local before_ok, before_count = call(inventory, "CountItemNum", item_name)
    before_count = before_ok and as_integer(before_count) or nil
    if before_count == nil then
        return { status = "operator_review", reason = "unable to establish pre-grant item count" }
    end
    local grant_ok, operation = call(inventory, "AddItem_ServerInternal", item_name, obligation.count, false, 0.0, true)
    if not grant_ok then
        return { status = "operator_review", reason = tostring(operation) }
    end
    local after_ok, after_count = call(inventory, "CountItemNum", item_name)
    after_count = after_ok and as_integer(after_count) or nil
    if after_count and after_count >= before_count + obligation.count then
        return { status = "delivered", before_count = before_count, after_count = after_count }
    end
    return { status = "operator_review", reason = "grant result could not be verified", before_count = before_count, after_count = after_count }
end

return Bridge

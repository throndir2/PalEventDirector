local util = require("ped.util")
local bounties = require("ped.bounties")
local PreflightDiagnostic = require("ped.preflight_diagnostic")
local DiagnosticIngress = require("ped.diagnostic_ingress")
local NativeExperiments = require("ped.native_experiments")
local NativeObserver = require("ped.native_observer")

local Bridge = {}
Bridge.__index = Bridge
local NATIVE_PROBE_GROUP = NativeExperiments.default_group
local PROBE_LIMITS = { rows = 512, points = 256, navigation = 32, functions = 128, classes = 8, incidents = 16 }

local HOOKS = {
    damage = "/Script/Pal.PalEventNotify_Character:OnCharacterDamaged_ServerInternal",
    death = "/Script/Pal.PalEventNotify_Character:OnCharacterDead_ServerInternal",
    invasion_start = "/Script/Pal.PalInvaderManager:BroadcastInvaderStart",
    invasion_declaration = "/Script/Pal.PalInvaderManager:BroadcastInvaderDeclaration",
    invasion_arrived = "/Script/Pal.PalInvaderManager:BroadcastInvaderArrived",
    invasion_end = "/Script/Pal.PalInvaderManager:BroadcastInvaderEnd",
    invasion_timeout = "/Script/Pal.PalInvaderManager:BroadcastInvaderWaveTimeup",
    invasion_cancel = "/Script/Pal.PalInvaderManager:BroadcastInvaderCancel",
    select_invaders = "/Script/Pal.PalInvaderIncidentBase:SelectInvaders",
    chat = "/Script/Pal.PalPlayerController:EnterChat_Receive",
}

local function global(name)
    return rawget(_G, name)
end

local function fname_constructor()
    local constructor = global("FName")
    -- Pinned UE4SS exposes a callable FName userdata, not a Lua function.
    if type(constructor) == "userdata" or type(constructor) == "function" then return constructor end
    return nil
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
    if not ok then
        return nil
    end
    return unwrap(value)
end

local function probe_field(object, name, kind)
    object = unwrap(object)
    if type(object) ~= "userdata" and type(object) ~= "table" then
        error("Native probe data has an unexpected type", 0)
    end
    local value = unwrap(object[name])
    if type(value) ~= kind or (kind == "number" and (value ~= value or math.abs(value) == math.huge)) then
        error("Native probe data has an unexpected type", 0)
    end
    return value
end

local function probe_vector(value)
    return { probe_field(value, "X", "number"), probe_field(value, "Y", "number"), probe_field(value, "Z", "number") }
end

local function call(object, method_name, ...)
    if method_name == "GetOptionWorldSettings" then
        return false, "By-value world-settings getter is blocked by the pinned UE4SS call-buffer limit"
    end
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

local function scalar(value)
    value = unwrap(value)
    if type(value) == "boolean" or type(value) == "number" or type(value) == "string" then
        return value
    end
    if value == nil then return nil end
    local text = to_string(value)
    return text ~= "" and text or nil
end

local function container_count(value)
    value = unwrap(value)
    if value == nil then return nil end
    local ok, count = pcall(function()
        if type(value.GetArrayNum) == "function" then return value:GetArrayNum() end
        return #value
    end)
    return ok and tonumber(count) or nil
end

local function or_unavailable(value)
    if value == nil then return "unavailable" end
    return value
end

local function is_enemy_invader_type(value)
    local numeric = as_integer(value)
    if numeric ~= nil then
        return numeric == 1
    end
    return to_string(value):match("InvaderEnemy$") ~= nil
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
    local compact = result:gsub("%-", "")
    if compact:match("^[0-9a-f]+$") and #compact == 32 then
        result = table.concat({
            compact:sub(1, 8),
            compact:sub(9, 12),
            compact:sub(13, 16),
            compact:sub(17, 20),
            compact:sub(21, 32),
        }, "-")
    end
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

local function object_address(object)
    object = unwrap(object)
    if not valid(object) then return nil end
    local ok, address = pcall(function() return object:GetAddress() end)
    if not ok or address == nil then return nil end
    return tostring(address)
end

local function same_object(left, right)
    left = unwrap(left)
    right = unwrap(right)
    if not valid(left) or not valid(right) then return false end
    local left_address = object_address(left)
    local right_address = object_address(right)
    return left_address ~= nil and right_address ~= nil and left_address == right_address
end

function Bridge.new(options)
    local self = setmetatable({
        config = assert(options.config),
        logger = assert(options.logger),
        clock = options.clock or util.now_seconds,
        director = nil,
        hook_ids = {},
        damage_sequence = 0,
        timed_out_bases = {},
        event_open = false,
        discovery_open = false,
        selection_open = false,
        owned_groups = {},
        selected_groups = {},
        expected_bases = {},
        pending_expected_bases = {},
        pending_native_base_ids = {},
        native_base_ids = {},
        pending_base_guilds = {},
        base_guilds = {},
        pending_roster = {},
        event_roster = {},
        pending_manager = nil,
        event_manager = nil,
        pending_world = nil,
        pending_admin_override = false,
        event_admin_override = false,
        pending_nearest_test = nil,
        event_nearest_test = nil,
        pending_native_control = nil,
        event_native_control = nil,
        event_world = nil,
        event_manager_address = nil,
        event_world_address = nil,
        request_windows = {},
        dispatch_order = {},
        probe_base_id = nil,
        probe_confirmed = false,
        fanout_dispatched = false,
        native_all_diagnostic_until = 0,
        native_all_diagnostic_manager = nil,
        native_all_diagnostic_world = nil,
        dispatching_base_id = nil,
        member_context = {},
        profile_id = "native",
        bounty_selector = nil,
        substitution_count = 0,
        player_names = {},
        utility = nil,
        loop_handle = nil,
        registered = false,
        hook_observed = {},
        periodic_active = false,
        native_fault = nil,
        native_trace_ordinal = 0,
        native_trace_run = os.time(),
        diagnostic_command_directory = options.diagnostic_command_directory,
        delivery_profile = options.delivery_profile or require("ped.version").delivery_profile,
    }, Bridge)
    if options.observe_native_experiments then
        if type(self.logger.native_experiment) ~= "function" then error("Native experiment recorder is unavailable") end
        self.experiments = NativeExperiments.new({
            clock = self.clock, run = self.native_trace_run,
            emit = function(record) return self.logger:native_experiment(record) end,
        })
        self.native_observer = NativeObserver.new(self, {
            unwrap = unwrap, valid = valid, property = property, same = same_object, guid = guid_string,
            count = container_count, address = object_address,
        })
    end
    return self
end

function Bridge:_experiment_detail(kind, fields, scope)
    scope = scope or self.experiment_current
    if not self.experiments or not scope then return end
    local recorded = self.experiments:record(scope, kind, fields)
    if not recorded then error("Native experiment logging failed", 0) end
end

function Bridge:_open_native_observation(manager, world, base, base_id, route, group, request, recipient)
    return self:_native_step("experiment-open", function()
        local scope = self.native_observer:open({ manager = manager, world = world, base = base, base_id = base_id,
            route = route, group = group, request = request, recipient = recipient,
            deadline = route ~= "inspect" and self.clock() + self.config.siegeLeague.startDiscoverySeconds or nil })
        self.native_observer:prepare(scope)
        return scope
    end)
end

function Bridge:poll_native_observations()
    if not self.experiments then return end
    if self.native_fault then self.experiments:clear(); return end
    local scope, due, skipped = self.experiments:next_sample()
    if not scope then return end
    self:_native_step("experiment-passive-sample", function()
        self:_experiment_detail("scope", { phase = "sample", sampleDue = due, skippedSamples = skipped,
            late = scope.deadline ~= nil and self.clock() > scope.deadline }, scope)
        local sampled, reason = self.native_observer:sample(scope)
        if not sampled or due == 600 then
            local closed = self.experiments:close(scope, sampled and "complete" or reason)
            if not closed then error("Native experiment logging failed", 0) end
        end
    end)
end

function Bridge:inspect_native_control(principal, paths)
    local allowed, reason = self:native_start_guard()
    if not allowed then return false, reason end
    if not self.experiments then return false, "comprehensive native observation is not enabled" end
    local environment_ok, environment_error = self:preflight_environment()
    if not environment_ok then return false, environment_error end
    local ok, result, inspection_error = self:_native_step("native-inspection", function()
        local roster = self:list_online_players()
        local manager, world, manager_error = self:_resolve_world_manager(roster)
        if not manager then return nil, manager_error end
        local requester
        for _, player in ipairs(roster) do if player.uid == principal.uid then requester = player; break end end
        if not requester or not valid(requester.controller) then return nil, "requesting controller is no longer online" end
        local id, base_error = self:_nearest_test_base(requester.controller, world)
        if not id then return nil, base_error end
        local target, target_error = self:_resolve_dispatch_target(manager, id)
        if not target then return nil, target_error end
        local opened, scope = self:_open_native_observation(manager, world, target.base, id, "inspect", nil, nil, principal.uid)
        if not opened then return end
        local previous = self.experiment_current
        self.experiment_current = scope
        local collected, details, detail_error = self:_native_step("experiment-inspection-details", function()
            local groups_ok, inventory, biomes = self:_probe_group_inventory(manager)
            if not groups_ok then return end
            local geometry_ok, geometry = self:_probe_spawn_inventory(manager, target.base, biomes, world)
            if not geometry_ok then return end
            local workers = self.native_observer:workers(scope)
            local sampled, state = self.native_observer:sample(scope)
            if not sampled then return nil, "native observation scope became unavailable" end
            local response = { observation = scope.id, slots = state.slots, occupied = state.occupied }
            for key, value in pairs(geometry) do response[key] = value end
            for key, value in pairs(workers) do response[key] = value end
            if paths then
                local queried, query_result = self.native_observer:path_queries(scope, requester.controller)
                if not queried then return nil, query_result end
                response.pathQueries, response.completePaths = query_result.queries, query_result.complete
            end
            return response
        end)
        self.experiment_current = previous
        if not collected then return end
        return details, detail_error
    end)
    if not ok then return false, result end
    if not result then return false, inspection_error or "native inspection could not establish a current base and world" end
    return true, result
end

function Bridge:attach_director(director)
    self.director = director
end

function Bridge:native_start_guard()
    if self.delivery_profile ~= "laboratory-native-test" or self.config.mode ~= "laboratory" then
        return false, "Native starts are quarantined outside the guarded laboratory test profile."
    end
    if not self.config.capabilities.startAllInvasions then return false, "capabilities.startAllInvasions is disabled." end
    if not self.registered or not self.periodic_active then return false, "Laboratory hooks and polling are not ready." end
    if self.native_fault then return false, self.native_fault end
    return true
end

function Bridge:_native_step(label, operation)
    if self.native_fault then return false, self.native_fault end
    self.native_trace_ordinal = self.native_trace_ordinal + 1
    local step = string.format("%d-%04d-start-%s", self.native_trace_run, self.native_trace_ordinal, label)
    local function fail(code)
        self.native_fault = "Native operation stopped at " .. label .. " [" .. code .. "]; preserve server logs and restart after investigation. Do not retry."
        if self.logger and type(self.logger.error) == "function" then self.logger:error(self.native_fault, { step = step }) end
        return false, self.native_fault
    end
    local function record(phase)
        if not self.logger or type(self.logger.preflight_breadcrumb) ~= "function" then return false end
        -- False means this boundary does not make a separate object-validity claim.
        local ok, saved = pcall(self.logger.preflight_breadcrumb, self.logger, step .. "." .. phase,
            require("ped.version").tested_server_build_id, false)
        return ok and saved == true
    end
    if not record("before") then return fail("breadcrumb-before") end
    local result = table.pack(pcall(operation))
    if self.native_fault then return false, self.native_fault end
    if not result[1] then return fail(PreflightDiagnostic.classify_error(result[2])) end
    if not record("after") then return fail("breadcrumb-after") end
    return true, table.unpack(result, 2, result.n)
end

function Bridge:_native_call(label, object, method, ...)
    local arguments = table.pack(...)
    return self:_native_step(label, function()
        local ok, result = call(object, method, table.unpack(arguments, 1, arguments.n))
        if not ok then error(result, 0) end
        return result
    end)
end

function Bridge:diagnose_preflight(confirmation, expected_step)
    if not self.registered or (self.diagnostic_ingress and (self.diagnostic_ingress.blocked or not self.diagnostic_ingress.active)) then
        return false, "Diagnostic startup is blocked or incomplete; preserve evidence before a new session."
    end
    if not self.preflight_diagnostic then
        self.preflight_diagnostic = PreflightDiagnostic.new({
            config = self.config,
            native_readiness = self.delivery_profile == "laboratory-native-test",
            record = function(step, build_id, object_valid)
                return self.logger:preflight_breadcrumb(step, build_id, object_valid)
            end,
        })
    end
    return self.preflight_diagnostic:run(confirmation, expected_step)
end

function Bridge:begin_event_discovery(profile_id, occurrence_id)
    local allowed, reason = self:native_start_guard()
    if not allowed then return nil, nil, reason end
    self.event_open = true
    self.discovery_open = true
    self.selection_open = false
    self.owned_groups = {}
    self.selected_groups = {}
    self.expected_bases = self.pending_expected_bases
    self.pending_expected_bases = {}
    self.native_base_ids = self.pending_native_base_ids
    self.pending_native_base_ids = {}
    self.base_guilds = self.pending_base_guilds
    self.pending_base_guilds = {}
    self.event_roster = self.pending_roster
    self.pending_roster = {}
    self.event_manager = self.pending_manager
    self.pending_manager = nil
    self.event_world = self.pending_world
    self.pending_world = nil
    self.event_admin_override = self.pending_admin_override == true
    self.pending_admin_override = false
    self.event_nearest_test = self.pending_nearest_test
    self.pending_nearest_test = nil
    self.event_native_control = self.pending_native_control
    self.pending_native_control = nil
    self.event_manager_address = object_address(self.event_manager)
    self.event_world_address = object_address(self.event_world)
    if not self.event_manager_address or not self.event_world_address then
        self:end_event_tracking()
        return nil, nil, "pinned event manager or world address is unavailable"
    end
    self.request_windows = {}
    self.dispatch_order = {}
    self.probe_base_id = nil
    self.probe_confirmed = false
    self.fanout_dispatched = false
    self.dispatching_base_id = nil
    self.member_context = {}
    self.profile_id = profile_id or "native"
    self.bounty_selector = bounties.new_selector(self.profile_id, occurrence_id)
    self.substitution_count = 0
    self.timed_out_bases = {}
    self.probe_handoff_metadata, self.probe_handoff_counts = nil, nil
    local targets = {}
    for base_id in pairs(self.expected_bases) do
        targets[#targets + 1] = { id = base_id, guildId = self.base_guilds[base_id] }
    end
    table.sort(targets, function(left, right) return left.id < right.id end)
    return targets, util.deep_copy(self.event_roster)
end

function Bridge:close_event_discovery()
    self.discovery_open = false
    self.selection_open = false
end

function Bridge:_request_window_open(base_id)
    local request = self.request_windows[base_id]
    if not request or request.status == "dispatch_call_failed" then
        return false
    end
    return self.clock() <= request.expiresAt
end

function Bridge:_request_identity_is_new(base_id, group_id, incident)
    local request = self.request_windows[base_id]
    if not request then return false end
    local baseline = request.baseline
    if not baseline then return true end
    if not baseline.complete or baseline.groups[group_id] then return false end
    local address = incident and object_address(incident)
    return not address or not baseline.incidents[address]
end

function Bridge:end_event_tracking(preserve_pending)
    local pending_fields = { "pending_admin_override", "pending_nearest_test", "pending_native_control",
        "pending_expected_bases", "pending_native_base_ids", "pending_base_guilds", "pending_roster", "pending_manager", "pending_world" }
    local pending = {}
    if preserve_pending == true then
        for _, key in ipairs(pending_fields) do pending[key] = self[key] end
    end
    self.pending_admin_override, self.event_admin_override = false, false
    self.pending_nearest_test, self.event_nearest_test = nil, nil
    self.pending_native_control, self.event_native_control = nil, nil
    self.event_open = false
    self.discovery_open = false
    self.selection_open = false
    self.owned_groups = {}
    self.selected_groups = {}
    self.expected_bases = {}
    self.pending_expected_bases = {}
    self.native_base_ids = {}
    self.pending_native_base_ids = {}
    self.base_guilds = {}
    self.pending_base_guilds = {}
    self.event_roster = {}
    self.pending_roster = {}
    self.pending_manager = nil
    self.event_manager = nil
    self.pending_world = nil
    self.event_world = nil
    self.event_manager_address = nil
    self.event_world_address = nil
    self.request_windows = {}
    self.dispatch_order = {}
    self.probe_base_id = nil
    self.probe_confirmed = false
    self.fanout_dispatched = false
    self.dispatching_base_id = nil
    self.member_context = {}
    self.profile_id = "native"
    self.bounty_selector = nil
    self.probe_handoff_metadata, self.probe_handoff_counts = nil, nil
    if preserve_pending == true then
        for _, key in ipairs(pending_fields) do self[key] = pending[key] end
    end
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

function Bridge:_resolve_world_manager(roster)
    local utility = self:_utility()
    if not valid(utility) then return nil, nil, "PalUtility unavailable" end
    if type(roster) ~= "table" or #roster < 1 then return nil, nil, "no online player world is available" end
    local manager
    local world
    for _, player in ipairs(roster) do
        if not valid(player.world) then
            return nil, nil, "online player world is invalid for " .. util.mask_uid(player.uid)
        end
        local manager_ok, candidate = self:_native_call("get-invader-manager", utility, "GetInvaderManager", player.world)
        if not manager_ok or not valid(candidate) then
            return nil, nil, "world-scoped PalInvaderManager lookup failed for " .. util.mask_uid(player.uid)
        end
        local candidate_world_ok, candidate_world = self:_native_call("manager-world", candidate, "GetWorld")
        if not candidate_world_ok or not same_object(candidate_world, player.world) then
            return nil, nil, "world-scoped PalInvaderManager returned a different world for " .. util.mask_uid(player.uid)
        end
        if manager and not same_object(manager, candidate) then
            return nil, nil, "online players resolved to different invasion managers"
        end
        manager = candidate
        if world and not same_object(world, player.world) then
            return nil, nil, "online players belong to different worlds"
        end
        world = player.world
    end
    if not object_address(manager) or not object_address(world) then
        return nil, nil, "world or PalInvaderManager address is unavailable"
    end
    return manager, world
end

function Bridge:_world_invaders_enabled(world)
    if not valid(world) then return false, "world is invalid for invasion settings" end
    local ok, options = self:_native_call("get-option-subsystem", self:_utility(), "GetOptionSubsystem", world)
    if not ok or not valid(options) then return false, "world-scoped option subsystem is unavailable" end
    local world_ok, options_world = self:_native_call("option-world", options, "GetWorld")
    if not world_ok or not same_object(options_world, world) then
        return false, "option subsystem belongs to a different world"
    end
    -- This is a reflected property view, not the oversized by-value UFunction.
    local read_ok, enabled = self:_native_step("invasion-enable-flag", function()
        local settings = property(options, "OptionWorldSettings")
        return property(settings, "bEnableInvaderEnemy")
    end)
    if not read_ok then return false, enabled end
    if type(enabled) ~= "boolean" then return false, "native invasion setting is unreadable" end
    if not enabled then return false, "native enemy invasions are disabled in world settings" end
    return true
end

function Bridge:_manager_hook_scope(context)
    local manager = unwrap(context)
    if not valid(manager) then return nil end
    local manager_world_ok, manager_world = call(manager, "GetWorld")
    if not manager_world_ok then return nil end
    if self.event_open then
        local manager_address = object_address(manager)
        local world_address = object_address(manager_world)
        if self.event_manager_address and self.event_world_address and manager_address and world_address
            and manager_address == self.event_manager_address and world_address == self.event_world_address then
            return "event"
        end
        return nil
    end
    if self.clock() <= self.native_all_diagnostic_until
        and same_object(manager, self.native_all_diagnostic_manager)
        and same_object(manager_world, self.native_all_diagnostic_world) then
        return "native-all-diagnostic"
    end
    return nil
end

function Bridge:_selection_hook_scope(context)
    local incident = unwrap(context)
    if not valid(incident) then return nil end
    local world_ok, world = call(incident, "GetWorld")
    if not world_ok then return nil end
    local world_address = object_address(world)
    if self.event_open and self.event_world_address and world_address
        and world_address == self.event_world_address then return "event" end
    if not self.event_open and self.clock() <= self.native_all_diagnostic_until
        and same_object(world, self.native_all_diagnostic_world) then
        return "native-all-diagnostic"
    end
    return nil
end

function Bridge:_register_hook(name, path, callback, mode)
    local register = global("RegisterHook")
    if type(register) ~= "function" then
        return false, "RegisterHook is unavailable"
    end
    local function observed(...)
        self.hook_observed[name] = (self.hook_observed[name] or 0) + 1
        callback(...)
    end
    local ok, pre_id, post_id
    if mode == "script" then
        ok, pre_id, post_id = pcall(register, path, observed)
    else
        ok, pre_id, post_id = pcall(register, path, function() end, observed)
    end
    if not ok then
        return false, tostring(pre_id)
    end
    self.hook_ids[name] = { path = path, pre = pre_id, post = post_id }
    if mode == "script" and (not util.is_integer(pre_id) or pre_id < 0 or pre_id ~= post_id) then
        return false, "Script hook registration identifiers are invalid"
    end
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
    return self:_base_id_from_parameter(parameter), guid_string(property(parameter, "GroupGuid")), property(parameter, "InvaderType")
end

function Bridge:_occupied_incident_details(incidents, total)
    return self:_native_step("occupied-incident-state", function()
        local recent = self.director and self.director.state and self.director.state.event
        local summary = { occupiedSlots = total, inspectedSlots = 0, invalidSlots = 0, enemySlots = 0, visitorSlots = 0,
            unknownTypeSlots = 0, initializedSlots = 0, executingSlots = 0, completedSlots = 0, canceledSlots = 0,
            matchingRecentEventSlots = 0, recentEventRequest = recent and recent.requestNumber or 0,
            handoffHookRegistered = self.hook_ids.probe_handoff ~= nil,
            processHandoffCalls = self.hook_observed.probe_handoff or 0,
            processDeclarationCalls = self.hook_observed.invasion_declaration or 0,
            processSelectionCalls = self.hook_observed.select_invaders or 0,
            processStartCalls = self.hook_observed.invasion_start or 0 }
        local entries = {}
        incidents:ForEach(function(key, value)
            local id = guid_string(key)
            entries[#entries + 1] = { incident = unwrap(value),
                recent = id ~= nil and recent ~= nil and recent.bases ~= nil and recent.bases[id] ~= nil }
            if #entries >= PROBE_LIMITS.incidents then return true end
            return nil
        end)
        for _, entry in ipairs(entries) do
            summary.inspectedSlots = summary.inspectedSlots + 1
            if entry.recent then summary.matchingRecentEventSlots = summary.matchingRecentEventSlots + 1 end
            if not valid(entry.incident) then
                summary.invalidSlots = summary.invalidSlots + 1
            else
                local kind = probe_field(entry.incident, "InvaderType", "number")
                if kind == 1 then summary.enemySlots = summary.enemySlots + 1
                elseif kind == 2 then summary.visitorSlots = summary.visitorSlots + 1
                else summary.unknownTypeSlots = summary.unknownTypeSlots + 1 end
                for _, check in ipairs({
                    { "occupied-initialized", "IsInitialized", "initializedSlots" },
                    { "occupied-executing", "IsExecuting", "executingSlots" },
                    { "occupied-completed", "IsCompleted", "completedSlots" },
                    { "occupied-canceled", "IsCanceled", "canceledSlots" },
                }) do
                    local ok, result = self:_native_call(check[1], entry.incident, check[2])
                    if not ok then return end
                    if type(result) ~= "boolean" then error("Native probe data has an unexpected type", 0) end
                    if result then summary[check[3]] = summary[check[3]] + 1 end
                end
            end
        end
        summary.incidentScanComplete = summary.inspectedSlots == total
        return summary
    end)
end

function Bridge:_registered_base_ids(manager)
    local observers = property(manager, "Observers")
    if not observers then
        return nil, "PalInvaderManager.Observers is unavailable"
    end
    local ids = {}
    local id_set = {}
    local ok, iteration_error = pcall(function()
        observers:ForEach(function(key)
            local id = guid_string(key)
            if id and not id_set[id] then
                id_set[id] = true
                ids[#ids + 1] = id
            end
        end)
    end)
    if not ok then
        return nil, "unable to enumerate registered invasion observers: " .. tostring(iteration_error)
    end
    table.sort(ids)
    local incidents = property(manager, "Incidents")
    if not incidents then
        return nil, "PalInvaderManager.Incidents is unavailable"
    end
    local incident_count = 0
    local counted, count_error = pcall(function()
        incidents:ForEach(function() incident_count = incident_count + 1 end)
    end)
    if not counted then
        return nil, "unable to inspect existing invasion incidents: " .. tostring(count_error)
    end
    if incident_count > 0 then
        local inspected, details = self:_occupied_incident_details(incidents, incident_count)
        if not inspected then return nil, details end
        self.logger:info("Native incident slots block a new start", details)
        return nil, string.format(
            "one or more native invasion/visitor incidents already occupy base slots (total=%d, enemy=%d, visitor=%d, executing=%d, completed=%d, canceled=%d, matching latest event=%d, scan=%s). No new native start ran.",
            details.occupiedSlots, details.enemySlots, details.visitorSlots, details.executingSlots, details.completedSlots,
            details.canceledSlots, details.matchingRecentEventSlots, details.incidentScanComplete and "complete" or "partial")
    end
    return ids, id_set
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

function Bridge:command_principal(controller)
    controller = unwrap(controller)
    if not valid(controller) then
        return nil, "server player controller is invalid"
    end
    local uid_ok, uid_value = call(controller, "GetPlayerUId")
    local uid = uid_ok and guid_string(uid_value) or nil
    if not uid then
        return nil, "stable player UID is unavailable"
    end
    local admin_ok, admin_value = pcall(function()
        return unwrap(controller.bAdmin)
    end)
    if not admin_ok then
        return {
            transport = "chat",
            uid = uid,
            palworldAdmin = nil,
            palworldAdminReadable = false,
            palworldAdminError = "APalPlayerController.bAdmin access failed",
        }
    end
    if type(admin_value) ~= "boolean" then
        return {
            transport = "chat",
            uid = uid,
            palworldAdmin = nil,
            palworldAdminReadable = false,
            palworldAdminError = "APalPlayerController.bAdmin is unavailable or ambiguous",
        }
    end
    return {
        transport = "chat",
        uid = uid,
        palworldAdmin = admin_value,
        palworldAdminReadable = true,
    }
end

function Bridge:list_online_players()
    local players = {}
    local seen = {}
    for _, controller in ipairs(self:_find_all("PalPlayerController")) do
        if valid(controller) then
            local world_ok, world = call(controller, "GetWorld")
            local uid_ok, uid_value = call(controller, "GetPlayerUId")
            local uid = uid_ok and guid_string(uid_value) or nil
            if world_ok and valid(world) and uid and not seen[uid] then
                seen[uid] = true
                local name = self:_player_display_name(uid)
                players[#players + 1] = { uid = uid, name = name, controller = controller, guid = uid_value, world = world }
            end
        end
    end
    table.sort(players, function(left, right) return left.uid < right.uid end)
    return players
end

function Bridge:_eligible_online_guild_bases(manager, roster, admin_override, selected_base_id)
    local utility = self:_utility()
    if not valid(utility) then
        return nil, nil, nil, nil, "PalUtility unavailable"
    end
    local expected = {}
    local native_ids = {}
    local base_guilds = {}
    local online_guilds = {}
    roster = roster or self:list_online_players()
    local resolved_roster = {}
    if #roster < 1 then
        return {}, {}, {}, {}, nil
    end
    for _, player in ipairs(roster) do
        local guild_ok, guild = call(utility, "GetGuildByPlayerUId", player.world, player.guid)
        if not guild_ok or not valid(guild) then
            return nil, nil, nil, nil, "guild lookup failed for online player " .. util.mask_uid(player.uid)
        end
        local guild_ok_id, guild_id_value = call(guild, "GetId")
        local guild_id = guild_ok_id and guid_string(guild_id_value) or nil
        if not guild_id then
            return nil, nil, nil, nil, "guild identity failed for online player " .. util.mask_uid(player.uid)
        end
        online_guilds[guild_id] = true
        resolved_roster[#resolved_roster + 1] = { uid = player.uid, name = player.name, guildId = guild_id }
    end

    local observers = property(manager, "Observers")
    if not observers then return nil, nil, nil, nil, "PalInvaderManager.Observers is unavailable" end
    local observer_error
    local ok, iteration_error = pcall(function()
        observers:ForEach(function(key, value)
            local key_id = guid_string(key)
            if selected_base_id and key_id ~= selected_base_id then return nil end
            local observer = unwrap(value)
            local base = property(observer, "TargetBaseCamp")
            if valid(base) then
                local id_ok, id_value = call(base, "GetId")
                local group_ok, group_value = call(base, "GetGroupIdBelongTo")
                local observer_id = guid_string(property(observer, "TargetBaseCampID"))
                local base_id = id_ok and guid_string(id_value) or nil
                local group_id = group_ok and guid_string(group_value) or nil
                if base_id and group_id and online_guilds[group_id] then
                    if not key_id or not observer_id or key_id ~= base_id or observer_id ~= base_id then
                        observer_error = "eligible base GUID sources disagree: " .. util.mask_uid(base_id)
                        return true
                    end
                    if admin_override == true then
                        expected[base_id] = true
                        native_ids[base_id] = id_value
                        base_guilds[base_id] = group_id
                        return nil
                    end
                    local available_ok, available = call(base, "IsAvailable")
                    local invading = property(observer, "bIsInvading")
                    local path_searching = property(observer, "bIsInvaderPathSearching")
                    local cooling_down = property(observer, "bIsCoolTime")
                    local ignore_invader = property(base, "bIgnoreInvader")
                    if type(invading) ~= "boolean" or type(path_searching) ~= "boolean"
                        or type(cooling_down) ~= "boolean" or type(ignore_invader) ~= "boolean" then
                        observer_error = "observer state is unavailable for eligible base " .. util.mask_uid(base_id)
                        return true
                    elseif invading or path_searching then
                        observer_error = "eligible base is already invading or path-searching: " .. util.mask_uid(base_id)
                        return true
                    elseif cooling_down and admin_override ~= true then
                        observer_error = "eligible base is in native invasion cooldown: " .. util.mask_uid(base_id)
                        return true
                    elseif ignore_invader then
                        observer_error = "eligible base ignores native invasions: " .. util.mask_uid(base_id)
                        return true
                    elseif available_ok and available then
                        expected[base_id] = true
                        native_ids[base_id] = key
                        base_guilds[base_id] = group_id
                    end
                end
            end
        end)
    end)
    if not ok then return nil, nil, nil, nil, "unable to enumerate eligible guild bases: " .. tostring(iteration_error) end
    if observer_error then return nil, nil, nil, nil, observer_error end
    return expected, native_ids, base_guilds, resolved_roster, nil
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
    local group_id
    for _, incident in ipairs(self:_find_all("PalInvaderIncidentBase")) do
        if valid(incident) then
            local member_ok, is_member = call(incident, "IsGroupCharacter", handle)
            if member_ok and is_member == true then
                local camp_ok, camp = call(incident, "GetTargetCampModel")
                if camp_ok and valid(camp) then
                    local id_ok, id = call(camp, "GetId")
                    if id_ok then
                        base_id = guid_string(id)
                        local internal_group_id = guid_string(property(incident, "GroupGuid"))
                        local broadcast_group_id = guid_string(property(incident, "BroadcastGroupGuid"))
                        local event_base = self.director and self.director.state and self.director.state.event
                            and self.director.state.event.bases[base_id] or nil
                        local accepted_group = event_base and event_base.groupId or nil
                        if accepted_group and (accepted_group == internal_group_id or accepted_group == broadcast_group_id)
                            and self.owned_groups[accepted_group] == base_id then
                            group_id = accepted_group
                            break
                        end
                        base_id = nil
                        group_id = nil
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
        group_id = group_id,
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
    local accepted = self.director:on_damage(target)
    if not accepted then
        return
    end
    self.director:on_death({
        target_id = target.target_id,
        base_id = target.base_id,
        group_id = target.group_id,
        source_kind = source.source_kind,
        player_uid = source.player_uid,
        reason = "defeated",
        dead_type = dead_type,
    })
end

function Bridge:_selection_base_id(incident)
    incident = unwrap(incident)
    local camp_ok, camp = call(incident, "GetTargetCampModel")
    if not camp_ok or not valid(camp) then
        return nil
    end
    local id_ok, id = call(camp, "GetId")
    return id_ok and guid_string(id) or nil
end

function Bridge:_on_select_invaders(context, out_members)
    local observed_base_id = self:_selection_base_id(context)
    if self.event_open or self.clock() <= self.native_all_diagnostic_until then
        self.logger:info("Native SelectInvaders observed", { base = util.mask_uid(observed_base_id), eventOpen = self.event_open })
    end
    if not self.event_open or self.profile_id == "native" or not self.bounty_selector then
        return
    end
    if not is_enemy_invader_type(property(unwrap(context), "InvaderType")) then
        return
    end
    local base_id = observed_base_id
    if not base_id or not self.expected_bases[base_id] then
        self.logger:warn("Ignored bounty substitution outside expected event bases", { base = util.mask_uid(base_id) })
        return
    end
    local incident = unwrap(context)
    local internal_group_id = guid_string(property(incident, "GroupGuid"))
    local broadcast_group_id = guid_string(property(incident, "BroadcastGroupGuid"))
    if (internal_group_id and not self:_request_identity_is_new(base_id, internal_group_id, incident))
        or (broadcast_group_id and not self:_request_identity_is_new(base_id, broadcast_group_id, incident)) then
        self.logger:info("Ignored a pre-existing or uncorrelatable native incident selection", { base = util.mask_uid(base_id) })
        return
    end
    local accepted_group
    local event_base
    if self.director and self.director.state and self.director.state.event then
        event_base = self.director.state.event.bases[base_id]
        accepted_group = event_base and event_base.groupId or nil
    end
    if not internal_group_id and not broadcast_group_id then
        self.logger:error("Ignored bounty selection without a stable native group identity", { base = util.mask_uid(base_id) })
        if self.director then self.director:on_composition_result(base_id, 0, 0, "group_identity_unavailable") end
        return
    end
    if not event_base or (event_base.status ~= "pending" and event_base.status ~= "active") then
        self.logger:warn("Ignored bounty selection outside an active event-base lifecycle", { base = util.mask_uid(base_id) })
        return
    end
    if accepted_group and accepted_group ~= internal_group_id and accepted_group ~= broadcast_group_id then
        self.logger:warn("Ignored bounty selection for a different group at an active event base", { base = util.mask_uid(base_id) })
        return
    end
    local reservation = self.selected_groups[base_id]
    if reservation then
        local internal_conflict = internal_group_id and reservation.internalId and internal_group_id ~= reservation.internalId
        local broadcast_conflict = broadcast_group_id and reservation.broadcastId and broadcast_group_id ~= reservation.broadcastId
        local identity_overlap = (internal_group_id and (internal_group_id == reservation.internalId or internal_group_id == reservation.broadcastId))
            or (broadcast_group_id and (broadcast_group_id == reservation.internalId or broadcast_group_id == reservation.broadcastId))
        if internal_conflict or broadcast_conflict or not identity_overlap then
            self.logger:warn("Ignored a second native selection identity for the same event base", { base = util.mask_uid(base_id) })
            if self.director then self.director:on_composition_result(base_id, 0, 0, "selection_identity_conflict") end
            return
        end
    else
        if not self:_request_window_open(base_id) then
            self.logger:warn("Ignored bounty selection without an active request window", { base = util.mask_uid(base_id) })
            return
        end
        reservation = { internalId = internal_group_id, broadcastId = broadcast_group_id }
        self.selected_groups[base_id] = reservation
    end
    if internal_group_id then self.owned_groups[internal_group_id] = base_id end
    if broadcast_group_id then self.owned_groups[broadcast_group_id] = base_id end
    local members = unwrap(out_members)
    if not members then
        self.logger:error("Bounty substitution output array is unavailable", { base = util.mask_uid(base_id), profile = self.profile_id })
        if self.director then self.director:on_composition_result(base_id, 0, 0, "output_array_unavailable") end
        return
    end
    local name_constructor = fname_constructor()
    if not name_constructor then
        self.logger:error("Bounty substitution requires FName construction")
        if self.director then self.director:on_composition_result(base_id, 0, 0, "fname_unavailable") end
        return
    end

    bounties.reset_selection(self.bounty_selector)
    local original_cursor = self.bounty_selector.cursor
    local original_replacements = self.bounty_selector.replacements
    local selected_count = 0
    pcall(function() selected_count = members:GetArrayNum() end)
    if selected_count < 1 then
        self.logger:error("Bounty substitution received an empty member array", { base = util.mask_uid(base_id), profile = self.profile_id })
        if self.director then self.director:on_composition_result(base_id, 0, 0, "empty_member_array") end
        return
    end
    local replaced_count = 0
    local assignments = {}
    local mutations = {}
    local prepare_ok, prepare_error = pcall(function()
        members:ForEach(function(_, element)
            local bounty = bounties.next(self.bounty_selector)
            if not bounty then
                return self.bounty_selector.profile.maximumReplacements ~= nil
            end
            local member = unwrap(element)
            if member == nil then
                error("selected member is unavailable")
            end
            local old_character_id = to_string(property(member, "CharacterID"))
            if old_character_id == "" then
                error("selected member CharacterID is unavailable")
            end
            local name_ok, bounty_name = pcall(name_constructor, bounty.id, 1)
            if not name_ok then
                error("unable to construct bounty FName: " .. bounty.id)
            end
            mutations[#mutations + 1] = {
                element = element,
                member = member,
                oldCharacterId = old_character_id,
                bountyName = bounty_name,
            }
            assignments[#assignments + 1] = bounty.id
        end)
    end)
    if not prepare_ok then
        self.bounty_selector.cursor = original_cursor
        self.bounty_selector.replacements = original_replacements
        self.logger:error("Bounty substitution preparation failed; native incident continues unranked", { base = util.mask_uid(base_id), error = prepare_error })
        if self.director then self.director:on_composition_result(base_id, 0, selected_count, tostring(prepare_error)) end
        return
    end
    if self.bounty_selector.profile.maximumReplacements == nil and #mutations ~= selected_count then
        self.bounty_selector.cursor = original_cursor
        self.bounty_selector.replacements = original_replacements
        local reason = string.format("expected preparation of all %d members but prepared %d", selected_count, #mutations)
        self.logger:error("Bounty substitution preparation was incomplete; native incident continues unranked", { base = util.mask_uid(base_id), error = reason })
        if self.director then self.director:on_composition_result(base_id, 0, selected_count, reason) end
        return
    end
    local mutation_ok, mutation_error = pcall(function()
        for _, mutation in ipairs(mutations) do
            mutation.member.CharacterID = mutation.bountyName
            mutation.element:set(mutation.member)
            replaced_count = replaced_count + 1
        end
    end)
    if not mutation_ok then
        self.bounty_selector.cursor = original_cursor
        self.bounty_selector.replacements = original_replacements
        local rollback_failed = false
        for _, mutation in ipairs(mutations) do
            local restored = pcall(function()
                mutation.member.CharacterID = name_constructor(mutation.oldCharacterId, 1)
                mutation.element:set(mutation.member)
            end)
            if not restored then rollback_failed = true end
        end
        local reason = tostring(mutation_error) .. (rollback_failed and "; rollback incomplete" or "")
        self.logger:error("Bounty substitution failed; native incident continues unranked", { base = util.mask_uid(base_id), error = reason })
        if self.director then self.director:on_composition_result(base_id, 0, selected_count, reason) end
        return
    end
    self.substitution_count = self.substitution_count + replaced_count
    self.logger:info("Applied bounty invasion profile", {
        base = util.mask_uid(base_id),
        profile = self.profile_id,
        replaced = replaced_count,
        selected = selected_count,
    })
    if self.director then
        self.director:on_composition_result(base_id, replaced_count, selected_count, nil, assignments)
    end
end

function Bridge:_on_select_invaders_post(context, _, _, _, out_members)
    if self:_selection_hook_scope(context) then
        self:_on_select_invaders(context, out_members)
    end
end

function Bridge:register()
    if self.registered then
        return true
    end
    local required = {}
    local native_enabled = self:native_start_guard()
    local laboratory = self.delivery_profile == "laboratory-native-test"
    local hooks_enabled = laboratory or native_enabled
    if laboratory and (self.config.capabilities.chatCommands or self.config.capabilities.observeCombat
        or self.config.capabilities.observeInvasions or self.config.capabilities.substituteBountyMembers) then
        if os.getenv("COMPUTERNAME") ~= "IMOUTO" then return false, "Laboratory hooks are IMOUTO-only." end
        local environment_ok, environment_error = self:preflight_environment()
        if not environment_ok then return false, environment_error end
    end
    if hooks_enabled and self.config.capabilities.observeCombat then
        required[#required + 1] = { "damage", HOOKS.damage, function(_, parameter) self:_on_damage(parameter) end }
        required[#required + 1] = { "death", HOOKS.death, function(_, parameter) self:_on_death(parameter) end }
    end
    if hooks_enabled and self.config.capabilities.observeInvasions then
        required[#required + 1] = { "invasion_declaration", HOOKS.invasion_declaration, function(context)
            local scope = self:_manager_hook_scope(context)
            if scope then
                self.logger:info("Native invasion declaration observed", { eventOpen = self.event_open })
            end
        end }
        required[#required + 1] = { "invasion_start", HOOKS.invasion_start, function(context, parameter)
            local scope = self:_manager_hook_scope(context)
            if not scope then return end
            local base_id, group_id, invader_type = self:_lifecycle_context(parameter)
            if self.config.diagnostics.traceHooks then self.logger:info("Invasion start hook", { base = util.mask_uid(base_id), group = util.mask_uid(group_id), discovery = self.discovery_open }) end
            if scope == "native-all-diagnostic" then
                self.logger:info("Native all-base diagnostic start observed", { base = util.mask_uid(base_id), group = util.mask_uid(group_id) })
            end
            local group_expected = self.owned_groups[group_id] == base_id and self:_request_identity_is_new(base_id, group_id)
            local native_discovery = self.profile_id == "native" and self.discovery_open and self:_request_window_open(base_id)
                and self:_request_identity_is_new(base_id, group_id)
            local existing_group
            if self.director and self.director.state and self.director.state.event and self.director.state.event.bases[base_id] then
                existing_group = self.director.state.event.bases[base_id].groupId
            end
            if base_id and group_id and (not existing_group or existing_group == group_id) and is_enemy_invader_type(invader_type) and self.expected_bases[base_id] and self.director and self.event_open and (group_expected or native_discovery) then
                if self.director:on_invasion_start(base_id, group_id) then
                    self.owned_groups[group_id] = base_id
                    if self.request_windows[base_id] then self.request_windows[base_id].status = "started" end
                    if base_id == self.probe_base_id then self.probe_confirmed = true end
                    self.logger:info("Correlated native invasion start confirmed", {
                        base = util.mask_uid(base_id),
                        group = util.mask_uid(group_id),
                        phase = self.request_windows[base_id] and self.request_windows[base_id].phase or "unknown",
                    })
                elseif not group_expected then
                    self.owned_groups[group_id] = nil
                end
            end
        end }
        required[#required + 1] = { "invasion_arrived", HOOKS.invasion_arrived, function(context, parameter)
            local scope = self:_manager_hook_scope(context)
            if not scope then return end
            local base_id, group_id = self:_lifecycle_context(parameter)
            self.logger:info("Native invasion arrival observed", { base = util.mask_uid(base_id), group = util.mask_uid(group_id), eventOpen = self.event_open })
        end }
        required[#required + 1] = { "invasion_timeout", HOOKS.invasion_timeout, function(context, parameter)
            local scope = self:_manager_hook_scope(context)
            if not scope then return end
            local base_id, group_id, invader_type = self:_lifecycle_context(parameter)
            if self.config.diagnostics.traceHooks then self.logger:info("Invasion timeout hook", { base = util.mask_uid(base_id), group = util.mask_uid(group_id) }) end
            if scope == "native-all-diagnostic" then
                self.logger:info("Native all-base diagnostic timeout observed", { base = util.mask_uid(base_id), group = util.mask_uid(group_id) })
            end
            if base_id and group_id and is_enemy_invader_type(invader_type) and self.owned_groups[group_id] == base_id and self.director then
                self.timed_out_bases[base_id] = true
                self.director:on_invasion_timeout(base_id, group_id)
            end
        end }
        required[#required + 1] = { "invasion_end", HOOKS.invasion_end, function(context, parameter)
            local scope = self:_manager_hook_scope(context)
            if not scope then return end
            local base_id, group_id, invader_type = self:_lifecycle_context(parameter)
            if self.config.diagnostics.traceHooks then self.logger:info("Invasion end hook", { base = util.mask_uid(base_id), group = util.mask_uid(group_id) }) end
            if scope == "native-all-diagnostic" then
                self.logger:info("Native all-base diagnostic end observed", { base = util.mask_uid(base_id), group = util.mask_uid(group_id) })
            end
            if base_id and group_id and is_enemy_invader_type(invader_type) and self.owned_groups[group_id] == base_id and self.director then
                self.director:on_invasion_end(base_id, group_id)
                self.owned_groups[group_id] = nil
                self.timed_out_bases[base_id] = nil
            end
        end }
        required[#required + 1] = { "invasion_cancel", HOOKS.invasion_cancel, function(context)
            if self:_manager_hook_scope(context) == "event" and self.director then self.director:on_invasion_cancel() end
        end }
    end
    if hooks_enabled and self.config.capabilities.substituteBountyMembers then
        required[#required + 1] = { "select_invaders", HOOKS.select_invaders, function(context, return_value, grade, biome, out_members)
            self:_on_select_invaders_post(context, return_value, grade, biome, out_members)
        end }
    end
    if hooks_enabled and self.config.capabilities.chatCommands then
        required[#required + 1] = { "chat", HOOKS.chat, function(context, message)
            if not self.director then return end
            local text = to_string(message)
            if not util.starts_with(util.trim(text), "!") then return end
            local controller = unwrap(context)
            local principal, principal_error = self:command_principal(controller)
            if principal then
                self.director:handle_chat(principal, text)
            else
                self.logger:warn("Ignored chat command without an authoritative principal", { reason = principal_error })
            end
        end }
    end

    local register_console = global("RegisterConsoleCommandGlobalHandler")
    if not native_enabled and type(register_console) ~= "function" then
        return false, "Diagnostic-only build requires a server console command handler"
    end
    if not native_enabled and self.diagnostic_command_directory then
        local loop_async, execute_game_thread = global("LoopAsync"), global("ExecuteInGameThread")
        if type(loop_async) ~= "function" or type(execute_game_thread) ~= "function" then
            return false, "Local diagnostic ingress requires LoopAsync and ExecuteInGameThread"
        end
        self.diagnostic_ingress = DiagnosticIngress.new({
            directory = self.diagnostic_command_directory,
            execute = function(token, step) return self:diagnose_preflight(token, step) end,
            enqueue = execute_game_thread,
        })
        if self.diagnostic_ingress.blocked then
            return false, "A prior diagnostic request is pending/in-flight; preserve and archive the command directory while stopped before a new run"
        end
        local ingress = self.diagnostic_ingress
        local loop_ok = pcall(loop_async, 1000, function()
            if not ingress.active then return true end
            if not self.registered then return false end
            local polled = pcall(function() ingress:poll() end)
            if not polled then ingress.blocked = true end
            return false
        end)
        if not loop_ok then ingress.active = false; return false, "Local diagnostic ingress initialization failed" end
    end
    for _, specification in ipairs(required) do
        local ok, hook_error = self:_register_hook(specification[1], specification[2], specification[3])
        if not ok then
            self:unregister()
            return false, specification[1] .. " hook failed: " .. hook_error
        end
    end
    if type(register_console) == "function" then
        local console_ok = pcall(register_console, "ped", function(command, parts, output)
            if not self.registered then return true end
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
            if output then pcall(function() output:Log(tostring(result or "ok")) end) end
            self.logger:info(ok and "Console command completed" or "Console command failed", { result = result })
            return true
        end)
        if not console_ok and not native_enabled then
            self:unregister()
            return false, "Preflight diagnostic console registration failed"
        end
    end

    if not hooks_enabled then
        self.registered = true
        self.logger:warn("Diagnostic-only build: no gameplay hooks or automatic native steps; local file ingress accepts one explicit operator request at a time")
        return true
    end

    local poll = function()
        if not self.periodic_active then return true end
        if not self.registered then return false end
        if self.director then
            local ok, tick_error = xpcall(function() self.director:tick() end, debug.traceback)
            if not ok then
                self.logger:error("Director tick failed", { error = tick_error })
            end
        end
        if self.experiments then self:poll_native_observations() end
        return false
    end
    self.periodic_active = true
    local loop = global("LoopInGameThreadWithDelay")
    if type(loop) == "function" then
        local ok, handle = pcall(loop, self.config.runtime.pollIntervalMs, poll)
        if ok and handle ~= false then
            self.loop_handle = handle
        else
            self:unregister()
            return false, "periodic scheduler failed: " .. tostring(handle)
        end
    else
        local legacy_loop = global("LoopAsync")
        local execute_game_thread = global("ExecuteInGameThread")
        if type(legacy_loop) == "function" and type(execute_game_thread) == "function" then
            local loop_ok, loop_result = pcall(legacy_loop, self.config.runtime.pollIntervalMs, function()
                if not self.periodic_active then return true end
                if not self.registered then return false end
                local queued, accepted = pcall(execute_game_thread, poll)
                if not queued or accepted == false then
                    self.periodic_active = false
                    self.logger:error("Game-thread polling stopped; native starts are locked.")
                    return true
                end
                return false
            end)
            if not loop_ok or loop_result == false then
                self:unregister()
                return false, "periodic scheduler registration failed"
            end
        else
            self:unregister()
            return false, "no supported periodic game-thread scheduler"
        end
    end
    self.registered = true
    if laboratory then self.logger:warn("Laboratory test controls loaded; in-game starts run automatic validation with native breadcrumbs. No manual preflight is required.") end
    return true
end

function Bridge:unregister()
    self.periodic_active = false
    if self.diagnostic_ingress then self.diagnostic_ingress.active = false end
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
    if self.experiments then self.experiments:clear() end
end

function Bridge:active_invasion_count(world)
    local count = 0
    for _, incident in ipairs(self:_find_all("PalInvaderIncidentBase")) do
        if valid(incident) then
            local in_scope = true
            if world then
                local world_ok, incident_world = call(incident, "GetWorld")
                in_scope = world_ok and same_object(incident_world, world)
            end
            if in_scope then
                local ok, executing = call(incident, "IsExecuting")
                if not ok or executing then count = count + 1 end
            end
        end
    end
    return count
end

function Bridge:preflight_environment()
    if self.config.mode ~= "laboratory" then
        return false, "alpha invasion mutation is laboratory-only"
    end
    local version = require("ped.version")
    if self.config.compatibility.requiredAdapter ~= version.adapter then
        return false, "configured adapter identity does not match this runtime"
    end
    local observed_build_id = os.getenv("PAL_EVENT_DIRECTOR_SERVER_BUILD_ID")
    if not observed_build_id or observed_build_id == "" then
        return false, "PAL_EVENT_DIRECTOR_SERVER_BUILD_ID is absent"
    end
    local build_allowed = false
    for _, candidate in ipairs(self.config.compatibility.allowedServerBuildIds) do
        if candidate == observed_build_id then build_allowed = true; break end
    end
    if not build_allowed then
        return false, "PAL_EVENT_DIRECTOR_SERVER_BUILD_ID is not allowlisted: " .. tostring(observed_build_id)
    end
    local runtime = global("UE4SS")
    if not runtime or type(runtime.GetVersion) ~= "function" then
        return false, "UE4SS version discovery is unavailable"
    end
    if #self.config.compatibility.allowedUe4ssVersions < 1 then
        return false, "no UE4SS version is allowlisted"
    end
    local ok, major, minor, patch = pcall(runtime.GetVersion)
    local current = ok and type(major) == "number" and type(minor) == "number" and type(patch) == "number"
        and string.format("%d.%d.%d", major, minor, patch) or "unknown"
    local allowed = false
    for _, candidate in ipairs(self.config.compatibility.allowedUe4ssVersions) do
        if candidate == current then allowed = true; break end
    end
    if not allowed then
        return false, "UE4SS version is not allowlisted: " .. current
    end
    return true, { serverBuildId = observed_build_id, ue4ssVersion = current }
end

function Bridge:_nearest_test_base(controller, world)
    local world_ok, current_world = self:_native_call("test-controller-world", controller, "GetWorld")
    if not world_ok or not same_object(current_world, world) then return nil, "requesting controller changed worlds" end
    local pawn_ok, pawn = self:_native_call("test-player-character", controller, "GetDefaultPlayerCharacter")
    if not pawn_ok or not valid(pawn) then return nil, "requesting player's character is unavailable" end
    local location_ok, location = self:_native_call("test-player-location", pawn, "K2_GetActorLocation")
    if not location_ok or location == nil then return nil, "requesting player's location is unavailable" end
    local manager_ok, manager = self:_native_call("test-base-manager", self:_utility(), "GetBaseCampManager", world)
    if not manager_ok or not valid(manager) then return nil, "base manager is unavailable" end
    local manager_world_ok, manager_world = self:_native_call("test-base-manager-world", manager, "GetWorld")
    if not manager_world_ok or not same_object(manager_world, world) then return nil, "base manager belongs to a different world" end
    local ranged_ok, ranged = self:_native_call("test-in-range-base", manager, "GetInRangedBaseCamp", location, 0)
    local nearest_ok, nearest = self:_native_call("test-nearest-base", manager, "GetNearestBaseCamp", location)
    if not ranged_ok or not nearest_ok or not valid(ranged) or not valid(nearest) then
        return nil, "stand inside an eligible base before using the nearest-base native test"
    end
    local ranged_id_ok, ranged_id = self:_native_call("test-in-range-id", ranged, "GetId")
    local nearest_id_ok, nearest_id = self:_native_call("test-nearest-id", nearest, "GetId")
    local id = ranged_id_ok and guid_string(ranged_id) or nil
    if not id or not nearest_id_ok or id ~= guid_string(nearest_id) then
        return nil, "nearest and in-range base identities do not agree"
    end
    return id
end

function Bridge:preflight_start(profile_id, control)
    local allowed, reason = self:native_start_guard()
    if not allowed then return false, reason end
    local control_ok, control_error = NativeExperiments.validate_context(control or {})
    if not control_ok then return false, control_error end
    self.pending_expected_bases = {}
    self.pending_native_base_ids = {}
    self.pending_base_guilds = {}
    self.pending_roster = {}
    self.pending_manager = nil
    self.pending_world = nil
    self.pending_admin_override = type(control) == "table" and control.admin == true
    self.pending_nearest_test = nil
    self.pending_native_control = type(control) == "table"
        and { requestNumber = control.requestNumber, requesterUid = control.requesterUid } or nil
    local environment_ok, environment_error = self:preflight_environment()
    if not environment_ok then
        return false, environment_error
    end
    local roster_ok, roster = self:_native_step("online-roster", function() return self:list_online_players() end)
    if not roster_ok then return false, roster end
    local resolved, manager, world, manager_error = self:_native_step("world-manager", function() return self:_resolve_world_manager(roster) end)
    if not resolved then return false, manager end
    if not manager then return false, manager_error end
    if not self.pending_admin_override then
        local settings_ok, invaders_enabled, settings_error =
            self:_native_step("world-invasion-settings", function() return self:_world_invaders_enabled(world) end)
        if not settings_ok then return false, invaders_enabled end
        if not invaders_enabled then return false, settings_error end
        local registry_ok, registered_ids, registration_error = self:_native_step("registered-bases", function() return self:_registered_base_ids(manager) end)
        if not registry_ok then return false, registered_ids end
        if not registered_ids then return false, registration_error end
        local scan_ok, active_count = self:_native_step("active-incidents", function() return self:active_invasion_count(world) end)
        if not scan_ok then return false, active_count end
        if active_count > 0 then
            return false, "a native invasion/visitor incident is already active; one incident per base is assumed and this alpha uses a global mutex"
        end
    end
    local profile = bounties.profile(profile_id)
    if not profile then
        return false, "unknown invasion profile"
    end
    if profile.mode ~= "native" then
        if not self.config.capabilities.substituteBountyMembers then
            return false, "bounty substitution capability is disabled"
        end
        local lookup_ok, selection_function = self:_native_step("selection-function", function() return self:_static_find(HOOKS.select_invaders) end)
        if not lookup_ok then return false, selection_function end
        if not valid(selection_function) then
            return false, "SelectInvaders is unavailable for bounty substitution"
        end
    end
    local selected_id
    if type(control) == "table" and control.nearestNativeTest then
        if not self.pending_admin_override or profile_id ~= "native" then return false, "nearest-base test requires the admin native profile" end
        local requester
        for _, player in ipairs(roster) do if player.uid == control.requesterUid then requester = player; break end end
        if not requester or not valid(requester.controller) then return false, "requesting controller is no longer online" end
        local id, nearest_error = self:_nearest_test_base(requester.controller, world)
        if not id then return false, nearest_error end
        selected_id = id
        local route = control.nativeTestRoute or "debug"
        local group = NativeExperiments.route(route).named_group and (control.nativeTestGroup or NATIVE_PROBE_GROUP) or nil
        self.pending_nearest_test = { controller = requester.controller, world = world, baseId = id, route = route, group = group }
    end
    local eligible_ok, base_set, native_ids, base_guilds, resolved_roster, eligibility_error =
        self:_native_step("eligible-bases", function()
            return self:_eligible_online_guild_bases(manager, roster, self.pending_admin_override, selected_id)
        end)
    if not eligible_ok then return false, base_set end
    if not base_set then return false, eligibility_error end
    if selected_id then
        if not base_set[selected_id] then return false, "nearest base is outside the eligible online-guild target set" end
        base_set, native_ids, base_guilds = { [selected_id] = true }, { [selected_id] = native_ids[selected_id] },
            { [selected_id] = base_guilds[selected_id] }
    end
    if #resolved_roster > self.config.limits.maxPlayers then
        return false, string.format("online roster count %d exceeds configured maximum %d", #resolved_roster, self.config.limits.maxPlayers)
    end
    local base_ids = util.sorted_keys(base_set)
    if #base_ids < 1 then return false, "no available base belongs to a guild with an online member" end
    if #base_ids > self.config.limits.maxBases then
        return false, string.format("registered base count %d exceeds configured maximum %d", #base_ids, self.config.limits.maxBases)
    end
    self.pending_expected_bases = base_set
    self.pending_native_base_ids = native_ids
    self.pending_base_guilds = base_guilds
    self.pending_roster = resolved_roster
    self.pending_manager = manager
    self.pending_world = world
    local test_route = self.pending_nearest_test and NativeExperiments.route(self.pending_nearest_test.route)
    local method = test_route and test_route.method
        or self.pending_admin_override and "RequestIncidentInvaderEnemy" or "StartInvaderMarchForBaseCamp"
    local owner = test_route and test_route.owner or "PalInvaderManager"
    local lookup_ok, function_object = self:_native_step("dispatch-function",
        function() return self:_static_find("/Script/Pal." .. owner .. ":" .. method) end)
    if not lookup_ok then return false, function_object end
    if not valid(function_object) then
        return false, method .. " is unavailable for this revision"
    end
    return true
end

function Bridge:_resolve_dispatch_target(manager, expected_base_id)
    local observers = property(manager, "Observers")
    if not observers then return nil, "PalInvaderManager.Observers is unavailable" end
    local target
    local iterated, iteration_error = pcall(function()
        observers:ForEach(function(key, value)
            if target then return end
            local key_id = guid_string(key)
            if key_id == expected_base_id then
                local observer = unwrap(value)
                local base = property(observer, "TargetBaseCamp")
                local model_ok, model_native_id = call(base, "GetId")
                local model_id = model_ok and guid_string(model_native_id) or nil
                local observer_id = guid_string(property(observer, "TargetBaseCampID"))
                target = {
                    observer = observer,
                    base = base,
                    nativeId = model_native_id,
                    keyId = key_id,
                    observerId = observer_id,
                    modelId = model_id,
                }
            end
        end)
    end)
    if not iterated then return nil, "unable to enumerate dispatch observer: " .. tostring(iteration_error) end
    if not target then return nil, "selected base is absent from the active manager observer map" end
    if not valid(target.observer) or not valid(target.base) or not target.nativeId then
        return nil, "selected base observer or native GUID is unavailable"
    end
    if target.keyId ~= expected_base_id or target.observerId ~= expected_base_id or target.modelId ~= expected_base_id then
        return nil, "observer key, TargetBaseCampID, and model GetId no longer agree"
    end
    return target
end

function Bridge:_prepare_probe_handoff(manager)
    local inspected, metadata, function_path = self:_native_step("probe-handoff-metadata", function()
        local owner = manager:GetClass()
        for _ = 1, PROBE_LIMITS.classes do
            if not valid(owner) then break end
            local functions = {}
            owner:ForEachFunction(function(fn)
                functions[#functions + 1] = fn
                if #functions >= PROBE_LIMITS.functions then return true end
                return nil
            end)
            for _, fn in ipairs(functions) do
                if not valid(fn) then error("Native probe metadata is unsupported", 0) end
                if fn:GetFName():ToString() == "RequestIncidentInvaderEnemy_BP" then
                    if not same_object(fn:GetOuter(), owner) then error("Native probe metadata is unsupported", 0) end
                    local blueprint = owner:IsA("/Script/Engine.BlueprintGeneratedClass")
                    local flags = fn:GetFunctionFlags()
                    if type(blueprint) ~= "boolean" or not util.is_integer(flags) then
                        error("Native probe metadata is unsupported", 0)
                    end
                    local native = (flags & 0x400) ~= 0
                    local result = { handoffResolution = blueprint and "blueprint" or "base-declaration",
                        handoffOwnerBlueprint = blueprint, handoffFunctionNative = native, handoffHookRegistered = false }
                    if not blueprint or native then return result end
                    local path = fn:GetFullName()
                    if type(path) ~= "string" or #path == 0 or #path > 1024 then
                        error("Native probe metadata is unsupported", 0)
                    end
                    return result, path
                end
            end
            if #functions >= PROBE_LIMITS.functions then
                return { handoffResolution = "function-limit", handoffHookRegistered = false }
            end
            owner = owner:GetSuperStruct()
        end
        return { handoffResolution = valid(owner) and "class-limit" or "not-found", handoffHookRegistered = false }
    end)
    if not inspected then return false, metadata end
    if function_path then
        local hooked, hook_error = self:_native_step("probe-handoff-register", function()
            local existing = self.hook_ids.probe_handoff
            if existing then
                if existing.path ~= function_path then error("Native probe observer registration failed", 0) end
                return
            end
            local ok = self:_register_hook("probe_handoff", function_path, function(context, base, parameter)
                if not self.event_open or not self.probe_base_id or self.native_fault then return end
                self:_native_step("probe-blueprint-handoff", function()
                    if self:_manager_hook_scope(context) ~= "event" then return end
                    local counts = self.probe_handoff_counts
                    if not counts then return end
                    counts.calls = counts.calls + 1
                    base, parameter = unwrap(base), unwrap(parameter)
                    local parameter_valid = valid(parameter)
                    if parameter_valid then counts.validParameters = counts.validParameters + 1 end
                    local parameter_matches = parameter_valid and guid_string(property(parameter, "TargetBaseCampID")) == self.probe_base_id
                    local base_matches = false
                    if valid(base) and base:IsA("/Script/Pal.PalBaseCampModel") then
                        local id_ok, id = self:_native_call("probe-handoff-base-id", base, "GetId")
                        if not id_ok then return end
                        base_matches = guid_string(id) == self.probe_base_id
                    end
                    if parameter_matches or base_matches then counts.probeCalls = counts.probeCalls + 1 end
                end)
            end, "script")
            if not ok then error("Native probe observer registration failed", 0) end
        end)
        if not hooked then return false, hook_error end
        metadata.handoffHookRegistered = true
    end
    self.probe_handoff_metadata = metadata
    self.probe_handoff_counts = { calls = 0, validParameters = 0, probeCalls = 0 }
    return true
end

function Bridge:_probe_group_inventory(manager, requested_group)
    local found, data, row_count = self:_native_step("probe-table-metadata", function()
        local data = unwrap(manager.InvaderEnemyDataTable)
        if not valid(data) or data:type() ~= "UDataTable" then error("Native probe table schema is unsupported", 0) end
        local row_struct = data:GetRowStruct()
        if not valid(row_struct) or row_struct:GetFName():ToString() ~= "PalInvaderDatabaseRow" then
            error("Native probe table schema is unsupported", 0)
        end
        local count = #data
        if not util.is_integer(count) or count < 0 then error("Native probe data has an unexpected type", 0) end
        return data, count
    end)
    if not found then return false, data end
    return self:_native_step("probe-table-rows", function()
        if not valid(data) then error("Native probe table schema is unsupported", 0) end
        local summary = { invaderTableRows = row_count, invaderRowsScanned = 0, invaderMatchingRows = 0,
            invaderMatchingWeightedRows = 0, probeGroupSpecified = requested_group ~= nil }
        local biomes = {}
        local catalog = {}
        data:ForEachRow(function(_, row)
            local name = unwrap(row.GroupName)
            if name == nil or name:type() ~= "FName" then error("Native probe data has an unexpected type", 0) end
            local group = name:ToString()
            if type(group) ~= "string" then error("Native probe data has an unexpected type", 0) end
            local biome = probe_field(row, "BiomeID", "number")
            local minimum = probe_field(row, "InvadeGradeMin", "number")
            local maximum = probe_field(row, "InvadeGradeMax", "number")
            local weight = probe_field(row, "Weight", "number")
            if not util.is_integer(biome) or biome < 0 or biome > 255 or not util.is_integer(minimum)
                or not util.is_integer(maximum) or minimum > maximum then
                error("Native probe data has an unexpected type", 0)
            end
            summary.invaderRowsScanned = summary.invaderRowsScanned + 1
            if self.experiment_current then
                local key = group .. "\0" .. tostring(biome)
                local entry = catalog[key]
                if not entry then
                    entry = { group = group, biome = biome, rows = 0, weightedRows = 0, requiredBuildRows = 0,
                        gradeMin = minimum, gradeMax = maximum,
                        selected = requested_group ~= nil and group:lower() == requested_group:lower() }
                    catalog[key] = entry
                end
                entry.rows = entry.rows + 1
                if weight > 0 then entry.weightedRows = entry.weightedRows + 1 end
                entry.gradeMin, entry.gradeMax = math.min(entry.gradeMin, minimum), math.max(entry.gradeMax, maximum)
                local wave = probe_field(row, "Wave", "number")
                entry.waveMin, entry.waveMax = math.min(entry.waveMin or wave, wave), math.max(entry.waveMax or wave, wave)
                local condition = unwrap(row.ConditionBuildObjectId)
                if condition == nil or condition:type() ~= "FName" then error("Native probe data has an unexpected type", 0) end
                if condition:ToString():lower() ~= "none" then entry.requiredBuildRows = entry.requiredBuildRows + 1 end
            end
            if not summary.probeGroupSpecified or group:lower() == requested_group:lower() then
                summary.invaderMatchingRows = summary.invaderMatchingRows + 1
                if weight > 0 then summary.invaderMatchingWeightedRows = summary.invaderMatchingWeightedRows + 1 end
                summary.invaderMatchingGradeMin = math.min(summary.invaderMatchingGradeMin or minimum, minimum)
                summary.invaderMatchingGradeMax = math.max(summary.invaderMatchingGradeMax or maximum, maximum)
                biomes[biome] = true
                if summary.probeGroupSpecified then summary.probeGroupName = group end
            end
            -- This iterator also double-removes Boolean false; nil continues safely.
            if summary.invaderRowsScanned >= PROBE_LIMITS.rows then return true end
            return nil
        end)
        if #data ~= row_count then error("Native probe data changed during observation", 0) end
        summary.invaderRowsComplete = summary.invaderRowsScanned == row_count
        if summary.probeGroupSpecified then
            if summary.invaderMatchingRows > 0 then summary.probeGroupPresent = true
            elseif summary.invaderRowsComplete then summary.probeGroupPresent = false end
        end
        for _, key in ipairs(util.sorted_keys(catalog)) do
            catalog[key].complete = summary.invaderRowsComplete
            self:_experiment_detail("group", catalog[key])
        end
        return summary, biomes
    end)
end

function Bridge:_probe_spawn_inventory(manager, base, biomes, world)
    world = world or self.event_world
    local settings_ok, settings = self:_native_call("probe-game-setting", self:_utility(), "GetGameSetting", world)
    if not settings_ok then return false, settings end
    local scanned, summary, candidates = self:_native_step("probe-spawn-geometry", function()
        if not valid(settings) or not valid(base) or not valid(manager) then
            error("Native probe data has an unexpected type", 0)
        end
        local minimum = probe_field(settings, "InvadeStartPoint_BaseCampRadius_Min_cm", "number")
        local maximum = probe_field(settings, "InvadeStartPoint_BaseCampRadius_Max_cm", "number")
        if minimum < 0 or maximum < minimum then error("Native probe data has an unexpected type", 0) end
        local origin = probe_vector(unwrap(base.Transform).Translation)
        if self.experiment_current then
            self:_experiment_detail("worker", { gradeOffset = probe_field(settings, "InvadeGradeOffset", "number") })
        end
        local points = unwrap(manager.InvadeStartLocationList)
        local count = #points
        if not util.is_integer(count) or count < 0 then error("Native probe data has an unexpected type", 0) end
        local result = { probeRadiusMinCm = minimum, probeRadiusMaxCm = maximum,
            probeWaterContinuousThresholdCm = probe_field(settings, "InvaderPathWaterContinuousDistanceThreshold", "number"),
            probeWaterTotalThresholdCm = probe_field(settings, "InvaderPathWaterTotalDistanceThreshold", "number"),
            probeRequiredBaseLevel = probe_field(settings, "InvadeOccurableBaseCampLevel", "number"),
            probePlayersInsideBase = container_count(unwrap(base.PlayerUIdsExistsInsideInServer)),
            probeStartPointCount = count, probeStartPointsScanned = 0,
            probeRadiusMatches2D = 0, probeRadiusMatches3D = 0, probeBiomeMatches2D = 0, probeBiomeMatches3D = 0,
            probeNavigationCandidates = 0, probeNavigationChecked = 0, probeNavigationNotDisabled = 0,
            probeNavigationDisabled = 0, probeNavigationUnavailable = 0, probeNavigationForeignWorld = 0 }
        local candidates, detail_rows = {}, {}
        local min_squared, max_squared = minimum * minimum, maximum * maximum
        points:ForEach(function(_, entry)
            local point = unwrap(entry)
            local location = probe_vector(point.Location)
            local biome = probe_field(point, "BiomeType", "number")
            if not util.is_integer(biome) or biome < 0 or biome > 255 then
                error("Native probe data has an unexpected type", 0)
            end
            local dx, dy, dz = location[1] - origin[1], location[2] - origin[2], location[3] - origin[3]
            local horizontal = dx * dx + dy * dy
            local spatial = horizontal + dz * dz
            local in_2d = horizontal >= min_squared and horizontal <= max_squared
            local in_3d = spatial >= min_squared and spatial <= max_squared
            result.probeStartPointsScanned = result.probeStartPointsScanned + 1
            if in_2d then
                result.probeRadiusMatches2D = result.probeRadiusMatches2D + 1
                if biomes[biome] then result.probeBiomeMatches2D = result.probeBiomeMatches2D + 1 end
            end
            if in_3d then
                result.probeRadiusMatches3D = result.probeRadiusMatches3D + 1
                if biomes[biome] then result.probeBiomeMatches3D = result.probeBiomeMatches3D + 1 end
            end
            if in_2d or in_3d then
                result.probeNavigationCandidates = result.probeNavigationCandidates + 1
                if #candidates < PROBE_LIMITS.navigation then
                    candidates[#candidates + 1] = { actor = unwrap(point.SourceActor), index = result.probeStartPointsScanned,
                        location = { X = location[1], Y = location[2], Z = location[3] }, spatial = spatial, in3D = in_3d }
                end
            end
            if self.experiment_current then
                detail_rows[#detail_rows + 1] = { index = result.probeStartPointsScanned,
                    horizontalMeters = math.sqrt(horizontal) / 100, spatialMeters = math.sqrt(spatial) / 100,
                    verticalMeters = math.abs(dz) / 100, biome = biome, radius2D = in_2d, radius3D = in_3d,
                    biomeMatch = biomes[biome] == true, actorValid = valid(unwrap(point.SourceActor)), inspected = false }
            end
            if result.probeStartPointsScanned >= PROBE_LIMITS.points then return true end
            return nil
        end)
        if #points ~= count then error("Native probe data changed during observation", 0) end
        result.probeGeometryComplete = result.probeStartPointsScanned == count
        if self.experiment_current then
            self.experiment_current.query_origin = { X = origin[1], Y = origin[2], Z = origin[3] }
            self.experiment_current.candidate_details = detail_rows
        end
        return result, candidates
    end)
    if not scanned then return false, summary end
    for _, candidate in ipairs(candidates) do
        local read, invoker = self:_native_step("probe-navigation-component", function()
            if not valid(candidate.actor) then return nil end
            return unwrap(candidate.actor.NavInvokerComponent)
        end)
        if not read then return false, invoker end
        local detail = self.experiment_current and self.experiment_current.candidate_details[candidate.index]
        if detail then detail.invokerValid = valid(invoker) end
        if not valid(invoker) then
            summary.probeNavigationUnavailable = summary.probeNavigationUnavailable + 1
        else
            local world_ok, invoker_world = self:_native_call("probe-navigation-world", invoker, "GetWorld")
            if not world_ok then return false, invoker_world end
            if detail then detail.sameWorld = same_object(invoker_world, world) end
            if not same_object(invoker_world, world) then
                summary.probeNavigationForeignWorld = summary.probeNavigationForeignWorld + 1
            else
                local checked, disabled = self:_native_call("probe-navigation-disabled", invoker, "IsDisableInvorker")
                if not checked then return false, disabled end
                local boolean_ok, boolean_error = self:_native_step("probe-navigation-result", function()
                    if type(disabled) ~= "boolean" then error("Native probe data has an unexpected type", 0) end
                end)
                if not boolean_ok then return false, boolean_error end
                if detail then detail.disabled, detail.inspected = disabled, true end
                summary.probeNavigationChecked = summary.probeNavigationChecked + 1
                if disabled then summary.probeNavigationDisabled = summary.probeNavigationDisabled + 1
                else summary.probeNavigationNotDisabled = summary.probeNavigationNotDisabled + 1 end
            end
        end
    end
    summary.probeNavigationComplete = summary.probeGeometryComplete
        and summary.probeNavigationChecked == summary.probeNavigationCandidates
    if self.experiment_current then
        local recorded, record_error = self:_native_step("experiment-candidate-records", function()
            local scope = self.experiment_current
            for _, detail in ipairs(scope.candidate_details) do self:_experiment_detail("candidate", detail, scope) end
            table.sort(candidates, function(left, right)
                if left.in3D ~= right.in3D then return left.in3D end
                if left.spatial ~= right.spatial then return left.spatial < right.spatial end
                return left.index < right.index
            end)
            scope.query_points = {}
            for index = 1, math.min(3, #candidates) do scope.query_points[index] = candidates[index].location end
            scope.candidate_details = nil
        end)
        if not recorded then return false, record_error end
    end
    return true, summary
end

function Bridge:_capture_probe_prerequisites(manager, base)
    local observed, observer_error = self:_prepare_probe_handoff(manager)
    if not observed then return false, observer_error end
    local test = self.event_nearest_test
    local route = test and NativeExperiments.route(test.route)
    local group = route and route.named_group and (test.group or NATIVE_PROBE_GROUP) or nil
    local grouped, summary, biomes = self:_probe_group_inventory(manager, group)
    if not grouped then return false, summary end
    local sampled, geometry = self:_probe_spawn_inventory(manager, base, biomes)
    if not sampled then return false, geometry end
    for key, value in pairs(geometry) do summary[key] = value end
    summary.nativeProbeRecorded = true
    summary.probeDataComplete = summary.invaderRowsComplete and summary.probeGeometryComplete and summary.probeNavigationComplete
    return true, summary
end

function Bridge:_dispatch_snapshot(manager, expected_base_id, phase)
    local target, target_error = self:_resolve_dispatch_target(manager, expected_base_id)
    local diagnostic = {
        phase = phase,
        base = util.mask_uid(expected_base_id),
        manager = full_name(manager) or "unknown",
        guidResolved = target ~= nil,
        guidResolutionError = target_error,
        observerKey = target and util.mask_uid(target.keyId) or "unavailable",
        observerTargetId = target and util.mask_uid(target.observerId) or "unavailable",
        modelId = target and util.mask_uid(target.modelId) or "unavailable",
        guidSourcesMatch = target and target.keyId == target.observerId and target.keyId == target.modelId or false,
        declarationHookCalls = self.hook_observed.invasion_declaration or 0,
        selectionHookCalls = self.hook_observed.select_invaders or 0,
        startHookCalls = self.hook_observed.invasion_start or 0,
    }
    if target then
        local available_ok, available = call(target.base, "IsAvailable")
        if available_ok then diagnostic.baseAvailable = or_unavailable(scalar(available))
        else diagnostic.baseAvailable = "unavailable" end
        diagnostic.baseState = or_unavailable(scalar(property(target.base, "CurrentState")))
        diagnostic.baseLevel = or_unavailable(scalar(property(target.base, "Level_InGuildProperty")))
        diagnostic.baseTemporary = scalar(property(target.base, "bTemporary"))
        diagnostic.baseIgnoreInvader = scalar(property(target.base, "bIgnoreInvader"))
        diagnostic.observerInvading = scalar(property(target.observer, "bIsInvading"))
        diagnostic.observerPathSearching = scalar(property(target.observer, "bIsInvaderPathSearching"))
        diagnostic.observerCoolTime = scalar(property(target.observer, "bIsCoolTime"))
        diagnostic.coolTimeFinish = scalar(property(target.observer, "CoolTimeFinish"))
        diagnostic.coolTimeElapsed = scalar(property(target.observer, "CoolTimeElapsed"))
        diagnostic.playerInBaseTimer = scalar(property(target.observer, "PlayerInBaseCampTimer"))
        diagnostic.playerHandleCount = container_count(property(target.observer, "PlayerHandlesCache"))
    end
    if phase == "probe-before" and target and not self.event_admin_override then
        local captured, prerequisites = self:_capture_probe_prerequisites(manager, target.base)
        if not captured then return diagnostic, target, prerequisites end
        for key, value in pairs(prerequisites) do diagnostic[key] = value end
    end
    for key, value in pairs(self.probe_handoff_metadata or {}) do diagnostic[key] = value end
    local handoff = self.probe_handoff_counts or {}
    diagnostic.handoffObservedCalls = handoff.calls or 0
    diagnostic.handoffProbeCalls = handoff.probeCalls or 0
    diagnostic.handoffValidParameterCalls = handoff.validParameters or 0
    local incidents = property(manager, "Incidents")
    local incident_count = 0
    local incident_for_base = false
    local incident_state
    local incident_can_execute
    local incident_arrived
    local incident_group
    local baseline = { complete = false, groups = {}, incidents = {} }
    local identities_complete = true
    if incidents then
        local inspected, inspection_error = pcall(function()
            incidents:ForEach(function(key, value)
                incident_count = incident_count + 1
                if guid_string(key) == expected_base_id then
                    local incident = unwrap(value)
                    incident_for_base = true
                    local address = object_address(incident)
                    if address then baseline.incidents[address] = true end
                    incident_state = scalar(property(incident, "ExecState"))
                    incident_can_execute = scalar(property(incident, "bCanExecute"))
                    incident_arrived = scalar(property(incident, "bIsArrived"))
                    incident_group = guid_string(property(incident, "GroupGuid"))
                        or guid_string(property(incident, "BroadcastGroupGuid"))
                    if not address or not incident_group then identities_complete = false end
                    for _, name in ipairs({ "GroupGuid", "BroadcastGroupGuid" }) do
                        local group = guid_string(property(incident, name))
                        if group then baseline.groups[group] = true end
                    end
                end
            end)
        end)
        if not inspected then diagnostic.incidentInspectionError = PreflightDiagnostic.classify_error(inspection_error)
        else baseline.complete = identities_complete end
    else
        diagnostic.incidentInspectionError = "Incidents map unavailable"
    end
    diagnostic.incidentCount = incident_count
    diagnostic.incidentForBase = incident_for_base
    diagnostic.incidentState = or_unavailable(incident_state)
    diagnostic.incidentCanExecute = incident_can_execute
    diagnostic.incidentArrived = incident_arrived
    diagnostic.incidentGroup = incident_group and util.mask_uid(incident_group) or "unavailable"
    diagnostic.managerInvaderInfo = valid(property(manager, "InvaderInfo"))
    local start_log_id = guid_string(property(manager, "StartInvaderLogId"))
    diagnostic.managerStartLogId = start_log_id and util.mask_uid(start_log_id) or "unavailable"
    diagnostic.managerPathFinder = valid(property(manager, "PathFinder"))
    if phase == "probe-timeout" then
        local points = property(manager, "InvadeStartLocationList")
        local source_actors, invokers, waiting = 0, 0, 0
        local inspected = points ~= nil and pcall(function()
            points:ForEach(function(_, point)
                local actor = property(point, "SourceActor")
                if valid(actor) then
                    source_actors = source_actors + 1
                    local invoker = property(actor, "NavInvokerComponent")
                    if valid(invoker) then
                        invokers = invokers + 1
                        if property(invoker, "bIsWaitWorldPartition") == true then waiting = waiting + 1 end
                    end
                end
            end)
        end)
        diagnostic.startPointNavigationReadable = inspected == true
        if inspected then
            diagnostic.startPointActorsLoaded = source_actors
            diagnostic.startPointInvokersLoaded = invokers
            diagnostic.startPointInvokersConfiguredToWaitForPartition = waiting
        end
    end
    local function summarize_keyed_map(map_name)
        local map = property(manager, map_name)
        if not map then return nil, nil, map_name .. " unavailable" end
        local count = 0
        local contains_base = false
        local inspected, inspection_error = pcall(function()
            map:ForEach(function(key)
                count = count + 1
                if guid_string(key) == expected_base_id then contains_base = true end
            end)
        end)
        if not inspected then return nil, nil, tostring(inspection_error) end
        return count, contains_base
    end
    diagnostic.startLocationCount, diagnostic.startLocationForBase, diagnostic.startLocationInspectionError = summarize_keyed_map("InvadeStartLocationList")
    diagnostic.savedInvaderStateCount, diagnostic.savedInvaderStateForBase, diagnostic.savedInvaderStateInspectionError = summarize_keyed_map("InvaderSaveDataMapCache")
    diagnostic.negotiatorRow = scalar(property(manager, "NegotiatorRowName")) or "unavailable"
    diagnostic.worldInvaderEnabled = self:_world_invaders_enabled(self.event_world)
    return diagnostic, target, target_error, baseline
end

function Bridge:_log_dispatch_snapshot(diagnostic)
    self.logger:info("Selected-base native invasion state", diagnostic)
end

function Bridge:_dispatch_selected_base(base_id, dispatch_phase)
    if not self.experiments or dispatch_phase ~= "probe" or self.event_admin_override then
        return self:_dispatch_selected_base_core(base_id, dispatch_phase)
    end
    local previous = self.experiment_current
    local called, result = self:_native_step("experiment-probe", function()
        local allowed, reason = self:native_start_guard()
        if not allowed then return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = reason } end
        local target, target_error = self:_resolve_dispatch_target(self.event_manager, base_id)
        if not target then return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = target_error } end
        local test, control = self.event_nearest_test, self.event_native_control or {}
        local route = test and (test.route or "debug") or "regular"
        local specification = test and NativeExperiments.route(test.route)
        if test and not specification then
            return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = "native experiment route is invalid" }
        end
        local group = specification and specification.named_group and (test.group or NATIVE_PROBE_GROUP) or nil
        local opened, scope = self:_open_native_observation(self.event_manager, self.event_world, target.base, base_id,
            route, group, control.requestNumber, control.requesterUid)
        if not opened then return end
        self.experiment_current = scope
        self.native_observer:workers(scope)
        self:_experiment_detail("scope", { phase = "before", route = route }, scope)
        local dispatched = self:_dispatch_selected_base_core(base_id, dispatch_phase)
        if self.native_fault then return dispatched end
        self:_experiment_detail("scope", { phase = "after",
            code = (dispatched.status == "dispatch_call_failed" or dispatched.status == "dispatch_precondition_failed") and "rejected" or "returned" }, scope)
        self.native_observer:sample(scope)
        scope.query_points, scope.query_origin = nil, nil
        return dispatched
    end)
    self.experiment_current = previous
    if not called then return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = result } end
    return result
end

function Bridge:_dispatch_selected_base_core(base_id, dispatch_phase)
    local allowed, reason = self:native_start_guard()
    if not allowed then return { baseId = base_id, status = "dispatch_quarantined", error = reason } end
    local manager = self.event_manager
    if not valid(manager) then
        return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = "pinned world invasion manager is unavailable" }
    end
    local snapshot_ok, before, target, target_error, baseline = self:_native_step("dispatch-before",
        function() return self:_dispatch_snapshot(manager, base_id, dispatch_phase .. "-before") end)
    if not snapshot_ok then return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = before } end
    self:_log_dispatch_snapshot(before)
    if not target then
        return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = target_error, before = before }
    end
    if self.event_admin_override and not valid(target.observer) then
        return { baseId = base_id, phase = dispatch_phase, status = "dispatch_precondition_failed", error = "native base observer is invalid", before = before }
    end
    if not self.event_admin_override and (before.worldInvaderEnabled ~= true or before.baseAvailable ~= true or before.baseIgnoreInvader ~= false
        or before.observerInvading ~= false or before.observerPathSearching ~= false
        or type(before.observerCoolTime) ~= "boolean" or (before.observerCoolTime and not self.event_admin_override)
        or before.incidentForBase) then
        return {
            baseId = base_id,
            phase = dispatch_phase,
            status = "dispatch_precondition_failed",
            error = "native observer or manager state rejected selected-base dispatch",
            before = before,
        }
    end
    local now = self.clock()
    self.request_windows[base_id] = {
        openedAt = now,
        expiresAt = now + self.config.siegeLeague.startDiscoverySeconds,
        status = "requesting",
        phase = dispatch_phase,
        baseline = baseline,
    }
    self.dispatching_base_id = base_id
    self.selection_open = true
    if self.event_admin_override then
        self.logger:info("Admin native request delegates gameplay policy to Palworld", {
            phase = dispatch_phase, worldEnabled = before.worldInvaderEnabled, baseAvailable = before.baseAvailable,
            ignoredByNative = before.baseIgnoreInvader, invading = before.observerInvading,
            pathfinding = before.observerPathSearching, cooldown = before.observerCoolTime,
            occupied = before.incidentForBase, baselineComplete = baseline and baseline.complete,
        })
    end
    local observation
    if self.event_admin_override and self.native_observer then
        local recorded, scope = self:_native_step("admin-observation-open", function()
            local test, control = self.event_nearest_test, self.event_native_control or {}
            local specification = test and NativeExperiments.route(test.route)
            local group = specification and specification.named_group and (test.group or NATIVE_PROBE_GROUP) or nil
            return self.native_observer:open({ manager = manager, world = self.event_world, base = target.base, base_id = base_id,
                route = test and (test.route or "debug") or "regular", group = group,
                request = control.requestNumber, recipient = control.requesterUid,
                deadline = self.clock() + self.config.siegeLeague.startDiscoverySeconds })
        end)
        if not recorded then
            self.selection_open, self.dispatching_base_id = false, nil
            self.request_windows[base_id].status = "dispatch_call_failed"
            return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = scope, before = before }
        end
        observation = scope
    end
    local ok, result
    local native_result
    local function invoke(label, owner, method, ...)
        local called, returned = self:_native_call(label, owner, method, ...)
        native_result = { method = method, returned = called, returnKind = called and type(returned) or "error" }
        if called and type(returned) == "boolean" then native_result.boolean = returned end
        if called then self.logger:info("Native invasion call returned", native_result) end
        return called, returned
    end
    local test_route
    if self.event_nearest_test then
        local test = self.event_nearest_test
        test_route = NativeExperiments.route(test.route)
        local current_id, target_error = self:_nearest_test_base(test.controller, test.world)
        if not test_route then
            ok, result = false, "native experiment route is invalid"
        elseif current_id ~= base_id or current_id ~= test.baseId then
            ok, result = false, target_error or "requester moved away from the selected native-test base"
        end
    end
    if ok ~= false then
        if test_route and test_route.named_group then
            local test = self.event_nearest_test
            local name_ok, group = self:_native_step("test-native-group", function()
                local constructor = fname_constructor()
                if not constructor then error("FName constructor unavailable", 0) end
                return constructor(test.group or NATIVE_PROBE_GROUP)
            end)
            if name_ok then
                ok, result = invoke("debug-nearest-native", test.controller, "Debug_InvaderMarchForNearCamp", group, true)
            else
                ok, result = false, group
            end
        elseif (test_route and test_route.method == "RequestIncidentInvaderEnemy") or (not test_route and self.event_admin_override) then
            ok, result = invoke("admin-request-incident", manager, "RequestIncidentInvaderEnemy", target.nativeId, target.observer)
            if ok then
                ok, result = self:_native_step("admin-admission-result", function()
                    if type(result) ~= "boolean" then error("Unexpected native enemy-incident admission result", 0) end
                    return result
                end)
                if ok and not result then ok, result = false, "Native enemy-incident request rejected the base; no invasion was accepted." end
            end
        else
            ok, result = invoke("start-invader-march", manager, "StartInvaderMarchForBaseCamp", target.nativeId)
        end
    end
    self.selection_open = false
    self.dispatching_base_id = nil
    local request = self.request_windows[base_id]
    if observation and not self.native_fault then
        local logged, log_error = self:_native_step("admin-observation-result", function()
            self:_experiment_detail("scope", { phase = "after", code = ok and "returned" or "rejected" }, observation)
        end)
        if not logged then ok, result = false, log_error end
    end
    if not ok then
        request.status = "dispatch_call_failed"
        request.error = tostring(result)
        return {
            baseId = base_id,
            phase = dispatch_phase,
            status = "dispatch_call_failed",
            error = tostring(result),
            before = before,
            native = native_result,
        }
    end
    local after_ok, after = self:_native_step("dispatch-after",
        function() return self:_dispatch_snapshot(manager, base_id, dispatch_phase .. "-after") end)
    if not after_ok then
        request.status = "dispatch_call_failed"
        return { baseId = base_id, phase = dispatch_phase, status = "dispatch_call_failed", error = after, before = before, native = native_result }
    end
    self:_log_dispatch_snapshot(after)
    local status = request.status == "started" and "lifecycle_confirmed" or dispatch_phase .. "_call_returned"
    request.status = status
    return {
        baseId = base_id,
        phase = dispatch_phase,
        status = status,
        before = before,
        after = after,
        native = native_result,
    }
end

function Bridge:start_all_invasions()
    local allowed, reason = self:native_start_guard()
    if not allowed then return false, reason end
    if not valid(self.event_manager) then
        return false, "pinned world invasion manager became unavailable before dispatch"
    end
    local selected, order = self:_native_step("probe-selection", function()
        local occupied = {}
        local observers = property(self.event_manager, "Observers")
        if not observers then error("Observer map is unavailable for probe selection", 0) end
        observers:ForEach(function(key, value)
            local id = guid_string(key)
            if id and self.expected_bases[id] then
                local observer = unwrap(value)
                local handles = container_count(property(observer, "PlayerHandlesCache"))
                local timer = property(observer, "PlayerInBaseCampTimer")
                occupied[id] = (type(handles) == "number" and handles > 0) or (type(timer) == "number" and timer > 0)
            end
        end)
        local ids = util.sorted_keys(self.expected_bases)
        table.sort(ids, function(left, right)
            if (occupied[left] == true) ~= (occupied[right] == true) then return occupied[left] == true end
            return left < right
        end)
        return ids
    end)
    if not selected then return false, order end
    self.dispatch_order = order
    self.probe_base_id = self.dispatch_order[1]
    self.probe_confirmed = false
    self.fanout_dispatched = false
    if not self.probe_base_id then return false, "no eligible selected base exists" end
    local requests = {}
    if self.event_admin_override then
        self.fanout_dispatched = true
        local requested, attempted, first_error = 0, 0, nil
        for index, base_id in ipairs(self.dispatch_order) do
            local phase = index == 1 and "probe" or "fanout"
            local result
            if self.native_fault then
                result = { baseId = base_id, phase = phase, status = "dispatch_skipped_native_fault", error = self.native_fault }
            else
                result = self:_dispatch_selected_base(base_id, phase)
                attempted = attempted + 1
            end
            requests[#requests + 1] = result
            if result.status == "probe_call_returned" or result.status == "fanout_call_returned" or result.status == "lifecycle_confirmed" then
                requested = requested + 1
            else
                first_error = first_error or result.error or "native dispatch did not return successfully"
            end
        end
        local accepted = requested > 0 and not self.native_fault
        return accepted, { requested = requested, attempted = attempted, requests = requests, phase = "admin-all",
            allTargetsAttempted = attempted == #self.dispatch_order, error = not accepted and (self.native_fault or first_error) or nil }
    end
    local probe = self:_dispatch_selected_base(self.probe_base_id, "probe")
    requests[#requests + 1] = probe
    for index = 2, #self.dispatch_order do
        requests[#requests + 1] = {
            baseId = self.dispatch_order[index],
            phase = "fanout",
            status = "awaiting_probe_confirmation",
        }
    end
    if probe.status == "dispatch_call_failed" or probe.status == "dispatch_precondition_failed" then
        return false, { requested = 0, requests = requests, error = probe.error or "probe dispatch failed" }
    end
    return true, { requested = 1, requests = requests, phase = "probe" }
end

function Bridge:capture_start_timeout()
    if not self.probe_base_id or not valid(self.event_manager) then
        return false, "Probe manager or target is unavailable at timeout."
    end
    local ok, snapshot = self:_native_step("dispatch-timeout",
        function() return self:_dispatch_snapshot(self.event_manager, self.probe_base_id, "probe-timeout") end)
    if not ok then return false, snapshot end
    self:_log_dispatch_snapshot(snapshot)
    return true, snapshot
end

function Bridge:continue_invasion_dispatch()
    local allowed, reason = self:native_start_guard()
    if not allowed then return false, reason end
    if self.fanout_dispatched then return true, { requested = 0, requests = {}, phase = "already_dispatched" } end
    if not self.probe_confirmed then return false, "probe lifecycle is not confirmed" end
    self.fanout_dispatched = true
    local requests = {}
    local requested = 0
    for index = 2, #self.dispatch_order do
        local request = self:_dispatch_selected_base(self.dispatch_order[index], "fanout")
        requests[#requests + 1] = request
        if request.status ~= "dispatch_call_failed" and request.status ~= "dispatch_precondition_failed" then
            requested = requested + 1
        end
    end
    if requested < #requests then
        self.logger:warn("Some confirmed-probe fanout calls were rejected", { failures = #requests - requested, requested = requested })
    end
    return true, { requested = requested, requests = requests, phase = "fanout" }
end

function Bridge:diagnose_native_start_all(confirmation)
    if self.delivery_profile == "laboratory-native-test" then
        return false, "Native-all comparison remains disabled; use the guarded selected-base start command."
    end
    local allowed, reason = self:native_start_guard()
    if not allowed then return false, reason end
    self.native_all_diagnostic_until = 0
    self.native_all_diagnostic_manager = nil
    self.native_all_diagnostic_world = nil
    if confirmation ~= "confirm-disposable-start-all" then
        return false, "diagnostic requires confirm-disposable-start-all"
    end
    if tostring(os.getenv("COMPUTERNAME") or ""):upper() ~= "IMOUTO" then
        return false, "native all-base diagnostic is restricted to IMOUTO"
    end
    local director_status = self.director and self.director.state and self.director.state.status or "idle"
    if self.event_open or director_status == "starting" or director_status == "active" or director_status == "resolving"
        or director_status == "recovery_required" then
        return false, "an event is already active"
    end
    local environment_ok, environment_error = self:preflight_environment()
    if not environment_ok then return false, environment_error end
    local roster = self:list_online_players()
    local manager, world, manager_error = self:_resolve_world_manager(roster)
    if not manager then return false, manager_error end
    local registered_ids, registration_error = self:_registered_base_ids(manager)
    if not registered_ids then return false, registration_error end
    if #registered_ids < 1 then return false, "no registered invasion observers exist" end
    if self:active_invasion_count(world) > 0 then return false, "a native invasion or visitor incident is already active" end
    local function_object = self:_static_find("/Script/Pal.PalInvaderManager:StartInvaderMarchAll")
    if not valid(function_object) then return false, "StartInvaderMarchAll is unavailable for this revision" end
    table.sort(registered_ids)
    local previous_world = self.event_world
    self.event_world = world
    local before = self:_dispatch_snapshot(manager, registered_ids[1], "native-all-before")
    self:_log_dispatch_snapshot(before)
    if before.worldInvaderEnabled ~= true then
        self.event_world = previous_world
        return false, "native enemy invasions are disabled or unreadable in world settings"
    end
    self.native_all_diagnostic_manager = manager
    self.native_all_diagnostic_world = world
    self.native_all_diagnostic_until = self.clock() + self.config.siegeLeague.startDiscoverySeconds
    local called, call_error = call(manager, "StartInvaderMarchAll")
    local after = self:_dispatch_snapshot(manager, registered_ids[1], "native-all-after")
    self:_log_dispatch_snapshot(after)
    self.event_world = previous_world
    if not called then
        self.native_all_diagnostic_until = 0
        self.native_all_diagnostic_manager = nil
        self.native_all_diagnostic_world = nil
        return false, "StartInvaderMarchAll call failed: " .. tostring(call_error)
    end
    self.logger:warn("Disposable native all-base comparison call returned; acceptance still requires lifecycle evidence", {
        observerCount = #registered_ids,
        incidentCountBefore = before.incidentCount,
        incidentCountAfter = after.incidentCount,
    })
    return true, "StartInvaderMarchAll returned; inspect masked declaration/start/arrival logs before the diagnostic window closes"
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
    return ok, announce_error
end

function Bridge:send_chat(message, recipient_uid)
    local game_state = self:_find_first("PalGameStateInGame")
    local utility = self:_utility()
    if not valid(game_state) or not valid(utility) then
        self.logger:warn("System chat skipped; Palworld messaging objects are unavailable", { recipient = util.mask_uid(recipient_uid) })
        return false, "Palworld messaging objects are unavailable"
    end
    local string_constructor = global("FString")
    local payload = message
    if type(string_constructor) == "function" then
        local ok, converted = pcall(string_constructor, message)
        if ok then payload = converted end
    end
    local ok, chat_error
    local recipient_count
    if recipient_uid then
        local receivers = {}
        for _, player in ipairs(self:list_online_players()) do
            if player.uid == recipient_uid then receivers[#receivers + 1] = player.guid end
        end
        if #receivers == 0 then
            self.logger:warn("Private system chat recipient is no longer online", { recipient = util.mask_uid(recipient_uid) })
            return false, "chat recipient is no longer online"
        end
        recipient_count = 1
        ok, chat_error = call(utility, "SendSystemToPlayerChat", game_state, payload, receivers)
    else
        recipient_count = #self:list_online_players()
        if recipient_count == 0 then return true end
        ok, chat_error = call(utility, "SendSystemAnnounce", game_state, payload)
    end
    if not ok then
        self.logger:warn("System chat failed", { error = chat_error, recipients = recipient_count })
    end
    return ok, chat_error
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
    local name_constructor = fname_constructor()
    if not name_constructor then
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

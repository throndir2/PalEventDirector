local Experiments = {}
Experiments.__index = Experiments

Experiments.default_group = "Invader_Group_NPC_Grade5_Hunter"
Experiments.sample_seconds = { 1, 5, 15, 30, 60, 120, 300, 600 }
Experiments.maximum_scopes = 8

local routes = {
    debug = { owner = "PalPlayerController", method = "Debug_InvaderMarchForNearCamp", named_group = true },
    admission = { owner = "PalInvaderManager", method = "RequestIncidentInvaderEnemy" },
    march = { owner = "PalInvaderManager", method = "StartInvaderMarchForBaseCamp" },
}

function Experiments.route(name)
    if name == nil then name = "debug" end
    if type(name) ~= "string" then return nil end
    return routes[name]
end

function Experiments.validate_context(context)
    if type(context) ~= "table" then return false, "native experiment context must be a table" end
    if context.nearestNativeTest ~= nil and type(context.nearestNativeTest) ~= "boolean" then
        return false, "native experiment scope must be Boolean"
    end
    if context.nativeTestRoute ~= nil or context.nativeTestGroup ~= nil then
        if context.nearestNativeTest ~= true then return false, "native experiment options require a single-base test" end
    end
    if not context.nearestNativeTest then return true end
    local route = Experiments.route(context.nativeTestRoute)
    if not route then return false, "native test route must be debug, admission, or march" end
    local group = context.nativeTestGroup
    if group ~= nil and (not route.named_group or type(group) ~= "string" or #group > 128
        or not group:match("^[A-Za-z][A-Za-z0-9_]+$")) then
        return false, "only the debug route accepts a bounded alphanumeric native group name"
    end
    return true
end

local schemas = {
    scope = {
        number = "deadline sampleDue skippedSamples slots totalScopes",
        boolean = "late complete groupWithheld",
        token = "route phase code",
        group = "group",
    },
    group = {
        number = "rows weightedRows gradeMin gradeMax biome requiredBuildRows waveMin waveMax",
        group = "group",
        boolean = "selected complete",
    },
    candidate = {
        number = "index horizontalMeters spatialMeters verticalMeters biome",
        boolean = "radius2D radius3D biomeMatch actorValid invokerValid sameWorld disabled inspected",
    },
    worker = {
        number = "index level slots sampled available minimum maximum average gradeOffset",
        boolean = "complete availableParameter",
    },
    signature = {
        token = "method owner parameter fieldType code",
        number = "flags index offset parameters",
        boolean = "available registered native net server reliable complete returnParameter",
    },
    incident = {
        number = "slot generation type state members controllers companions grade wave maximumWave",
        boolean = "valid matchedBase initialized executing completed canceled canExecute arrived usesPaths pathfinder",
        token = "className",
    },
    state = {
        number = "slots observedSlots playerCache playersInsideBase playerTimer cooldownElapsed cooldownFinish grade wave maximumWave waitingIncidents executingIncidents residentIncidents remainingStartSeconds remainingWaveSeconds",
        boolean = "managerValid worldValid baseValid occupied pathfinding invading cooldown incidentForBase pathfinder invaderInfo firstWave complete",
    },
    hook = {
        token = "method code",
        number = "grade biome returnedCount members",
        boolean = "matchedBase contextValid parameterValid returnReadable returnedBoolean outputReadable late",
    },
    path = {
        number = "index points lengthMeters cost queries completePaths",
        boolean = "objectValid pathValid partial lengthReadable costReadable navigationBuilding navigationLocked",
    },
}

local tokens = {
    route = { debug = true, admission = true, march = true, regular = true, inspect = true },
    phase = { opened = true, before = true, after = true, sample = true, closed = true, rejected = true },
    code = { complete = true, evicted = true, unavailable = true, native_fault = true, missing = true,
        unsupported = true, expired = true, not_loaded = true, limit = true, wrong_world = true, returned = true, rejected = true },
}

local schema_fields = {}
for kind, groups in pairs(schemas) do
    local fields = {}
    for value_kind, names in pairs(groups) do
        for name in names:gmatch("%S+") do fields[name] = value_kind end
    end
    schema_fields[kind] = fields
end

local function identifier(value, maximum)
    return type(value) == "string" and #value <= maximum and value:match("^[A-Za-z_][A-Za-z0-9_]*$")
        and not value:find(string.rep("%x", 32))
end

function Experiments.validate_record(record)
    if type(record) ~= "table" or record.schemaVersion ~= 1 or not schema_fields[record.kind] then return false end
    local common = { schemaVersion = true, kind = true, sequence = true, run = true, observation = true, request = true, timestamp = true, elapsed = true }
    for _, key in ipairs({ "sequence", "run", "observation", "timestamp" }) do
        local value = record[key]
        if type(value) ~= "number" or value ~= math.floor(value) or value < 0 or value > 10000000000 then return false end
    end
    for key, value in pairs(record) do
        if key == "request" or key == "elapsed" then
            if type(value) ~= "number" or value ~= value or value < 0 or value > 100000000 then return false end
        elseif not common[key] then
            local expected = schema_fields[record.kind][key]
            if expected == "number" then
                if type(value) ~= "number" or value ~= value or math.abs(value) > 4294967295 then return false end
            elseif expected == "boolean" then
                if type(value) ~= "boolean" then return false end
            elseif expected == "group" then
                if not identifier(value, 128) then return false end
            elseif expected == "token" then
                if not identifier(value, 96) or (tokens[key] and not tokens[key][value]) then return false end
            else
                return false
            end
        end
    end
    return true
end

function Experiments.new(options)
    return setmetatable({ clock = assert(options.clock), emit = assert(options.emit), run = assert(options.run),
        sequence = 0, record_sequence = 0, scopes = {} }, Experiments)
end

function Experiments:record(scope, kind, fields)
    local now = self.clock()
    self.record_sequence = self.record_sequence + 1
    local record = { schemaVersion = 1, kind = kind, sequence = self.record_sequence, run = self.run, observation = scope.id,
        request = scope.request, timestamp = now, elapsed = math.max(0, now - scope.opened) }
    for key, value in pairs(fields) do
        if record[key] ~= nil or key == "request" then return false, "experiment record header cannot be replaced" end
        record[key] = value
    end
    if not Experiments.validate_record(record) then return false, "experiment record shape rejected" end
    return self.emit(record)
end

function Experiments:open(values)
    self.sequence = self.sequence + 1
    local scope = { id = self.sequence, request = values.request, route = values.route, group = values.group,
        opened = self.clock(), next_sample = 1, manager = values.manager, world = values.world,
        base = values.base, base_id = values.base_id, recipient = values.recipient,
        deadline = values.deadline, aliases = {}, next_alias = 0, closed = false }
    if #self.scopes >= Experiments.maximum_scopes then
        local previous = self.scopes[1]
        local recorded, reason = self:record(previous, "scope", { phase = "closed", code = "evicted" })
        if not recorded then return nil, reason end
        previous.closed = true
        table.remove(self.scopes, 1)
    end
    local recorded, reason = self:record(scope, "scope", { phase = "opened", route = scope.route,
        group = identifier(scope.group, 128) and scope.group or nil, groupWithheld = scope.group ~= nil and not identifier(scope.group, 128),
        deadline = scope.deadline })
    if not recorded then return nil, reason end
    self.scopes[#self.scopes + 1] = scope
    return scope
end

function Experiments:next_sample()
    local now = self.clock()
    for _, scope in ipairs(self.scopes) do
        if not scope.closed then
            local index = scope.next_sample
            local due = Experiments.sample_seconds[index]
            if due and now >= scope.opened + due then
                local last = index
                while Experiments.sample_seconds[last + 1] and now >= scope.opened + Experiments.sample_seconds[last + 1] do
                    last = last + 1
                end
                scope.next_sample = last + 1
                return scope, Experiments.sample_seconds[last], last - index
            end
        end
    end
end

function Experiments:close(scope, code)
    local ok, reason = self:record(scope, "scope", { phase = "closed", code = code })
    if not ok then return false, reason end
    scope.closed = true
    for index, candidate in ipairs(self.scopes) do
        if candidate == scope then table.remove(self.scopes, index); break end
    end
    return true
end

function Experiments:clear()
    self.scopes = {}
end

return Experiments

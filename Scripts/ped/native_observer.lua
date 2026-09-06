local Experiments = require("ped.native_experiments")

local Observer = {}
Observer.__index = Observer

local INCIDENT_METHODS = {
    { name = "SelectInvaders", result = "boolean", selection = true },
    { name = "GetCandidateStartLocations", result = "count" },
    { name = "GetInvaderStartPoint", result = "boolean" },
    { name = "SpawnMemberCharacters" },
    { name = "OnGenerated" }, { name = "OnInitialized" }, { name = "OnBegin" },
    { name = "OnStartInvade" }, { name = "OnInvaderArrived" }, { name = "OnEndInvade" },
    { name = "OnCanceled" }, { name = "OnForceStop" }, { name = "OnEnd" },
}
local MANAGER_METHODS = {
    { name = "RequestIncidentInvaderEnemy_BP", result = "object", manager = true },
    { name = "RequestIncidentVisitorNPC_BP", result = "object", manager = true },
}
local SYSTEM_METHODS = {
    { name = "RequestIncident", result = "object", system = true },
    { name = "GenerateIncident", result = "object", system = true },
    { name = "IsIncidentBeginAllowed", result = "boolean", system = true },
}

function Observer.new(bridge, access)
    return setmetatable({ bridge = bridge, a = access, hooks = {}, hook_count = 0 }, Observer)
end

function Observer:call(label, object, method, ...)
    local ok, result = self.bridge:_native_call(label, object, method, ...)
    if not ok then error(result, 0) end
    return result
end

function Observer:record(scope, kind, fields)
    self.bridge:_experiment_detail(kind, fields, scope)
end

function Observer:field(object, name)
    object = self.a.unwrap(object)
    if object == nil then return nil end
    return self.a.unwrap(object[name])
end

function Observer:open(values)
    local scope = self.bridge.experiments:open(values)
    if not scope then error("Native experiment logging failed", 0) end
    return scope
end

function Observer:signature(scope, fn, method)
    if not self.a.valid(fn) then
        self:record(scope, "signature", { method = method, available = false, code = "missing" })
        return nil
    end
    local flags = fn:GetFunctionFlags()
    local parameters = {}
    fn:ForEachProperty(function(field)
        parameters[#parameters + 1] = field
        if #parameters >= 16 then return true end
        return nil
    end)
    local info = { method = method, owner = fn:GetOuter():GetFName():ToString(), available = true, flags = flags, native = (flags & 0x400) ~= 0,
        net = (flags & 0x40) ~= 0, server = (flags & 0x200000) ~= 0, reliable = (flags & 0x80) ~= 0,
        parameters = #parameters, complete = #parameters < 16 }
    self:record(scope, "signature", info)
    for index, field in ipairs(parameters) do
        if not self.a.valid(field) then error("Native probe metadata is unsupported", 0) end
        local name = field:GetFName():ToString()
        self:record(scope, "signature", { method = method, index = index, parameter = name,
            fieldType = field:GetClass():GetFName():ToString(), offset = field:GetOffset_Internal(),
            returnParameter = name == "ReturnValue" })
    end
    return info
end

function Observer:find_functions(owner, wanted)
    local found = {}
    for _ = 1, 8 do
        if not self.a.valid(owner) then break end
        local functions = {}
        owner:ForEachFunction(function(fn)
            functions[#functions + 1] = fn
            if #functions >= 128 then return true end
            return nil
        end)
        for _, fn in ipairs(functions) do
            if not self.a.valid(fn) then error("Native probe metadata is unsupported", 0) end
            local name = fn:GetFName():ToString()
            if wanted[name] and not found[name] then found[name] = fn end
        end
        if #functions >= 128 then break end
        owner = owner:GetSuperStruct()
    end
    return found
end

function Observer:observe_hook(specification, native, context, ...)
    local bridge, a = self.bridge, self.a
    if bridge.native_fault or #bridge.experiments.scopes == 0 then return end
    local arguments = table.pack(...)
    bridge:_native_step("experiment-lifecycle-hook", function()
        context = a.unwrap(context)
        if not a.valid(context) then return end
        local world = self:call("experiment-hook-world", context, "GetWorld")
        local first = native and specification.result and 2 or 1
        local returned
        if native and specification.result then returned = a.unwrap(arguments[1]) end
        local subject = context
        if specification.system then
            if specification.result == "object" then subject = returned
            else subject = a.unwrap(arguments[first]) end
        elseif specification.manager then
            subject = a.unwrap(arguments[first])
        end
        local base_id
        if a.valid(subject) and subject:IsA("/Script/Pal.PalInvaderIncidentBase") then
            local base = self:call("experiment-hook-base", subject, "GetTargetCampModel")
            if a.valid(base) then base_id = a.guid(self:call("experiment-hook-base-id", base, "GetId")) end
        elseif a.valid(subject) and subject:IsA("/Script/Pal.PalBaseCampModel") then
            base_id = a.guid(self:call("experiment-hook-model-id", subject, "GetId"))
        end
        for _, scope in ipairs(bridge.experiments.scopes) do
            if a.same(world, scope.world) then
                local fields = { method = specification.name, contextValid = true,
                    matchedBase = base_id ~= nil and base_id == scope.base_id,
                    late = scope.deadline ~= nil and bridge.clock() > scope.deadline,
                    returnReadable = returned ~= nil }
                if specification.result == "boolean" then
                    fields.returnReadable = type(returned) == "boolean"
                    if fields.returnReadable then fields.returnedBoolean = returned end
                elseif specification.result == "count" then
                    fields.returnReadable = type(returned) == "number"
                    if fields.returnReadable then fields.returnedCount = returned end
                    local output = a.unwrap(arguments[first])
                    fields.members = a.count(output)
                    fields.outputReadable = fields.members ~= nil
                elseif specification.result == "object" then
                    if native then fields.parameterValid = a.valid(returned) end
                end
                if specification.selection then
                    local grade, biome = a.unwrap(arguments[first]), a.unwrap(arguments[first + 1])
                    if type(grade) == "number" then fields.grade = grade end
                    if type(biome) == "number" then fields.biome = biome end
                    fields.members = a.count(a.unwrap(arguments[first + 2]))
                    fields.outputReadable = fields.members ~= nil
                elseif specification.name == "GetInvaderStartPoint" then
                    local vector = a.unwrap(arguments[first])
                    fields.outputReadable = vector ~= nil and type(self:field(vector, "X")) == "number"
                        and type(self:field(vector, "Y")) == "number" and type(self:field(vector, "Z")) == "number"
                end
                self:record(scope, "hook", fields)
            end
        end
    end)
end

function Observer:hook_class(scope, owner, specifications)
    local wanted = {}
    for _, specification in ipairs(specifications) do wanted[specification.name] = true end
    local found = self:find_functions(owner, wanted)
    for _, specification in ipairs(specifications) do
        local fn = found[specification.name]
        local information = self:signature(scope, fn, specification.name)
        if information then
            local path = fn:GetFullName()
            if not self.hooks[path] then
                if self.hook_count >= 96 then
                    self:record(scope, "signature", { method = specification.name, registered = false, code = "limit" })
                else
                    local name = "experiment_" .. (self.hook_count + 1)
                    local native = information.native
                    local ok = self.bridge:_register_hook(name, path, function(...)
                        self:observe_hook(specification, native, ...)
                    end, not native and "script" or nil)
                    if not ok then error("Native probe observer registration failed", 0) end
                    self.hooks[path] = true
                    self.hook_count = self.hook_count + 1
                end
            end
            self:record(scope, "signature", { method = specification.name, registered = self.hooks[path] == true,
                native = information.native })
        end
    end
end

function Observer:prepare(scope)
    local a = self.a
    for route in pairs({ debug = true, admission = true, march = true }) do
        local specification = Experiments.route(route)
        local fn = self.bridge:_static_find("/Script/Pal." .. specification.owner .. ":" .. specification.method)
        self:signature(scope, fn, specification.method)
    end
    self:hook_class(scope, scope.manager:GetClass(), MANAGER_METHODS)
    local system = self:call("experiment-incident-system", self.bridge:_utility(), "GetIncidentSystem", scope.world)
    if not a.valid(system) or not a.same(self:call("experiment-system-world", system, "GetWorld"), scope.world) then
        error("Native probe metadata is unsupported", 0)
    end
    scope.system = system
    self:hook_class(scope, system:GetClass(), SYSTEM_METHODS)
    local root = self.bridge:_static_find("/Script/Pal.PalInvaderIncidentBase")
    if not a.valid(root) then error("Native probe metadata is unsupported", 0) end
    local classes = {}
    local map = a.unwrap(system.IncidentClassMap)
    map:ForEach(function(_, value)
        classes[#classes + 1] = a.unwrap(value)
        if #classes >= 128 then return true end
        return nil
    end)
    local inspected = 0
    for _, class in ipairs(classes) do
        local parent = class
        for _ = 1, 8 do
            if not a.valid(parent) then break end
            if a.same(parent, root) then
                self:hook_class(scope, class, INCIDENT_METHODS)
                inspected = inspected + 1
                break
            end
            parent = parent:GetSuperStruct()
        end
        if inspected >= 8 then break end
    end
    self:record(scope, "signature", { method = "IncidentClassMap", parameters = #classes,
        available = true, complete = #classes < 128 and inspected < 8 })
end

function Observer:workers(scope)
    local a = self.a
    local result = { workerAvailable = 0 }
    local director = self:field(scope.base, "WorkerDirector")
    if not a.valid(director) then
        self:record(scope, "worker", { available = 0, complete = false })
        return result
    end
    local container = self:field(director, "CharacterContainer")
    if not a.valid(container) then
        self:record(scope, "worker", { available = 0, complete = false })
        return result
    end
    local slots = a.unwrap(container.SlotArray)
    local total, sampled, sum = #slots, 0, 0
    for index = 1, math.min(total, 32) do
        -- The pinned TArray getter extends arrays on an out-of-range read.
        if index > #slots then break end
        local slot = a.unwrap(slots[index])
        sampled = sampled + 1
        local handle = a.valid(slot) and self:field(slot, "Handle") or nil
        local parameter
        if a.valid(handle) then parameter = self:call("experiment-worker-parameter", handle, "TryGetIndividualParameter") end
        local fields = { index = index, availableParameter = a.valid(parameter) }
        if fields.availableParameter then
            local level = self:call("experiment-worker-level", parameter, "GetLevel")
            if type(level) ~= "number" or level < 0 or level > 10000 then error("Native probe data has an unexpected type", 0) end
            fields.level = level
            result.workerAvailable = result.workerAvailable + 1
            result.workerMinimum = math.min(result.workerMinimum or level, level)
            result.workerMaximum = math.max(result.workerMaximum or level, level)
            sum = sum + level
        end
        self:record(scope, "worker", fields)
    end
    self:record(scope, "worker", { slots = total, sampled = sampled, available = result.workerAvailable,
        minimum = result.workerMinimum, maximum = result.workerMaximum,
        average = result.workerAvailable > 0 and sum / result.workerAvailable or nil,
        complete = sampled == total and #slots == total })
    return result
end

function Observer:sample(scope)
    local bridge, a = self.bridge, self.a
    if not a.valid(scope.manager) or not a.valid(scope.world) or not a.valid(scope.base) then
        self:record(scope, "state", { managerValid = a.valid(scope.manager), worldValid = a.valid(scope.world), baseValid = a.valid(scope.base) })
        return false, "expired"
    end
    if not a.same(self:call("experiment-sample-world", scope.manager, "GetWorld"), scope.world) then return false, "wrong_world" end
    local target = bridge:_resolve_dispatch_target(scope.manager, scope.base_id)
    if not target then return false, "expired" end
    local observer = target.observer
    local state = { managerValid = true, worldValid = true, baseValid = true,
        occupied = false, slots = 0, observedSlots = 0,
        pathfinding = self:field(observer, "bIsInvaderPathSearching"),
        invading = self:field(observer, "bIsInvading"), cooldown = self:field(observer, "bIsCoolTime"),
        cooldownElapsed = self:field(observer, "CoolTimeElapsed"), cooldownFinish = self:field(observer, "CoolTimeFinish"),
        playerCache = a.count(self:field(observer, "PlayerHandlesCache")),
        playersInsideBase = a.count(self:field(scope.base, "PlayerUIdsExistsInsideInServer")),
        playerTimer = self:field(observer, "PlayerInBaseCampTimer"),
        pathfinder = a.valid(self:field(scope.manager, "PathFinder")) }
    local incidents = a.unwrap(scope.manager.Incidents)
    state.slots = #incidents
    local entries = {}
    incidents:ForEach(function(key, value)
        entries[#entries + 1] = { id = a.guid(key), incident = a.unwrap(value) }
        if #entries >= 16 then return true end
        return nil
    end)
    state.observedSlots = #entries
    if scope.returned_incident then
        state.returnedIncident = a.valid(scope.returned_incident)
        state.returnedIncidentInSample = false
        for _, entry in ipairs(entries) do
            if a.same(entry.incident, scope.returned_incident) then
                entry.returnedHandle, state.returnedIncidentInSample = true, true
            end
        end
        if not state.returnedIncidentInSample then
            entries[#entries + 1] = { incident = scope.returned_incident, returnedHandle = true }
        end
    end
    for _, entry in ipairs(entries) do
        local id, incident = entry.id, entry.incident
        local alias = id and scope.aliases[id] or (entry.returnedHandle and scope.returned_alias or nil)
        local address = a.address(incident)
        if not alias then
            scope.next_alias = scope.next_alias + 1
            alias = { index = scope.next_alias, generation = 1, address = address }
            if id and scope.next_alias <= 64 then scope.aliases[id] = alias end
            if not id and entry.returnedHandle then scope.returned_alias = alias end
        elseif alias.address ~= address then
            alias.address, alias.generation = address, alias.generation + 1
        end
        local fields = { slot = alias.index, generation = alias.generation, valid = a.valid(incident),
            matchedBase = id ~= nil and id == scope.base_id, returnedHandle = entry.returnedHandle }
        if fields.matchedBase then state.occupied = true end
        if fields.valid then
            if entry.returnedHandle then
                local target = self:call("experiment-returned-target", incident, "GetTargetCampModel")
                fields.matchedBase = a.valid(target)
                    and a.guid(self:call("experiment-returned-target-id", target, "GetId")) == scope.base_id
            end
            fields.type = self:field(incident, "InvaderType")
            fields.state = self:field(incident, "ExecState")
            fields.initialized = self:call("experiment-incident-initialized", incident, "IsInitialized")
            fields.executing = self:call("experiment-incident-executing", incident, "IsExecuting")
            fields.completed = self:call("experiment-incident-completed", incident, "IsCompleted")
            fields.canceled = self:call("experiment-incident-canceled", incident, "IsCanceled")
            fields.className = incident:GetClass():GetFName():ToString()
            fields.canExecute = self:field(incident, "bCanExecute")
            fields.arrived = self:field(incident, "bIsArrived")
            fields.usesPaths = self:field(incident, "bUseFindPaths")
            fields.pathfinder = a.valid(self:field(incident, "PathFinder"))
            fields.members = a.count(self:field(incident, "InvaderMember"))
            fields.controllers = a.count(self:field(incident, "MemberController"))
            fields.companions = a.count(self:field(incident, "OtomoController"))
        end
        self:record(scope, "incident", fields)
    end
    local info = self:field(scope.manager, "InvaderInfo")
    state.invaderInfo = a.valid(info)
    if state.invaderInfo then
        state.grade = self:field(info, "InvadeGrade")
        state.wave = self:field(info, "CurrentWave")
        state.maximumWave = self:field(info, "WaveMax")
        state.firstWave = self:field(info, "bIsFirstWaveStarted")
    end
    state.complete = state.observedSlots == state.slots
    if not state.complete and not state.occupied then state.occupied = nil end
    if a.valid(scope.system) then
        state.waitingIncidents = a.count(self:field(scope.system, "WaitingIncidents"))
        state.executingIncidents = a.count(self:field(scope.system, "ExecuteIncidents"))
        state.residentIncidents = a.count(self:field(scope.system, "ResidentIncidents"))
    end
    if state.invaderInfo then
        state.remainingStartSeconds = self:call("experiment-remaining-start", info, "GetRemainInvadeStartRealTimeSeconds")
        state.remainingWaveSeconds = self:call("experiment-remaining-wave", info, "GetRemainWaveEndRealTimeSeconds")
    end
    self:record(scope, "state", state)
    return true, state
end

function Observer:checked_fields(owner, maximum)
    local fields = {}
    owner:ForEachProperty(function(field)
        fields[#fields + 1] = field
        if #fields > maximum then return true end
        return nil
    end)
    if #fields > maximum then error("Native navigation signature is unsupported", 0) end
    local result = {}
    for _, field in ipairs(fields) do
        if not self.a.valid(field) then error("Native navigation signature is unsupported", 0) end
        local name = field:GetFName():ToString()
        if result[name] then error("Native navigation signature is unsupported", 0) end
        result[name] = { field = field, kind = field:GetClass():GetFName():ToString(), offset = field:GetOffset_Internal() }
    end
    return result, #fields
end

function Observer:vector_width(field)
    local struct = field:GetStruct()
    if not self.a.valid(struct) or struct:GetFName():ToString() ~= "Vector" then
        error("Native navigation signature is unsupported", 0)
    end
    local fields, count = self:checked_fields(struct, 3)
    local width = fields.X and (fields.X.kind == "DoubleProperty" and 8 or fields.X.kind == "FloatProperty" and 4 or nil)
    if count ~= 3 or not width then error("Native navigation signature is unsupported", 0) end
    for index, name in ipairs({ "X", "Y", "Z" }) do
        local value = fields[name]
        if not value or value.kind ~= fields.X.kind or value.offset ~= (index - 1) * width then
            error("Native navigation signature is unsupported", 0)
        end
    end
    return width
end

function Observer:check_navigation_signature(scope, fn, method, query, static, numeric)
    local info = self:signature(scope, fn, method)
    if not info or not info.native or (static and (info.flags & 0x2000) == 0) then
        error("Native navigation signature is unsupported", 0)
    end
    local fields, count = self:checked_fields(fn, query and 6 or static and 2 or 1)
    local expected
    if query then
        if not fields.PathStart or not fields.PathEnd or fields.PathStart.kind ~= "StructProperty"
            or fields.PathEnd.kind ~= "StructProperty" then error("Native navigation signature is unsupported", 0) end
        local width = self:vector_width(fields.PathStart.field)
        if self:vector_width(fields.PathEnd.field) ~= width then error("Native navigation signature is unsupported", 0) end
        local context_offset = width == 8 and 56 or 32
        expected = {
            WorldContextObject = { "ObjectProperty", 0 }, PathStart = { "StructProperty", 8 },
            PathEnd = { "StructProperty", 8 + width * 3 }, PathfindingContext = { "ObjectProperty", context_offset },
            FilterClass = { "ClassProperty", context_offset + 8 }, ReturnValue = { "ObjectProperty", context_offset + 16 },
        }
    elseif static then
        expected = { WorldContextObject = { "ObjectProperty", 0 }, ReturnValue = { "BoolProperty", 8 } }
    else
        local kind = fields.ReturnValue and fields.ReturnValue.kind
        if numeric and kind ~= "DoubleProperty" and kind ~= "FloatProperty" then
            error("Native navigation signature is unsupported", 0)
        end
        expected = { ReturnValue = { numeric and kind or "BoolProperty", 0 } }
    end
    local expected_count = 0
    for name, shape in pairs(expected) do
        expected_count = expected_count + 1
        local actual = fields[name]
        if not actual or actual.kind ~= shape[1] or actual.offset ~= shape[2] then
            error("Native navigation signature is unsupported", 0)
        end
    end
    if count ~= expected_count then error("Native navigation signature is unsupported", 0) end
end

function Observer:invoke(label, fn, receiver, ...)
    local arguments = table.pack(...)
    local ok, result = self.bridge:_native_step(label, function()
        if not self.a.valid(fn) or not self.a.valid(receiver) then error("Native navigation signature is unsupported", 0) end
        return fn(receiver, table.unpack(arguments, 1, arguments.n))
    end)
    if not ok then error(result, 0) end
    return result
end

function Observer:path_queries(scope, controller)
    local bridge, a = self.bridge, self.a
    local current = bridge:_nearest_test_base(controller, scope.world)
    if current ~= scope.base_id then return false, "requester is no longer inside the inspected base" end
    local pawn = self:call("path-query-pawn", controller, "GetDefaultPlayerCharacter")
    if not a.valid(pawn) or not a.same(self:call("path-query-world", pawn, "GetWorld"), scope.world) then
        return false, "path-query pawn is unavailable in the inspected world"
    end
    local nav_class = bridge:_static_find("/Script/NavigationSystem.NavigationSystemV1")
    local filter = bridge:_static_find("/Script/NavigationSystem.NavigationQueryFilter")
    if not a.valid(nav_class) or not a.valid(filter) then return false, "native navigation classes are not loaded" end
    local cdo = nav_class:GetCDO()
    if not a.valid(cdo) then return false, "native navigation default object is unavailable" end
    local functions = {}
    for _, specification in ipairs({
        { "FindPathToLocationSynchronously", "NavigationSystemV1", true, true },
        { "IsNavigationBeingBuilt", "NavigationSystemV1", false, true },
        { "IsNavigationBeingBuiltOrLocked", "NavigationSystemV1", false, true },
        { "IsValid", "NavigationPath" }, { "IsPartial", "NavigationPath" },
        { "GetPathLength", "NavigationPath", false, false, true },
        { "GetPathCost", "NavigationPath", false, false, true },
    }) do
        local fn = bridge:_static_find("/Script/NavigationSystem." .. specification[2] .. ":" .. specification[1])
        self:check_navigation_signature(scope, fn, specification[1], specification[3], specification[4], specification[5])
        functions[specification[1]] = fn
    end
    local building = self:invoke("path-navigation-building", functions.IsNavigationBeingBuilt, cdo, scope.world)
    local locked = self:invoke("path-navigation-locked", functions.IsNavigationBeingBuiltOrLocked, cdo, scope.world)
    if type(building) ~= "boolean" or type(locked) ~= "boolean" then error("Native probe data has an unexpected type", 0) end
    self:record(scope, "path", { navigationBuilding = building, navigationLocked = locked })
    local origin, points = scope.query_origin, scope.query_points
    if type(origin) ~= "table" or type(points) ~= "table" then return false, "no bounded spawn geometry was collected" end
    local function finite(value)
        return type(value) == "number" and value == value and math.abs(value) < math.huge
    end
    local function vector(value)
        return type(value) == "table" and finite(rawget(value, "X")) and finite(rawget(value, "Y")) and finite(rawget(value, "Z"))
    end
    if not vector(origin) then error("Native probe data has an unexpected type", 0) end
    local result = { queries = 0, complete = 0 }
    for index = 1, math.min(3, #points) do
        if not vector(points[index]) then error("Native probe data has an unexpected type", 0) end
        local path = self:invoke("path-query", functions.FindPathToLocationSynchronously, cdo, scope.world,
            points[index], origin, pawn, filter)
        result.queries = result.queries + 1
        local fields = { index = index, objectValid = a.valid(path) }
        if fields.objectValid then
            if not path:IsA("/Script/NavigationSystem.NavigationPath") then error("Native probe data has an unexpected type", 0) end
            -- Invoke the reflected path predicate, not UE4SS's pointer-validity method.
            fields.pathValid = self:invoke("path-result-valid", functions.IsValid, path)
            fields.partial = self:invoke("path-result-partial", functions.IsPartial, path)
            if type(fields.pathValid) ~= "boolean" or type(fields.partial) ~= "boolean" then
                error("Native probe data has an unexpected type", 0)
            end
            fields.points = a.count(self:field(path, "PathPoints"))
            local length = self:invoke("path-result-length", functions.GetPathLength, path)
            local cost = self:invoke("path-result-cost", functions.GetPathCost, path)
            fields.lengthReadable = finite(length) and length >= 0 and length / 100 <= 4294967295
            fields.costReadable = finite(cost) and cost >= 0 and cost <= 4294967295
            if fields.lengthReadable then fields.lengthMeters = length / 100 end
            if fields.costReadable then fields.cost = cost end
            if fields.pathValid and not fields.partial and fields.points and fields.points >= 2 then
                result.complete = result.complete + 1
            end
        end
        self:record(scope, "path", fields)
    end
    self:record(scope, "path", { queries = result.queries, completePaths = result.complete })
    scope.query_origin, scope.query_points = nil, nil
    return true, result
end

return Observer

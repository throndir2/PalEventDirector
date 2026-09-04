local json = require("ped.json")
local path = require("ped.path")
local filesystem = require("ped.filesystem")
local Ingress = {}
Ingress.__index = Ingress

function Ingress.new(options)
    local fs = options.filesystem or filesystem
    local self = setmetatable({
        fs = fs,
        request = path.join(options.directory, "request.json"),
        claimed = path.join(options.directory, "in-flight.json"),
        response = path.join(options.directory, "response.json"),
        execute = options.execute,
        enqueue = options.enqueue,
        active = true,
        busy = false,
    }, Ingress)
    -- Never replay a request left by a prior process, whether claimed or unclaimed.
    self.blocked = fs.exists(self.request) or fs.exists(self.claimed)
    return self
end

function Ingress:poll()
    if not self.active or self.blocked or self.busy or not self.fs.exists(self.request) then return end
    self.busy = true
    if self.fs.exists(self.claimed) or not self.fs.rename(self.request, self.claimed) then
        self.blocked = true
        return
    end
    local bytes = self.fs.read(self.claimed)
    local ok, request = pcall(json.decode, type(bytes) == "string" and #bytes <= 1024 and bytes or "")
    if not ok or type(request) ~= "table" or request.schemaVersion ~= 1
        or type(request.id) ~= "string" or not request.id:match("^[0-9a-f%-]+$") or #request.id ~= 36
        or type(request.preview) ~= "boolean"
        or (not request.preview and (request.confirmation ~= "confirm-disposable-readonly"
            or type(request.expectedStep) ~= "string" or not request.expectedStep:match("^%d+%-%d+%-[a-z0-9%-]+$"))) then
        self.blocked = true
        return
    end
    local queued, accepted = pcall(self.enqueue, function()
        if not self.active then return end
        local success, result
        local ran = pcall(function()
            if request.preview then success, result = self.execute(nil, nil)
            else success, result = self.execute(request.confirmation, request.expectedStep) end
        end)
        if not ran then success, result = false, "Diagnostic execution failed; raw error suppressed. Preserve the breadcrumb log." end
        if type(result) ~= "string" then result = "Diagnostic returned an invalid result; preserve the breadcrumb log."; success = false end
        local response = json.encode({ schemaVersion = 1, id = request.id, success = success == true, message = result }) .. "\n"
        local temporary = self.response .. ".tmp"
        if not self.fs.write(temporary, response) or not self.fs.remove(self.response)
            or not self.fs.rename(temporary, self.response) or not self.fs.remove(self.claimed) then
            self.blocked = true
            return
        end
        self.busy = false
    end)
    if not queued or accepted == false then self.blocked = true end
end

return Ingress
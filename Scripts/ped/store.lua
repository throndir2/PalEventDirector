local json = require("ped.json")
local default_filesystem = require("ped.filesystem")
local path = require("ped.path")
local util = require("ped.util")

local Store = {}
Store.__index = Store

function Store.new(data_directory, logger, filesystem)
    filesystem = filesystem or default_filesystem
    local ok, directory_error = filesystem.ensure_directory(data_directory)
    if not ok then
        error(directory_error)
    end
    local self = setmetatable({
        directory = data_directory,
        logger = logger,
        filesystem = filesystem,
        snapshot_path = path.join(data_directory, "snapshot.json"),
        journal_path = path.join(data_directory, "journal.ndjson"),
        sequence = 0,
        chain = "00000000",
        records = {},
    }, Store)
    self:_scan_journal()
    return self
end

function Store:_scan_journal()
    local content = self.filesystem.read(self.journal_path)
    if not content then
        return
    end
    local lines = {}
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end
    local last_nonempty = 0
    for index, line in ipairs(lines) do if line ~= "" then last_nonempty = index end end
    local valid_lines = {}
    for line_number, line in ipairs(lines) do
        if line ~= "" then
            local ok, record = pcall(json.decode, line)
            local valid_shape = ok and type(record) == "table" and record.schemaVersion == 1 and util.is_integer(record.sequence)
                and type(record.checksum) == "string" and type(record.kind) == "string" and type(record.previousChecksum) == "string"
            if not valid_shape then
                if line_number == last_nonempty and content:sub(-1) ~= "\n" then
                    local repaired = #valid_lines > 0 and (table.concat(valid_lines, "\n") .. "\n") or ""
                    local repaired_ok, repair_error = self.filesystem.write(self.journal_path, repaired)
                    if not repaired_ok then error("unable to remove torn journal tail: " .. tostring(repair_error)) end
                    if self.logger then self.logger:warn("Removed a torn terminal journal fragment", { line = line_number }) end
                    break
                end
                error("journal is invalid at line " .. line_number)
            end
            local checksum = record.checksum
            record.checksum = nil
            local expected = util.hash32(self.chain .. json.encode(record))
            record.checksum = checksum
            if checksum ~= expected then
                error("journal checksum mismatch at line " .. line_number)
            end
            if record.sequence ~= self.sequence + 1 or record.previousChecksum ~= self.chain then
                error("journal sequence chain mismatch at line " .. line_number)
            end
            self.sequence = record.sequence
            self.chain = checksum
            self.records[#self.records + 1] = record
            valid_lines[#valid_lines + 1] = line
        end
    end
end

function Store:append(kind, data, state)
    local record = {
        schemaVersion = 1,
        sequence = self.sequence + 1,
        timestampUtc = util.utc_now(),
        kind = kind,
        data = data or json.object(),
        previousChecksum = self.chain,
    }
    if state ~= nil then
        if type(state) ~= "table" then
            return false, "journal recovery state must be a table"
        end
        record.state = util.deep_copy(state)
    end
    record.checksum = util.hash32(self.chain .. json.encode(record))
    local ok, write_error = self.filesystem.append(self.journal_path, json.encode(record) .. "\n")
    if not ok then
        return false, write_error
    end
    self.sequence = record.sequence
    self.chain = record.checksum
    self.records[#self.records + 1] = record
    return true, record
end

function Store:save_snapshot(payload)
    local envelope = {
        schemaVersion = 1,
        journalSequence = self.sequence,
        journalChecksum = self.chain,
        savedAtUtc = util.utc_now(),
        payload = payload,
    }
    envelope.checksum = util.hash32(json.encode(envelope.payload))
    local temporary = self.snapshot_path .. ".tmp"
    local backup = self.snapshot_path .. ".bak"
    local ok, write_error = self.filesystem.write(temporary, json.encode(envelope) .. "\n")
    if not ok then
        return false, write_error
    end
    self.filesystem.remove(backup)
    if self.filesystem.exists(self.snapshot_path) then
        local renamed, rename_error = self.filesystem.rename(self.snapshot_path, backup)
        if not renamed then
            self.filesystem.remove(temporary)
            return false, rename_error
        end
    end
    local installed, install_error = self.filesystem.rename(temporary, self.snapshot_path)
    if not installed then
        if self.filesystem.exists(backup) then
            self.filesystem.rename(backup, self.snapshot_path)
        end
        return false, install_error
    end
    return true
end

local function decode_snapshot(filesystem, file_path)
    local text = filesystem.read(file_path)
    if not text then
        return nil, "not found"
    end
    local ok, envelope = pcall(json.decode, text)
    if not ok or type(envelope) ~= "table" or envelope.schemaVersion ~= 1 or type(envelope.payload) ~= "table"
        or not util.is_integer(envelope.journalSequence) or type(envelope.journalChecksum) ~= "string" then
        return nil, "invalid JSON envelope"
    end
    if envelope.checksum ~= util.hash32(json.encode(envelope.payload)) then
        return nil, "checksum mismatch"
    end
    return envelope
end

local function anchor_matches(store, envelope)
    if envelope.journalSequence == store.sequence and envelope.journalChecksum == store.chain then
        return "tail"
    end
    if envelope.journalSequence == 0 then
        return envelope.journalChecksum == "00000000" and "prior" or nil
    end
    local anchor = store.records[envelope.journalSequence]
    if anchor and anchor.sequence == envelope.journalSequence and anchor.checksum == envelope.journalChecksum then
        return "prior"
    end
    return nil
end

local function recover_from_envelope(store, envelope, source)
    local anchor = anchor_matches(store, envelope)
    if anchor == "tail" then
        return envelope.payload, envelope, nil, false
    end
    local tail = store.records[#store.records]
    if anchor == "prior" and tail and tail.sequence == store.sequence and type(tail.state) == "table" then
        if store.logger then
            store.logger:warn("Recovered state from journal tail after an incomplete snapshot checkpoint", {
                snapshotSequence = envelope.journalSequence,
                journalSequence = store.sequence,
                snapshotSource = source,
            })
        end
        return tail.state, envelope, nil, true
    end
    return nil, nil, string.format("%s snapshot is not recoverably anchored to journal tail (snapshot=%s journal=%s)", source, tostring(envelope.journalSequence), tostring(store.sequence))
end

function Store:load_snapshot()
    local envelope, load_error = decode_snapshot(self.filesystem, self.snapshot_path)
    if envelope then
        local payload, metadata, recovery_error, recovered = recover_from_envelope(self, envelope, "primary")
        if payload then return payload, metadata, nil, recovered end
        load_error = recovery_error
    end

    local backup, backup_error = decode_snapshot(self.filesystem, self.snapshot_path .. ".bak")
    if backup then
        local payload, metadata, recovery_error, recovered = recover_from_envelope(self, backup, "backup")
        if payload then
            if self.logger and not recovered then self.logger:warn("Loaded backup snapshot", { primaryError = load_error }) end
            return payload, metadata, nil, recovered
        end
        backup_error = recovery_error
    end

    if self.sequence > 0 then
        local tail = self.records[#self.records]
        if tail and tail.sequence == self.sequence and type(tail.state) == "table" then
            if self.logger then self.logger:warn("Recovered state from journal without a completed snapshot", { journalSequence = self.sequence }) end
            return tail.state, nil, nil, true
        end
        return nil, nil, "journal exists without a snapshot or recoverable state-bearing tail"
    end
    if load_error ~= "not found" or backup_error ~= "not found" then
        return nil, nil, "no valid snapshot: " .. tostring(load_error) .. "; backup: " .. tostring(backup_error)
    end
    return nil
end

return Store

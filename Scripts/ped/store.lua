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
    local line_number = 0
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
        line_number = line_number + 1
        if line ~= "" then
            local ok, record = pcall(json.decode, line)
            if not ok or type(record) ~= "table" or not util.is_integer(record.sequence) or type(record.checksum) ~= "string" then
                error("journal is invalid at line " .. line_number)
            end
            local checksum = record.checksum
            record.checksum = nil
            local expected = util.hash32(self.chain .. json.encode(record))
            record.checksum = checksum
            if checksum ~= expected then
                error("journal checksum mismatch at line " .. line_number)
            end
            self.sequence = record.sequence
            self.chain = checksum
            self.records[#self.records + 1] = record
        end
    end
end

function Store:append(kind, data)
    local record = {
        schemaVersion = 1,
        sequence = self.sequence + 1,
        timestampUtc = util.utc_now(),
        kind = kind,
        data = data or json.object(),
        previousChecksum = self.chain,
    }
    record.checksum = util.hash32(self.chain .. json.encode(record))
    local ok, write_error = self.filesystem.append(self.journal_path, json.encode(record) .. "\n")
    if not ok then
        return false, write_error
    end
    self.sequence = record.sequence
    self.chain = record.checksum
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
    if not ok or type(envelope) ~= "table" or type(envelope.payload) ~= "table" then
        return nil, "invalid JSON envelope"
    end
    if envelope.checksum ~= util.hash32(json.encode(envelope.payload)) then
        return nil, "checksum mismatch"
    end
    return envelope
end

function Store:load_snapshot()
    local envelope, load_error = decode_snapshot(self.filesystem, self.snapshot_path)
    if envelope then
        if envelope.journalSequence ~= self.sequence or envelope.journalChecksum ~= self.chain then
            return nil, nil, string.format("snapshot is not anchored to journal tail (snapshot=%s journal=%s)", tostring(envelope.journalSequence), tostring(self.sequence))
        end
        return envelope.payload, envelope
    end
    local backup, backup_error = decode_snapshot(self.filesystem, self.snapshot_path .. ".bak")
    if backup then
        if backup.journalSequence ~= self.sequence or backup.journalChecksum ~= self.chain then
            backup_error = string.format("not anchored to journal tail (snapshot=%s journal=%s)", tostring(backup.journalSequence), tostring(self.sequence))
        else
            if self.logger then
                self.logger:warn("Loaded backup snapshot", { primaryError = load_error })
            end
            return backup.payload, backup
        end
    end
    if self.sequence > 0 then
        return nil, nil, "journal exists without an exactly anchored snapshot; replay is not available in alpha.1"
    end
    if load_error ~= "not found" or backup_error ~= "not found" then
        return nil, nil, "no valid snapshot: " .. tostring(load_error) .. "; backup: " .. tostring(backup_error)
    end
    return nil
end

return Store

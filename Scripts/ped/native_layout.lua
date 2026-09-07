local Layout = {}

function Layout.fields(owner, maximum, valid, reason)
    local properties = {}
    owner:ForEachProperty(function(field)
        properties[#properties + 1] = field
        if #properties > maximum then return true end
        return nil
    end)
    if #properties > maximum then error(reason, 0) end
    local fields = {}
    for _, field in ipairs(properties) do
        if not valid(field) then error(reason, 0) end
        local name = field:GetFName():ToString()
        if fields[name] then error(reason, 0) end
        fields[name] = { field = field, kind = field:GetClass():GetFName():ToString(), offset = field:GetOffset_Internal() }
    end
    return fields, #properties
end

function Layout.expect(owner, expected, valid, reason)
    local count = 0
    for _ in pairs(expected) do count = count + 1 end
    local fields, actual_count = Layout.fields(owner, count, valid, reason)
    if actual_count ~= count then error(reason, 0) end
    for name, specification in pairs(expected) do
        local field = fields[name]
        if not field or field.kind ~= specification[1] or field.offset ~= specification[2] then error(reason, 0) end
    end
    return fields
end

return Layout

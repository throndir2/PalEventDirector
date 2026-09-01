local failures = 0
for index = 1, #arg do
    local chunk, load_error = loadfile(arg[index])
    if not chunk then
        io.stderr:write(arg[index], ": ", tostring(load_error), "\n")
        failures = failures + 1
    end
end
if failures > 0 then
    os.exit(1)
end

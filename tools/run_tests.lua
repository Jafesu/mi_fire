--- Test runner.
---
--- No dependencies, no framework, works under 5.1 through 5.4. Run from the resource root:
---
---     lua tools/run_tests.lua
---
--- Exits non-zero on failure so it can gate a commit.

local GREEN, RED, DIM, BOLD, RESET = '\27[32m', '\27[31m', '\27[90m', '\27[1m', '\27[0m'
if os.getenv('NO_COLOR') or os.getenv('TERM') == 'dumb' then
    GREEN, RED, DIM, BOLD, RESET = '', '', '', '', ''
end

local t = {}
local passed, failed, currentGroup = 0, 0, nil
local failures = {}

function t.describe(name)
    currentGroup = name
    print(('\n%s%s%s'):format(BOLD, name, RESET))
end

local function record(success, message)
    if success then
        passed = passed + 1
        print(('  %s+%s %s%s%s'):format(GREEN, RESET, DIM, message, RESET))
    else
        failed = failed + 1
        failures[#failures + 1] = ('%s / %s'):format(currentGroup or 'ungrouped', message)
        print(('  %s- %s%s'):format(RED, message, RESET))
    end
end

function t.ok(value, message)
    record(value == true or (value and value ~= false), message)
end

function t.equal(actual, expected, message)
    local success = actual == expected
    if not success then
        message = ('%s %s(got %s, expected %s)%s'):format(
            message, DIM, tostring(actual), tostring(expected), RESET)
    end
    record(success, message)
end

function t.near(actual, expected, tolerance, message)
    local success = type(actual) == 'number' and math.abs(actual - expected) <= tolerance
    if not success then
        message = ('%s %s(got %s, expected %s +/- %s)%s'):format(
            message, DIM, tostring(actual), tostring(expected), tostring(tolerance), RESET)
    end
    record(success, message)
end

-- ---------------------------------------------------------------------------

local specs = {
    'tools/tests/boot_spec.lua',
    'tools/tests/fire_spec.lua',
    'tools/tests/permissions_spec.lua',
    'tools/tests/scba_spec.lua',
    'tools/tests/pass_spec.lua',
    'tools/tests/hydraulics_spec.lua',
    'tools/tests/sprinklers_spec.lua',
}

print(('%smi_fire test suite%s'):format(BOLD, RESET))

for i = 1, #specs do
    local chunk, err = loadfile(specs[i])
    if not chunk then
        failed = failed + 1
        failures[#failures + 1] = ('%s failed to load: %s'):format(specs[i], err)
        print(('%s- could not load %s: %s%s'):format(RED, specs[i], err, RESET))
    else
        local ok, runErr = pcall(chunk(), t)
        if not ok then
            failed = failed + 1
            failures[#failures + 1] = ('%s raised: %s'):format(specs[i], runErr)
            print(('%s- %s raised: %s%s'):format(RED, specs[i], runErr, RESET))
        end
    end
end

print()
if failed == 0 then
    print(('%s%d passed%s'):format(GREEN, passed, RESET))
    os.exit(0)
else
    print(('%s%d passed, %d failed%s'):format(RED, passed, failed, RESET))
    print()
    for i = 1, #failures do
        print(('  %s* %s%s'):format(RED, failures[i], RESET))
    end
    os.exit(1)
end

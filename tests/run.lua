-- tests/run.lua：测试主入口。用法：lua tests/run.lua
package.path = "skills/yeelight-smart-home/scripts/?.lua;skills/yeelight-smart-home/scripts/?/init.lua;tests/?.lua;" .. package.path

local mock = require("tests.mock")
mock.setup_globals()
mock.setup_capability()

local passed = true
local runner = {}

function runner.load(name)
    local file = "tests/" .. name .. ".lua"
    local chunk, err = loadfile(file)
    if not chunk then
        io.stderr:write("LOAD FAIL: " .. tostring(err) .. "\n")
        passed = false
        return
    end
    local ok, run_err = pcall(chunk)
    if not ok then
        io.stderr:write("RUNTIME FAIL in " .. name .. ": " .. tostring(run_err) .. "\n")
        passed = false
    end
end

runner.load("test_util")
runner.load("test_contract")
runner.load("test_name_match")
runner.load("test_risk")
runner.load("test_http")
runner.load("test_topology")
runner.load("test_bind")
runner.load("test_control")
runner.load("test_router")
runner.load("test_catalog_coverage")
runner.load("test_endpoints")
runner.load("test_review2")
runner.load("test_review3")

if not mock.summary() then
    passed = false
end
os.exit(passed and 0 or 1)

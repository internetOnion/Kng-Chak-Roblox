--# selene: allow(incorrect_standard_library_use)
--[[
	Headless test runner: `lune run test` from the repo root.

	Runs every tests/**/*.spec.luau outside Studio. Shared game code expects
	Roblox's globals, so the runner installs the ones Lune provides first (see
	tests/README.md for what's available). Exits with code 1 if any test fails.
	Pass a word to run only spec files whose path contains it: `lune run test Planet`.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local TestKit = require("../tests/TestKit")

-- Roblox globals the shared game code may use. Anything else is missing on purpose.
-- They must be bare globals: modules the runner requires don't see entries set on _G.
task = require("@lune/task")
Vector2 = roblox.Vector2
Vector3 = roblox.Vector3
Color3 = roblox.Color3
CFrame = roblox.CFrame
Enum = roblox.Enum

local filter = process.args[1]

local function findSpecs(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			findSpecs(path, out)
		elseif string.sub(entry, -10) == ".spec.luau" and (not filter or string.find(path, filter, 1, true)) then
			table.insert(out, path)
		end
	end
	return out
end

local specs = findSpecs("tests", {})
table.sort(specs)

local passed, failed = 0, 0
for _, path in specs do
	local loaded, loadError = pcall(require, `../{string.sub(path, 1, -6)}`)
	if not loaded then
		failed += 1
		print(`FAIL  {path} (could not load)\n      {loadError}`)
		continue
	end
	for _, test in TestKit.collect() do
		local ok, err = xpcall(test.fn, function(message)
			return tostring(message)
		end)
		if ok then
			passed += 1
			print(`ok    {test.name}`)
		else
			failed += 1
			print(`FAIL  {test.name}\n      {err}`)
		end
	end
end

print(`\n{passed} passed, {failed} failed`)
if #specs == 0 then
	print("No spec files found.")
	process.exit(1)
end
process.exit(if failed > 0 then 1 else 0)

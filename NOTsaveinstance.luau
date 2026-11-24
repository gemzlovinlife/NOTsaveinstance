--!native
--!optimize 2
-- https://discord.gg/wx4ThpAsmw
-- Standalone rebuild of UniversalSynSaveInstance. No SomeHub / USSI dependency.
--
-- Usage:
--   local saveinstance = ... (this script returns the function)
--   saveinstance()                        -- full save with default options
--   saveinstance({ noscripts = true })    -- place file, no decompiling
--   saveinstance({ Object = workspace.Foo, IsModel = true })  -- .rbxmx model
--   saveinstance({ SafeMode = true, timeout = 15, SaveBytecode = true })

local service = setmetatable({}, {
	__index = function(self, index)
		local Service = game:GetService(index) or settings():GetService(index) or UserSettings():GetService(index)
		self[index] = Service
		return Service
	end,
})

local function string_find(s, pattern)
	return string.find(s, pattern, nil, true)
end

local function ArrayToDictionary(t, hydridMode, valueOverride)
	local tmp = {}

	if hydridMode then
		for some1, some2 in t do
			if type(some1) == "number" then
				tmp[some2] = valueOverride or true
			elseif type(some2) == "table" then
				tmp[some1] = ArrayToDictionary(some2, hydridMode) -- Some1 is Class, Some2 is Name
			else
				tmp[some1] = some2
			end
		end
	else
		for _, key in t do
			if type(key) == "string" then
				tmp[key] = true
			end
		end
	end

	return tmp
end

local ESCAPES_PATTERN = "[&<>\"'\0\1-\9\11-\12\14-\31\127-\255]"
local ESCAPES = {
	["&"] = "&amp;",
	["<"] = "&lt;",
	[">"] = "&gt;",
	['"'] = "&#34;",
	["'"] = "&#39;",
	["\0"] = "",
}

for rangeStart, rangeEnd in string.gmatch(ESCAPES_PATTERN, "(.)%-(.)") do
	for charCode = string.byte(rangeStart), string.byte(rangeEnd) do
		ESCAPES[string.char(charCode)] = "&#" .. charCode .. ";"
	end
end

--[=[ Inline method finder (replaces SomeHub's UniversalMethodFinder) ]=]
local global_container
do
	local KNOWN_NAMES = {
		base64encode = { "base64encode", "base64_encode", "base64enc", "encodebase64", "tobase64", "base64" },
		decompile = { "decompile", "decompilefunction", "decompilestring" },
		gethiddenproperty = { "gethiddenproperty", "get_hidden_property" },
		gethui = { "gethui", "get_hui", "gethuigui" },
		getnilinstances = { "getnilinstances", "get_nil_instances" },
		getscriptbytecode = { "getscriptbytecode", "get_script_bytecode", "dumpstring" },
		hash = { "hash", "hashstring", "crypt_hash" },
		protectgui = { "protectgui", "protect_gui" },
		readfile = { "readfile", "read_file" },
		writefile = { "writefile", "write_file" },
		setthreadidentity = { "setthreadidentity", "setthreadidentitylevel", "setidentity", "setthreadcontext" },
	}

	local function find(s, p)
		return string.find(s, p, 1, true)
	end

	local PATTERN_CHECKS = {
		base64encode = function(n)
			return (find(n, "base64") and (find(n, "enc") or find(n, "encode"))) or (find(n, "crypt") and find(n, "encode"))
		end,
		decompile = function(n)
			return (find(n, "decomp") and string.sub(n, -1) ~= "s") or find(n, "assembl")
		end,
		gethiddenproperty = function(n)
			return find(n, "get") and find(n, "h") and find(n, "prop") and string.sub(n, -1) ~= "s"
		end,
		gethui = function(n)
			return find(n, "get") and find(n, "h") and find(n, "ui")
		end,
		getnilinstances = function(n)
			return find(n, "nil") and find(n, "get") and string.sub(n, -1) == "s"
		end,
		getscriptbytecode = function(n)
			return find(n, "get") and find(n, "bytecode")
		end,
		hash = function(n)
			return find(n, "hash") and find(n, "crypt")
		end,
		protectgui = function(n)
			return find(n, "protect") and find(n, "ui") and not find(n, "un")
		end,
		readfile = function(n)
			return find(n, "file") and find(n, "read")
		end,
		writefile = function(n)
			return find(n, "file") and find(n, "write")
		end,
		setthreadidentity = function(n)
			return find(n, "identity") and find(n, "set")
		end,
	}

	local matched = {}
	local visited = {}

	local function tryKnown(lowered, value)
		for target, names in KNOWN_NAMES do
			if not matched[target] then
				for _, known in names do
					if lowered == known then
						matched[target] = value
						return true
					end
				end
			end
		end
		return false
	end

	local function scan(env, depth)
		if visited[env] then
			return
		end
		visited[env] = true

		for name, value in next, env do
			local kind = type(value)
			if kind == "function" then
				local nameStr = tostring(name)
				local lowered = string.lower(nameStr)
				if not tryKnown(lowered, value) then
					for target, check in PATTERN_CHECKS do
						if not matched[target] and check(lowered) then
							matched[target] = value
							break
						end
					end
				end
			elseif kind == "table" and depth < 2 then
				pcall(scan, value, depth + 1)
			end
		end
	end

	local envs = {}
	do
		local function addEnv(getter)
			local ok, env = pcall(getter)
			if ok and type(env) == "table" then
				table.insert(envs, env)
			end
		end
		if getgenv then
			addEnv(getgenv)
		end
		if getrenv then
			addEnv(getrenv)
		end
		table.insert(envs, _G)
		table.insert(envs, shared)
	end

	for _, env in envs do
		pcall(scan, env, 0)
	end

	global_container = setmetatable(matched, {
		__index = function(self, key)
			local ok, env = pcall(getgenv)
			local value
			if ok and type(env) == "table" then
				value = env[key]
			end
			if value == nil and type(_G) == "table" then
				value = _G[key]
			end
			if value ~= nil then
				self[key] = value
			end
			return value
		end,
	})
end

local identify_executor = identifyexecutor or getexecutorname or whatexecutor

local EXECUTOR_NAME = "Unknown"
if identify_executor then
	local ok, name = pcall(identify_executor)
	if ok and type(name) == "string" then
		EXECUTOR_NAME = name
	end
end

local gethiddenproperty = global_container.gethiddenproperty
local readfile = global_container.readfile
local writefile = global_container.writefile

local getscriptbytecode = global_container.getscriptbytecode
local base64encode = global_container.base64encode

if not base64encode then
	local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

	base64encode = function(raw)
		raw = tostring(raw)
		local len = #raw
		if len == 0 then
			return ""
		end

		local out = table.create(math.ceil(len / 3) * 4)
		local n = 0
		local i = 1

		while i <= len do
			local b1 = string.byte(raw, i)
			local b2 = string.byte(raw, i + 1)
			local b3 = string.byte(raw, i + 2)

			local chunk = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)

			local c1 = math.floor(chunk / 262144) % 64
			local c2 = math.floor(chunk / 4096) % 64
			local c3 = math.floor(chunk / 64) % 64
			local c4 = chunk % 64

			n += 1
			out[n] = string.sub(B64_CHARS, c1 + 1, c1 + 1)
			n += 1
			out[n] = string.sub(B64_CHARS, c2 + 1, c2 + 1)
			n += 1
			out[n] = b2 and string.sub(B64_CHARS, c3 + 1, c3 + 1) or "="
			n += 1
			out[n] = b3 and string.sub(B64_CHARS, c4 + 1, c4 + 1) or "="

			i += 3
		end

		return table.concat(out)
	end
end

--[=[ sha384 replacement: executor hash if present, otherwise a cheap local digest (cache keys only) ]=]
local sha384
do
	local hash = global_container.hash
	local HEX = "0123456789abcdef"

	local function toHex(n)
		local out = table.create(8)
		for i = 7, 0, -1 do
			local nib = math.floor(n / (2 ^ (i * 4))) % 16
			out[8 - i] = string.sub(HEX, nib + 1, nib + 1)
		end
		return table.concat(out)
	end

	local function cheapDigest(data)
		if not bit32 then
			return data
		end

		local band, bxor = bit32.band, bit32.bxor
		local h1, h2, h3, h4 = 0x811c9dc5, 0x01000193, 0x9e3779b9, 0x85ebca6b

		for i = 1, #data do
			local b = string.byte(data, i)
			h1 = band(bxor(h1, b) * 31 + b, 0xFFFFFFFF)
			h2 = band(bxor(h2, h1) * 131 + b, 0xFFFFFFFF)
			h3 = band(bxor(h3, h2) * 65599 + b, 0xFFFFFFFF)
			h4 = band(bxor(h4, h3) * 7 + b, 0xFFFFFFFF)
		end

		return toHex(h1) .. toHex(h2) .. toHex(h3) .. toHex(h4) .. toHex(#data % 0xFFFFFFFF)
	end

	sha384 = function(data)
		if hash then
			local ok, result = pcall(hash, data, "sha384")
			if ok and type(result) == "string" and result ~= "" then
				return result
			end
		end
		return cheapDigest(data)
	end
end

local custom_decompiler, load_decompiler

if getscriptbytecode then
	local decompiler_source

	if
		pcall(function()
			decompiler_source =
				game:HttpGet("https://raw.githubusercontent.com/w-a-e/Advanced-Decompiler-V3/main/init.lua", true)
		end)
		and decompiler_source
	then
		load_decompiler = function(decompTimeout)
			local CONSTANTS = [[
	local ENABLED_REMARKS = {
		NATIVE_REMARK = true,
		INLINE_REMARK = true
	}
	local DECOMPILER_TIMEOUT = ]] .. decompTimeout .. [[
		
	local READER_FLOAT_PRECISION = 7
	local SHOW_INSTRUCTION_LINES = false
	local SHOW_REFERENCES = true
	local SHOW_OPERATION_NAMES = false
	local SHOW_MISC_OPERATIONS = false
	local LIST_USED_GLOBALS = true
	local RETURN_ELAPSED_TIME = false
	]]
			local _ENV = (getgenv or getrenv or getfenv)()
			local old = _ENV.decompile

			local f = loadstring(
				string.gsub(
					string.gsub(
						decompiler_source,
						"return %(x %% 2^32%) // %(2^disp%)",
						"return math.floor((x %% 2^32) / (2^disp))",
						1
					),
					";;CONSTANTS HERE;;",
					CONSTANTS
				),
				"Advanced-Decompiler-V3"
			)
			if not f then
				return
			end
			f()
			custom_decompiler = _ENV.decompile
			_ENV.decompile = old
		end
	end
end

local SharedStrings = {}
local SharedString_identifiers = setmetatable({
	identifier = 1e15,
}, {
	__index = function(self, str)
		local Identifier = base64encode(tostring(self.identifier))
		self.identifier += 1

		self[str] = Identifier
		return Identifier
	end,
})

local Type_IDs = {
	string = 0x02,
	boolean = 0x03,
	number = 0x06,
	UDim = 0x09,
	UDim2 = 0x0A,
	BrickColor = 0x0E,
	Color3 = 0x0F,
	Vector2 = 0x10,
	Vector3 = 0x11,
	CFrame = 0x14,
	EnumItem = 0x15,
	NumberSequence = 0x17,
	ColorSequence = 0x19,
	NumberRange = 0x1B,
	Rect = 0x1C,
	Font = 0x21,
}
local CFrame_Rotation_IDs = {
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x02,
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x03,
	["\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x05,
	["\0\0\128\63\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x06,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x07,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x09,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x0a,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x0c,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x0d,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x0e,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\63\0\0\0\0\0\0\0\0"] = 0x10,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\128"] = 0x11,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x14,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\128"] = 0x15,
	["\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x17,
	["\0\0\128\191\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\191\0\0\0\128"] = 0x18,
	["\0\0\0\0\0\0\128\63\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63"] = 0x19,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0"] = 0x1b,
	["\0\0\0\0\0\0\128\191\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\128\0\0\0\0\0\0\0\0\0\0\128\191"] = 0x1c,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0"] = 0x1e,
	["\0\0\0\0\0\0\128\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\191\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x1f,
	["\0\0\0\0\0\0\0\0\0\0\128\63\0\0\0\0\0\0\128\63\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x20,
	["\0\0\0\0\0\0\128\191\0\0\0\0\0\0\0\0\0\0\0\0\0\0\128\63\0\0\128\191\0\0\0\0\0\0\0\0"] = 0x22,
	["\0\0\0\0\0\0\0\0\0\0\128\191\0\0\0\0\0\0\128\191\0\0\0\128\0\0\128\191\0\0\0\0\0\0\0\128"] = 0x23,
}
local Binary_Descriptors
Binary_Descriptors = {
	__SEQUENCE = function(raw, valueFormatter, keypointSize, Envelope)
		local Keypoints = raw.Keypoints
		local Keypoints_n = #Keypoints

		local len = 4 + (keypointSize or 12) * Keypoints_n
		local b = buffer.create(len)
		local offset = 0

		buffer.writeu32(b, offset, Keypoints_n)
		offset += 4

		for _, keypoint in Keypoints do
			buffer.writef32(b, offset, Envelope or keypoint.Envelope)
			offset += 4
			buffer.writef32(b, offset, keypoint.Time)
			offset += 4

			local Value = keypoint.Value
			if valueFormatter then
				offset += valueFormatter(Value, b, offset)
			else
				buffer.writef32(b, offset, Value)
				offset += 4
			end
		end

		return b, len
	end,
	["string"] = function(raw)
		local raw_len = #raw
		local len = 4 + raw_len

		local b = buffer.create(len)

		buffer.writeu32(b, 0, raw_len)
		buffer.writestring(b, 4, raw)

		return b, len
	end,
	["boolean"] = function(raw)
		local b = buffer.create(1)

		buffer.writeu8(b, 0, raw and 1 or 0)

		return b, 1
	end,
	["number"] = function(raw)
		local b = buffer.create(8)

		buffer.writef64(b, 0, raw)

		return b, 8
	end,
	["UDim"] = function(raw)
		local b = buffer.create(8)

		buffer.writef32(b, 0, raw.Scale)
		buffer.writei32(b, 4, raw.Offset)

		return b, 8
	end,
	["UDim2"] = function(raw)
		local b = buffer.create(16)

		local Descriptors_UDim = Binary_Descriptors.UDim
		local X = Descriptors_UDim(raw.X)
		buffer.copy(b, 0, X)
		local Y = Descriptors_UDim(raw.Y)
		buffer.copy(b, 8, Y)

		return b, 16
	end,
	["BrickColor"] = function(raw)
		local b = buffer.create(4)

		buffer.writeu32(b, 0, raw.Number)

		return b, 4
	end,
	["Color3"] = function(raw)
		local b = buffer.create(12)

		buffer.writef32(b, 0, raw.R)
		buffer.writef32(b, 4, raw.G)
		buffer.writef32(b, 8, raw.B)

		return b, 12
	end,
	["Vector2"] = function(raw)
		local b = buffer.create(8)

		buffer.writef32(b, 0, raw.X)
		buffer.writef32(b, 4, raw.Y)

		return b, 8
	end,
	["Vector3"] = function(raw)
		local b = buffer.create(12)

		buffer.writef32(b, 0, raw.X)
		buffer.writef32(b, 4, raw.Y)
		buffer.writef32(b, 8, raw.Z)

		return b, 12
	end,
	["CFrame"] = function(raw)
		local X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = raw:GetComponents()

		local rotation_ID = CFrame_Rotation_IDs[string.pack("<fffffffff", R00, R01, R02, R10, R11, R12, R20, R21, R22)]

		local len = rotation_ID and 13 or 49
		local b = buffer.create(len)

		buffer.writef32(b, 0, X)
		buffer.writef32(b, 4, Y)
		buffer.writef32(b, 8, Z)

		if rotation_ID then
			buffer.writeu8(b, 12, rotation_ID)
		else
			buffer.writeu8(b, 12, 0x0)

			buffer.writef32(b, 13, R00)
			buffer.writef32(b, 17, R01)
			buffer.writef32(b, 21, R02)

			buffer.writef32(b, 25, R10)
			buffer.writef32(b, 29, R11)
			buffer.writef32(b, 33, R12)

			buffer.writef32(b, 37, R20)
			buffer.writef32(b, 41, R21)
			buffer.writef32(b, 45, R22)
		end

		return b, len
	end,
	["EnumItem"] = function(raw)
		local b_Name, Name_size = Binary_Descriptors.string(tostring(raw.EnumType))

		local len = Name_size + 4
		local b = buffer.create(len)

		buffer.copy(b, 0, b_Name)
		buffer.writeu32(b, Name_size, raw.Value)

		return b, len
	end,
	["NumberSequence"] = nil,
	["ColorSequence"] = function(raw)
		return Binary_Descriptors.__SEQUENCE(raw, function(color3, b, offset)
			buffer.copy(b, offset, Binary_Descriptors.Color3(color3))
			return 12
		end, 20, 0)
	end,
	["NumberRange"] = function(raw)
		local b = buffer.create(8)

		buffer.writef32(b, 0, raw.Min)
		buffer.writef32(b, 4, raw.Max)

		return b, 8
	end,
	["Rect"] = function(raw)
		local b = buffer.create(16)

		local Descriptors_Vector2 = Binary_Descriptors.Vector2
		local Min = Descriptors_Vector2(raw.Min)
		buffer.copy(b, 0, Min)
		local Max = Descriptors_Vector2(raw.Max)
		buffer.copy(b, 8, Max)

		return b, 16
	end,
	["Font"] = function(raw)
		local Descriptors_string = Binary_Descriptors.string

		local b_Family, Family_size = Descriptors_string(raw.Family)
		local b_CachedFaceId, CachedFaceId_size = Descriptors_string("")

		local len = 3 + Family_size + CachedFaceId_size
		local b = buffer.create(len)

		buffer.writeu16(b, 0, raw.Weight.Value)
		buffer.writeu8(b, 2, raw.Style.Value)

		buffer.copy(b, 3, b_Family)
		buffer.copy(b, 3 + Family_size, b_CachedFaceId)

		return b, len
	end,
}
do
	Binary_Descriptors.NumberSequence = Binary_Descriptors.__SEQUENCE
end

local XML_Descriptors
XML_Descriptors = {
	__APIPRECISION = function(raw, precision)
		if raw == 0 or raw % 1 == 0 then
			return raw
		end

		local Extreme = XML_Descriptors.__EXTREME(raw)
		if Extreme then
			return Extreme
		end

		return string.format("%." .. precision .. "f", raw)
	end,
	__BIT = function(...)
		local Value = 0

		for i, bit in { ... } do
			if bit then
				Value += 2 ^ (i - 1)
			end
		end

		return Value
	end,
	__CDATA = function(raw)
		return "<![CDATA[" .. raw .. "]]>"
	end,
	__ENUM = function(raw)
		return raw.Value, "token"
	end,
	__EXTREME = function(raw)
		local Extreme
		if raw ~= raw then
			Extreme = "NAN"
		elseif raw == math.huge then
			Extreme = "INF"
		elseif raw == -math.huge then
			Extreme = "-INF"
		end

		return Extreme
	end,
	__EXTREME_RANGE = function(raw)
		return raw ~= raw and "0" or raw
	end,
	__MINMAX = function(min, max, descriptor)
		return "<min>" .. descriptor(min) .. "</min><max>" .. descriptor(max) .. "</max>"
	end,
	__PROTECTEDSTRING = function(raw)
		return string_find(raw, "]]>") and string.gsub(raw, ESCAPES_PATTERN, ESCAPES) or XML_Descriptors.__CDATA(raw)
	end,
	__SEQUENCE = function(raw, valueFormatter)
		local __EXTREME_RANGE = XML_Descriptors.__EXTREME_RANGE

		local Converted = ""

		for _, keypoint in raw.Keypoints do
			local Value = keypoint.Value

			Converted ..= keypoint.Time .. " " .. (valueFormatter and valueFormatter(Value) or __EXTREME_RANGE(Value) .. " " .. __EXTREME_RANGE(
				keypoint.Envelope
			) .. " ")
		end

		return Converted
	end,
	__VECTOR = function(X, Y, Z)
		local Value = "<X>" .. X .. "</X><Y>" .. Y .. "</Y>"

		if Z then
			Value ..= "<Z>" .. Z .. "</Z>"
		end

		return Value
	end,
	Axes = function(raw)
		return "<axes>" .. XML_Descriptors.__BIT(raw.X, raw.Y, raw.Z) .. "</axes>"
	end,

	BinaryString = EXECUTOR_NAME == "Electron" and function(raw)
		return raw
	end or base64encode,

	BrickColor = function(raw)
		return raw.Number
	end,
	CFrame = function(raw)
		local X, Y, Z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = raw:GetComponents()
		return XML_Descriptors.__VECTOR(X, Y, Z)
			.. "<R00>"
			.. R00
			.. "</R00><R01>"
			.. R01
			.. "</R01><R02>"
			.. R02
			.. "</R02><R10>"
			.. R10
			.. "</R10><R11>"
			.. R11
			.. "</R11><R12>"
			.. R12
			.. "</R12><R20>"
			.. R20
			.. "</R20><R21>"
			.. R21
			.. "</R21><R22>"
			.. R22
			.. "</R22>",
			"CoordinateFrame"
	end,
	Color3 = function(raw)
		return "<R>" .. raw.R .. "</R><G>" .. raw.G .. "</G><B>" .. raw.B .. "</B>"
	end,
	Color3uint8 = function(raw)
		return 0xFF000000
			+ (math.floor(raw.R * 255) * 0x10000)
			+ (math.floor(raw.G * 255) * 0x100)
			+ math.floor(raw.B * 255)
	end,
	ColorSequence = function(raw)
		return XML_Descriptors.__SEQUENCE(raw, function(color3)
			local __EXTREME_RANGE = XML_Descriptors.__EXTREME_RANGE

			return __EXTREME_RANGE(color3.R)
				.. " "
				.. __EXTREME_RANGE(color3.G)
				.. " "
				.. __EXTREME_RANGE(color3.B)
				.. " 0 "
		end)
	end,
	Content = function(raw)
		return raw == "" and "<null></null>" or "<url>" .. XML_Descriptors.string(raw, true) .. "</url>"
	end,
	CoordinateFrame = function(raw)
		return "<CFrame>" .. XML_Descriptors.CFrame(raw) .. "</CFrame>"
	end,
	Faces = function(raw)
		return "<faces>"
			.. XML_Descriptors.__BIT(raw.Right, raw.Top, raw.Back, raw.Left, raw.Bottom, raw.Front)
			.. "</faces>"
	end,
	Font = function(raw)
		local FontString = tostring(raw)

		local EmptyWeight = string_find(FontString, "Weight = ,")
		local EmptyStyle = string_find(FontString, "Style =  }")

		return "<Family>"
			.. XML_Descriptors.Content(raw.Family)
			.. "</Family><Weight>"
			.. (EmptyWeight and "" or XML_Descriptors.__ENUM(raw.Weight))
			.. "</Weight><Style>"
			.. (EmptyStyle and "" or raw.Style.Name)
			.. "</Style>"
	end,
	NumberRange = function(raw)
		local __EXTREME_RANGE = XML_Descriptors.__EXTREME_RANGE

		return __EXTREME_RANGE(raw.Min) .. " " .. __EXTREME_RANGE(raw.Max)
	end,
	NumberSequence = nil,
	PhysicalProperties = function(raw)
		local CustomPhysics
		if raw then
			CustomPhysics = true
		else
			CustomPhysics = false
		end
		CustomPhysics = "<CustomPhysics>" .. XML_Descriptors.bool(CustomPhysics) .. "</CustomPhysics>"

		return raw
				and CustomPhysics .. "<Density>" .. raw.Density .. "</Density><Friction>" .. raw.Friction .. "</Friction><Elasticity>" .. raw.Elasticity .. "</Elasticity><FrictionWeight>" .. raw.FrictionWeight .. "</FrictionWeight><ElasticityWeight>" .. raw.ElasticityWeight .. "</ElasticityWeight>"
			or CustomPhysics
	end,
	Ray = function(raw)
		local vector3 = XML_Descriptors.Vector3

		return "<origin>" .. vector3(raw.Origin) .. "</origin><direction>" .. vector3(raw.Direction) .. "</direction>"
	end,
	Rect = function(raw)
		return XML_Descriptors.__MINMAX(raw.Min, raw.Max, XML_Descriptors.Vector2), "Rect2D"
	end,
	Region3 = function(raw)
		local Translation = raw.CFrame.Position
		local HalfSize = raw.Size * 0.5

		return XML_Descriptors.__MINMAX(Translation - HalfSize, Translation + HalfSize, XML_Descriptors.Vector3)
	end,
	Region3int16 = function(raw)
		return XML_Descriptors.__MINMAX(raw.Min, raw.Max, XML_Descriptors.Vector3int16)
	end,
	SharedString = function(raw)
		raw = base64encode(raw)

		local Identifier = SharedString_identifiers[raw]

		if SharedStrings[Identifier] == nil then
			SharedStrings[Identifier] = raw
		end

		return Identifier
	end,
	UDim = function(raw)
		return "<S>" .. raw.Scale .. "</S><O>" .. raw.Offset .. "</O>"
	end,
	UDim2 = function(raw)
		local X, Y = raw.X, raw.Y

		return "<XS>"
			.. X.Scale
			.. "</XS><XO>"
			.. X.Offset
			.. "</XO><YS>"
			.. Y.Scale
			.. "</YS><YO>"
			.. Y.Offset
			.. "</YO>"
	end,
	Vector2 = function(raw)
		return XML_Descriptors.__VECTOR(raw.X, raw.Y)
	end,
	Vector2int16 = nil,
	Vector3 = function(raw)
		return XML_Descriptors.__VECTOR(raw.X, raw.Y, raw.Z)
	end,
	Vector3int16 = nil,
	bool = function(raw)
		return raw and "true" or "false"
	end,
	double = function(raw)
		return XML_Descriptors.__APIPRECISION(raw, 17)
	end,
	float = function(raw)
		return XML_Descriptors.__APIPRECISION(raw, 9)
	end,
	int = function(raw)
		return XML_Descriptors.__EXTREME(raw) or raw
	end,
	int64 = nil,
	string = function(raw, skipEmptyCheck)
		return not skipEmptyCheck and raw == "" and raw
			or string_find(raw, "]]>") and string.gsub(raw, ESCAPES_PATTERN, ESCAPES)
			or XML_Descriptors.__CDATA(string.gsub(raw, "\0", ""))
	end,
}
for descriptorName, redirectName in
	{
		NumberSequence = "__SEQUENCE",
		Vector2int16 = "Vector2",
		Vector3int16 = "Vector3",
		int64 = "int",
	}
do
	XML_Descriptors[descriptorName] = XML_Descriptors[redirectName]
end

local ClassList

do
	local ClassPropertyExceptions = { TriangleMeshPart = ArrayToDictionary({ "CollisionFidelity" }) }

	local function FetchAPI()
		local API_Dump
		local VERSIONS = "versionQTStudio"

		pcall(function()
			VERSIONS = version()
		end)

		do -- cache
			if readfile then
				local ok, cached = pcall(readfile, VERSIONS)
				if ok and cached and cached ~= "" and string.sub(cached, 1, 1) == "{" then
					API_Dump = cached
				end
			end
		end

		if not API_Dump then -- official CDN, matched to this exact client build
			for _, url in
				{
					"https://setup.rbxcdn.com/" .. VERSIONS .. "-Full-API-Dump.json",
					"https://setup.rbxcdn.com/versionQTStudio-Full-API-Dump.json",
				}
			do
				local ok, result = pcall(game.HttpGet, game, url, true)
				if ok and type(result) == "string" and string.sub(result, 1, 1) == "{" then
					API_Dump = result
					break
				end
			end
		end

		if not API_Dump then -- GitHub tracker fallbacks
			warn("Failed to get " .. VERSIONS .. " API Dump, trying tracker..")
			local ok, result = pcall(function()
				local latest_commit = service.HttpService:JSONDecode(
					game:HttpGet(
						"https://api.github.com/search/commits?sort=committer-date&order=desc&q=repo:MaximumADHD/Roblox-Client-Tracker+0."
							.. (string.split(VERSIONS, ".")[2] or ""),
						true
					)
				).items[1]
				return game:HttpGet(
					"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/"
						.. latest_commit.sha
						.. "/Mini-API-Dump.json",
					true
				)
			end)
			if ok and result then
				API_Dump = result
			end
		end

		if not API_Dump then
			local ok, result = pcall(game.HttpGet, game,
				"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Mini-API-Dump.json", true)
			if ok then
				API_Dump = result
			end
		end

		if not API_Dump then
			error("Could not fetch an API Dump")
		end

		if writefile then
			pcall(writefile, VERSIONS, API_Dump)
		end

		local classList = {}

		for _, API_Class in service.HttpService:JSONDecode(API_Dump).Classes do
			local ClassProperties, ClassProperties_size = {}, 1
			local Class = {
				Properties = ClassProperties,
				Superclass = API_Class.Superclass,
			}

			local ClassTags = API_Class.Tags
			local ClassName = API_Class.Name

			if ClassTags then
				Class.Tags = ArrayToDictionary(ClassTags)
			end

			local ClassExceptions = ClassPropertyExceptions[ClassName]

			for _, Member in API_Class.Members do
				if Member.MemberType == "Property" then
					local Serialization = Member.Serialization

					if Serialization.CanLoad then
						local PropertyName = Member.Name
						if Serialization.CanSave or ClassExceptions and ClassExceptions[PropertyName] then
							local MemberTags = Member.Tags

							local ValueType = Member.ValueType

							local Special

							if MemberTags then
								MemberTags = ArrayToDictionary(MemberTags)

								Special = MemberTags.NotScriptable
							end

							ClassProperties[ClassProperties_size] = {
								Name = PropertyName,
								Category = ValueType.Category,
								ValueType = ValueType.Name,

								Special = Special,

								CanRead = nil,
							}
							ClassProperties_size += 1
						end
					end
				end
			end

			classList[ClassName] = Class
		end

		return classList
	end

	local ok, result = pcall(FetchAPI)
	if ok then
		ClassList = result
	else
		warn("Failed to load the API Dump")
		warn(result)
		return
	end
end

local inherited_properties = {}
local default_instances = {}
local referents, ref_size = {}, 0

local GLOBAL_ENV = getgenv and getgenv() or _G or shared

local function synsaveinstance(CustomOptions, CustomOptions2)
	do
		local setthreadidentity = global_container.setthreadidentity
		if setthreadidentity then
			pcall(setthreadidentity, 8)
		end
	end

	local totalstr, totalsize = "", 0
	local savebuffer, savebuffer_size = { '<roblox version="4">' }, 2

	local StatusText

	local OPTIONS = {
		mode = "optimized",
		noscripts = false,
		scriptcache = true,
		decomptype = "",
		timeout = 10,
		__DEBUG_MODE = false,

		DecompileJobless = false,
		DecompileIgnore = {
			service.Chat,
			service.TextChatService,
			ModuleScript = nil,
		},
		SaveBytecode = false,

		IgnoreProperties = { "ScriptGuid", "UniqueId", "HistoryId" },

		IgnoreList = { service.CoreGui, service.CorePackages },

		ExtraInstances = {},
		NilInstances = false,
		NilInstancesFixes = {},

		SaveCacheInterval = 0x1600 * 10,
		ShowStatus = true,
		SafeMode = false,
		Anonymous = false,
		ReadMe = true,
		FilePath = false,
		Object = false,
		IsModel = false,

		IgnoreDefaultProperties = true,
		IgnoreNotArchivable = true,
		IgnorePropertiesOfNotScriptsOnScriptsMode = false,
		IgnoreSpecialProperties = false,

		IsolateLocalPlayer = false,
		IsolateLocalPlayerCharacter = false,
		IsolatePlayers = false,
		IsolateStarterPlayer = false,
		RemovePlayerCharacters = true,

		SaveNonCreatable = false,
		NotCreatableFixes = { "Player", "PlayerScripts", "PlayerGui", "TouchTransmitter" },

		IgnoreSharedStrings = true,
		SharedStringOverwrite = false,
		TreatUnionsAsParts = EXECUTOR_NAME == "Solara",

		OptionsAliases = {
			FilePath = "FileName",
			IgnoreDefaultProperties = "IgnoreDefaultProps",
			SaveNonCreatable = "SaveNotCreatable",
			IsolatePlayers = "SavePlayers",
			scriptcache = "DecompileJobless",
			timeout = "DecompileTimeout",
			IgnoreNotArchivable = "IgnoreArchivable",
		},

		NotScriptableFixes = {
			Instance = {
				AttributesSerialize = function(instance)
					local attrs = instance:GetAttributes()

					local attrs_n = 0
					local buffer_size = 4
					local attrs_sorted = {}
					local attrs_formatted = table.clone(attrs)

					for attr, val in attrs do
						attrs_n += 1
						attrs_sorted[attrs_n] = attr

						local Type = typeof(val)

						local Descriptor = Binary_Descriptors[Type]
						local attr_size

						attrs_formatted[attr], attr_size = Descriptor(val)

						buffer_size += 5 + #attr + attr_size
					end

					if attrs_n == 0 then
						return ""
					end
					table.sort(attrs_sorted)

					local b = buffer.create(buffer_size)

					local offset = 0

					buffer.writeu32(b, offset, attrs_n)
					offset += 4

					local Descriptors_string = Binary_Descriptors.string
					for _, attr in attrs_sorted do
						local b_Name, Name_size = Descriptors_string(attr)

						buffer.copy(b, offset, b_Name)
						offset += Name_size

						buffer.writeu8(b, offset, Type_IDs[typeof(attrs[attr])])
						offset += 1

						local bb = attrs_formatted[attr]

						buffer.copy(b, offset, bb)
						offset += buffer.len(bb)
					end

					return buffer.tostring(b)
				end,
				Tags = function(instance)
					local tags = instance:GetTags()

					if #tags == 0 then
						return ""
					end

					return table.concat(tags, "\0")
				end,
				_Inheritors = {
					BallSocketConstraint = { MaxFrictionTorqueXml = "MaxFrictionTorque" },
					BasePart = {
						Color3uint8 = "Color",
						MaterialVariantSerialized = "MaterialVariant",
						size = "Size",
						_Inheritors = {
							Terrain = {
								AcquisitionMethod = "LastUsedModificationMethod",
								MaterialColors = function(instance)
									local TERRAIN_MATERIAL_COLORS = {
										Enum.Material.Grass,
										Enum.Material.Slate,
										Enum.Material.Concrete,
										Enum.Material.Brick,
										Enum.Material.Sand,
										Enum.Material.WoodPlanks,
										Enum.Material.Rock,
										Enum.Material.Glacier,
										Enum.Material.Snow,
										Enum.Material.Sandstone,
										Enum.Material.Mud,
										Enum.Material.Basalt,
										Enum.Material.Ground,
										Enum.Material.CrackedLava,
										Enum.Material.Asphalt,
										Enum.Material.Cobblestone,
										Enum.Material.Ice,
										Enum.Material.LeafyGrass,
										Enum.Material.Salt,
										Enum.Material.Limestone,
										Enum.Material.Pavement,
									}

									local b = buffer.create(69)
									local offset = 6

									local RGB_components = { "R", "G", "B" }

									for _, material in TERRAIN_MATERIAL_COLORS do
										local color = instance:GetMaterialColor(material)
										for _, component in RGB_components do
											buffer.writeu8(b, offset, math.floor(color[component] * 255))
											offset += 1
										end
									end

									return buffer.tostring(b)
								end,
							},
							TriangleMeshPart = {
								FluidFidelityInternal = "FluidFidelity",
								_Inheritors = {
									MeshPart = { InitialSize = "MeshSize" },
									PartOperation = { InitialSize = "MeshSize" },
								},
							},
							TrussPart = { style = "Style" },
							FormFactorPart = {
								formFactorRaw = "FormFactor",
								_Inheritors = { Part = { shape = "Shape" } },
							},
						},
					},

					DoubleConstrainedValue = { value = "Value" },
					IntConstrainedValue = { value = "Value" },
					Fire = { heat_xml = "Heat", size_xml = "Size" },

					Humanoid = { Health_XML = "Health" },
					LocalizationTable = {
						Contents = function(instance)
							return instance:GetContents()
						end,
					},
					MaterialService = { Use2022MaterialsXml = "Use2022Materials" },

					Model = {
						ScaleFactor = function(instance)
							return instance:GetScale()
						end,
						WorldPivotData = "WorldPivot",
						_Inheritors = {
							Workspace = {
								CollisionGroupData = function()
									local collision_groups = game:GetService("PhysicsService")
										:GetRegisteredCollisionGroups()

									local col_groups_n = #collision_groups

									if col_groups_n == 0 then
										return "\1\0"
									end

									local buffer_size = 3

									for _, group in collision_groups do
										buffer_size += 7 + #group.name
									end

									buffer_size -= 1

									local b = buffer.create(buffer_size)

									local offset = 0

									buffer.writeu8(b, offset, 1)
									offset += 1
									buffer.writeu16(b, offset, col_groups_n * 10)
									offset += 2

									for i, group in collision_groups do
										local name, id, mask = group.name, i - 1, group.mask
										local name_len = #name

										if id ~= 0 then
											buffer.writeu8(b, offset, id)
											offset += 1
										end

										buffer.writeu8(b, offset, 4)
										offset += 1

										buffer.writei32(b, offset, mask)
										offset += 4

										buffer.writeu8(b, offset, name_len)
										offset += 1
										buffer.writestring(b, offset, name)
										offset += name_len
									end

									return buffer.tostring(b)
								end,
							},
						},
					},
					PackageLink = { PackageIdSerialize = "PackageId", VersionIdSerialize = "VersionNumber" },
					Players = { MaxPlayersInternal = "MaxPlayers", PreferredPlayersInternal = "PreferredPlayers" },

					StarterPlayer = { AvatarJointUpgrade_Serialized = "AvatarJointUpgrade" },
					Smoke = { size_xml = "Size", opacity_xml = "Opacity", riseVelocity_xml = "RiseVelocity" },
					Sound = {
						xmlRead_MaxDistance_3 = "RollOffMaxDistance",
					},
					WeldConstraint = {
						Part0Internal = "Part0",
						Part1Internal = "Part1",
					},
				},
			},
		},
	}

	local function CheckAlias(searchAlias)
		for option, alias in OPTIONS.OptionsAliases do
			if searchAlias == alias then
				return option
			end
		end
	end

	do -- Load Settings
		local function construct_NilinstanceFix(Name, ClassName, Separate)
			return function(instance, instancePropertyOverrides)
				local Exists = if Separate then nil else OPTIONS.NilInstancesFixes[Name]

				local Fix

				local DoesntExist = not Exists
				if DoesntExist then
					Fix = Instance.new(ClassName)
					if not Separate then
						OPTIONS.NilInstancesFixes[Name] = Fix
					end

					instancePropertyOverrides[Fix] = { __Children = { instance }, Properties = { Name = Name } }
				else
					Fix = Exists
				end

				table.insert(instancePropertyOverrides[Fix].__Children, instance)
				if DoesntExist then
					return Fix
				end
			end
		end

		OPTIONS.NilInstancesFixes.Animator = construct_NilinstanceFix(
			"Animator has to be placed under Humanoid or AnimationController",
			"AnimationController"
		)
		OPTIONS.NilInstancesFixes.AdPortal = construct_NilinstanceFix("AdPortal must be parented to a Part", "Part")
		OPTIONS.NilInstancesFixes.Attachment =
			construct_NilinstanceFix("Attachments must be parented to a BasePart or another Attachment", "Part")
		OPTIONS.NilInstancesFixes.BaseWrap =
			construct_NilinstanceFix("BaseWrap must be parented to a MeshPart", "MeshPart")
		OPTIONS.NilInstancesFixes.PackageLink =
			construct_NilinstanceFix("Package already has a PackageLink", "Folder", true)

		if CustomOptions2 and type(CustomOptions2) == "table" then
			local tmp = CustomOptions
			local Type = typeof(tmp)
			CustomOptions = CustomOptions2
			if Type == "Instance" then
				CustomOptions.Object = tmp
			elseif Type == "table" and typeof(tmp[1]) == "Instance" then
				CustomOptions.ExtraInstances = tmp
				OPTIONS.IsModel = true
			end
		end

		local Type = typeof(CustomOptions)

		if Type == "table" then
			if typeof(CustomOptions[1]) == "Instance" then
				OPTIONS.mode = "invalidmode"
				OPTIONS.ExtraInstances = CustomOptions
				OPTIONS.IsModel = true
				CustomOptions = {}
			else
				for key, value in CustomOptions do
					if OPTIONS[key] == nil then
						local Option = CheckAlias(key)

						if Option then
							OPTIONS[Option] = value
						end
					else
						OPTIONS[key] = value
					end
				end
				local Decompile = CustomOptions.Decompile
				if Decompile ~= nil then
					OPTIONS.noscripts = not Decompile
				end
				local SavePlayerCharacters = CustomOptions.SavePlayerCharacters
				if SavePlayerCharacters ~= nil then
					OPTIONS.RemovePlayerCharacters = not SavePlayerCharacters
				end
				local RemovePlayers = CustomOptions.RemovePlayers
				if RemovePlayers ~= nil then
					OPTIONS.IsolatePlayers = not RemovePlayers
				end
			end
		elseif Type == "Instance" then
			OPTIONS.mode = "invalidmode"
			OPTIONS.Object = CustomOptions
			CustomOptions = {}
		else
			CustomOptions = {}
		end
	end

	do -- Fixes crashes on Mobile Devices
		local DecompileIgnore = OPTIONS.DecompileIgnore
		local ModuleScript = DecompileIgnore.ModuleScript
		if type(DecompileIgnore.ModuleScript) == "table" then
			table.insert(DecompileIgnore, "PlayerModule")
		elseif ModuleScript == nil then
			DecompileIgnore.ModuleScript = { "PlayerModule" }
		end
	end
	local InstancePropertyOverrides = {}

	local DecompileIgnore, IgnoreList, IgnoreProperties, NotCreatableFixes =
		ArrayToDictionary(OPTIONS.DecompileIgnore, true),
		ArrayToDictionary(OPTIONS.IgnoreList, true),
		ArrayToDictionary(OPTIONS.IgnoreProperties),
		ArrayToDictionary(OPTIONS.NotCreatableFixes, true, "Folder")

	local __DEBUG_MODE = OPTIONS.__DEBUG_MODE

	local FilePath = OPTIONS.FilePath
	local SaveCacheInterval = OPTIONS.SaveCacheInterval
	local ToSaveInstance = OPTIONS.Object
	local IsModel = OPTIONS.IsModel
	if ToSaveInstance and CustomOptions.IsModel == nil then
		IsModel = true
	end
	local IgnoreDefaultProperties = OPTIONS.IgnoreDefaultProperties
	local IgnoreNotArchivable = not OPTIONS.IgnoreNotArchivable
	local IgnorePropertiesOfNotScriptsOnScriptsMode = OPTIONS.IgnorePropertiesOfNotScriptsOnScriptsMode
	local IgnoreSpecialProperties = OPTIONS.IgnoreSpecialProperties
	local notIgnoreSpecialProperties = not IgnoreSpecialProperties

	local IsolateLocalPlayer = OPTIONS.IsolateLocalPlayer
	local IsolateLocalPlayerCharacter = OPTIONS.IsolateLocalPlayerCharacter
	local IsolateStarterPlayer = OPTIONS.IsolateStarterPlayer
	local IsolatePlayers = OPTIONS.IsolatePlayers

	local SaveNonCreatable = OPTIONS.SaveNonCreatable
	local TreatUnionsAsParts = OPTIONS.TreatUnionsAsParts

	local DecompileJobless = OPTIONS.DecompileJobless
	local ScriptCache = OPTIONS.scriptcache and getscriptbytecode

	local Timeout = OPTIONS.timeout

	local IgnoreSharedStrings = OPTIONS.IgnoreSharedStrings
	local SharedStringOverwrite = OPTIONS.SharedStringOverwrite
	local NotScriptableFixes = OPTIONS.NotScriptableFixes
	local NilInstances = OPTIONS.NilInstances

	if NilInstances and enablenilinstances then
		enablenilinstances()
	end

	local SaveBytecode
	if OPTIONS.SaveBytecode and getscriptbytecode then
		SaveBytecode = function(script)
			local s, bytecode = pcall(getscriptbytecode, script)

			if s then
				if bytecode and bytecode ~= "" then
					return "-- Bytecode (Base64):\n-- " .. base64encode(bytecode) .. "\n\n"
				end
			end
		end
	end

	local ldeccache = GLOBAL_ENV.scriptcache

	local DecompileIgnoring, ToSaveList, ldecompile, placename, elapse_t, SaveNonCreatableWillBeEnabled, RecoveredScripts

	if ScriptCache and not ldeccache then
		ldeccache = {}
		GLOBAL_ENV.scriptcache = ldeccache
	end

	if ToSaveInstance == game then
		OPTIONS.mode = "full"
		ToSaveInstance = nil
		IsModel = nil
	end

	local function isLuaSourceContainer(instance)
		return instance:IsA("LuaSourceContainer")
	end

	do
		local mode = string.lower(OPTIONS.mode)
		local tmp = table.clone(OPTIONS.ExtraInstances)

		local PlaceName = game.PlaceId

		pcall(function()
			PlaceName ..= " " .. service.MarketplaceService:GetProductInfo(PlaceName).Name
		end)

		local function sanitizeFileName(str)
			return string.sub(string.gsub(string.gsub(string.gsub(str, "[^%w _]", ""), " +", " "), " +$", ""), 1, 240)
		end

		if IsModel then
			if mode == "optimized" then
				mode = "full"
			end

			for _, key in
				{
					"IsolateLocalPlayer",
					"IsolateLocalPlayerCharacter",
					"IsolatePlayers",
					"IsolateStarterPlayer",
					"NilInstances",
				}
			do
				if CustomOptions[key] == nil then
					local Option = CheckAlias(key)
					if CustomOptions[Option] == nil then
						OPTIONS[key] = false
					end
				end
			end

			placename = (
				FilePath or sanitizeFileName("model " .. PlaceName .. " " .. (ToSaveInstance or tmp[1]):GetFullName())
			) .. ".rbxmx"
		else
			placename = (FilePath or sanitizeFileName("place " .. PlaceName)) .. ".rbxlx"
		end

		if mode ~= "scripts" then
			IgnorePropertiesOfNotScriptsOnScriptsMode = nil
		end

		local TempRoot = ToSaveInstance or game

		if mode == "full" then
			local Children = TempRoot:GetChildren()
			if 0 < #Children then
				table.move(Children, 1, #Children, #tmp + 1, tmp)
			end
		elseif mode == "optimized" then
			for _, serviceName in
				{
					"Workspace",
					"Players",
					"Lighting",
					"MaterialService",
					"ReplicatedFirst",
					"ReplicatedStorage",

					"ServerScriptService",
					"ServerStorage",

					"StarterGui",
					"StarterPack",
					"StarterPlayer",
					"Teams",
					"SoundService",
					"TextChatService",
					"Chat",

					"JointsService",

					"LocalizationService",
				}
			do
				table.insert(tmp, service[serviceName])
			end
		elseif mode == "scripts" then
			local unique = {}
			for _, instance in TempRoot:GetDescendants() do
				if isLuaSourceContainer(instance) then
					local Parent = instance.Parent
					while Parent and Parent ~= TempRoot do
						instance = instance.Parent
						Parent = instance.Parent
					end
					if Parent then
						unique[instance] = true
					end
				end
			end
			for instance in unique do
				table.insert(tmp, instance)
			end
		end
		ToSaveList = tmp
	end

	local function get_size_format()
		local Size

		for i, unit in
			{
				"B",
				"KB",
				"MB",
				"GB",
				"TB",
			}
		do
			if totalsize < 0x400 ^ i then
				Size = math.floor(totalsize / (0x400 ^ (i - 1)) * 10) / 10 .. " " .. unit
				break
			end
		end

		return Size
	end

	local function wait_for_render()
		service.RunService.RenderStepped:Wait()
	end

	local Loading
	local function run_with_loading(text, keepStatus, waitForRender, taskFunction, ...)
		local previousStatus

		if StatusText then
			if keepStatus then
				previousStatus = StatusText.Text
			end
			Loading = task.spawn(function()
				local spinner_count = 0
				local chars = { "|", "/", "—", "\\" }

				local function getLoadingText()
					spinner_count += 1

					if #chars < spinner_count then
						spinner_count = 1
					end

					return chars[spinner_count]
				end

				text ..= " "

				while true do
					StatusText.Text = text .. getLoadingText()
					task.wait(0.25)
				end
			end)
			if waitForRender then
				wait_for_render()
			end
		end

		local result = { taskFunction(...) }

		if Loading then
			task.cancel(Loading)
			Loading = nil
			if previousStatus then
				StatusText.Text = previousStatus
			end
		end

		return unpack(result)
	end

	do
		if load_decompiler then
			pcall(load_decompiler, Timeout)
		end
		local Decompiler = OPTIONS.decomptype == "custom" and custom_decompiler
			or global_container.decompile
			or custom_decompiler

		if OPTIONS.noscripts then
			ldecompile = function()
				return "-- Decompiling is disabled"
			end
		elseif Decompiler then
			local function DecompileHandler(script)
				if Timeout == -1 then
					return pcall(Decompiler, script)
				end

				local thread = coroutine.running()
				local timeoutThread, isCancelled

				task.spawn(function()
					local ok, result = pcall(Decompiler, script)

					if isCancelled then
						return
					end

					if timeoutThread then
						task.cancel(timeoutThread)
					else
						task.defer(function()
							task.cancel(timeoutThread)
						end)
					end

					while coroutine.status(thread) ~= "suspended" do
						task.wait()
					end

					coroutine.resume(thread, ok, result)
				end)

				timeoutThread = task.delay(Timeout, function()
					isCancelled = true

					coroutine.resume(thread, nil, "Decompiler timed out")
				end)

				return coroutine.yield()
			end

			ldecompile = function(script)
				local hashed_bytecode
				if ScriptCache then
					local s, bytecode = pcall(getscriptbytecode, script)
					local cached

					if s then
						if not bytecode or bytecode == "" then
							return "-- The Script is Empty"
						end
						hashed_bytecode = sha384(bytecode)
						cached = ldeccache[hashed_bytecode]
					end

					if cached then
						if __DEBUG_MODE then
							warn("Found in Cache", script:GetFullName())
						end
						return cached
					elseif DecompileJobless then
						return "-- Not found in already decompiled ScriptCache"
					end
				else
					task.wait()
				end

				local ok, result = run_with_loading("Decompiling " .. script.Name, true, nil, DecompileHandler, script)

				if not result then
					ok, result = false, "Empty Output"
				end

				local output
				if ok then
					result = string.gsub(result, "\0", "\\0")
					output = result
				else
					output = "--[[ Failed to decompile\nReason:\n" .. (result or "") .. "\n]]"
				end

				if ScriptCache and hashed_bytecode then
					ldeccache[hashed_bytecode] = output
					if __DEBUG_MODE then
						warn("Cached", script:GetFullName())
					end
				end

				return output
			end
		else
			ldecompile = function()
				return "-- Decompiling is NOT supported on your executor"
			end
		end
	end

	local function getsafeproperty(instance, propertyName)
		return instance[propertyName]
	end

	local function ReadProperty(instance, property, propertyName, special)
		local raw = "__BREAK"

		local InstanceOverride = InstancePropertyOverrides[instance]
		if InstanceOverride then
			local PropertyOverride = InstanceOverride.Properties[propertyName]
			if PropertyOverride then
				return PropertyOverride
			end
		end

		local CanRead = property.CanRead

		if CanRead == false then
			return "__BREAK"
		end

		local function filterResult(result)
			return result == nil
				or result == "can't get value"
				or type(result) == "string"
					and (string_find(result, "Unable to get property " .. propertyName) or property.Category == "Enum" and string_find(
						result,
						"Invalid value for enum "
					))
		end

		if special then
			if gethiddenproperty then
				local ok, result = pcall(gethiddenproperty, instance, propertyName)

				if ok then
					raw = result
				end

				if filterResult(raw) then
					if __DEBUG_MODE then
						warn("Filtered", propertyName)
					end
					property.CanRead = false

					return "__BREAK"
				end
			end
		else
			if CanRead then
				raw = instance[propertyName]
			else
				local ok, result = pcall(getsafeproperty, instance, propertyName)

				if ok then
					raw = result
				elseif notIgnoreSpecialProperties and gethiddenproperty then
					ok, result = pcall(gethiddenproperty, instance, propertyName)

					if ok then
						raw = result

						property.Special = true
					end
				end

				property.CanRead = ok
				if not ok or filterResult(raw) then
					return "__BREAK"
				end
			end
		end

		return raw
	end

	local function ReturnItem(className, instance)
		local ref = referents[instance]
		if not ref then
			ref = ref_size
			referents[instance] = ref
			ref_size += 1
		end

		return '<Item class="' .. className .. '" referent="' .. ref .. '"><Properties>'
	end

	local function ReturnProperty(tag, propertyName, value)
		return "<" .. tag .. ' name="' .. propertyName .. '">' .. value .. "</" .. tag .. ">"
	end

	local function ReturnValueAndTag(raw, valueType, descriptor)
		local value, tag = (descriptor or XML_Descriptors[valueType])(raw)

		return value, tag == nil and valueType or tag
	end

	local function InheritsFix(fixes, className, instance)
		local Fix = fixes[className]
		if Fix then
			return Fix
		elseif Fix == nil then
			for class_name, fix in fixes do
				if instance:IsA(class_name) then
					return fix
				end
			end
		end
	end

	local function GetInheritedProps(className)
		local prop_list = {}
		local layer = ClassList[className]
		while layer do
			local layer_props = layer.Properties
			table.move(layer_props, 1, #layer_props, #prop_list + 1, prop_list)

			layer = ClassList[layer.Superclass]
		end
		inherited_properties[className] = prop_list
		return prop_list
	end

	local function save_cache()
		local savestr = table.concat(savebuffer)
		totalstr ..= savestr

		totalsize += #savestr

		table.clear(savebuffer)
		savebuffer_size = 1

		if StatusText then
			StatusText.Text = "Saving.. Size: " .. get_size_format()
		end
		wait_for_render()
	end

	local function save_specific(className, properties)
		local Ref = Instance.new(className)
		local Item = ReturnItem(Ref.ClassName, Ref)

		for propertyName, val in properties do
			local Class, value, tag

			if "Source" == propertyName then
				tag = "ProtectedString"
				value = XML_Descriptors.__PROTECTEDSTRING(val)
				Class = "Script"
			elseif "Name" == propertyName then
				Class = "Instance"
				value, tag = ReturnValueAndTag(val, "string")
			end

			if Class then
				Item ..= ReturnProperty(tag, propertyName, value)
			end
		end
		Item ..= "</Properties>"
		return Item
	end

	local function save_hierarchy(hierarchy, queuedHierarchy)
		for _, instance in hierarchy do
			if IgnoreNotArchivable and not instance.Archivable then
				continue
			end

			local SkipEntirely = IgnoreList[instance]
			if SkipEntirely then
				continue
			end

			local ClassName = instance.ClassName

			local InstanceName = instance.Name

			do
				local OnIgnoredList = IgnoreList[ClassName]
				if OnIgnoredList and (OnIgnoredList == true or OnIgnoredList[InstanceName]) then
					continue
				end
			end

			if not DecompileIgnoring then
				DecompileIgnoring = DecompileIgnore[instance]

				if DecompileIgnoring == nil then
					local DecompileIgnored = DecompileIgnore[ClassName]
					if DecompileIgnored then
						DecompileIgnoring = DecompileIgnored == true or DecompileIgnored[InstanceName]
					end
				end

				if DecompileIgnoring then
					DecompileIgnoring = instance
				elseif DecompileIgnoring == false then
					DecompileIgnoring = 1
				end
			end

			local InstanceOverride, ClassNameOverride

			do
				local function replaceClassName(newClassName)
					if InstanceName ~= ClassName then
						InstanceOverride = InstancePropertyOverrides[instance]
						if not InstanceOverride then
							InstanceOverride = { Properties = { Name = "[" .. ClassName .. "] " .. InstanceName } }
							InstancePropertyOverrides[instance] = InstanceOverride
						end
					end
					ClassName = newClassName
				end

				local Fix = NotCreatableFixes[ClassName]

				if Fix then
					if SaveNonCreatable then
						replaceClassName(Fix)
					else
						continue
					end
				else
					if TreatUnionsAsParts and instance:IsA("PartOperation") then
						replaceClassName("Part")
						ClassNameOverride = "BasePart"
					elseif not ClassList[ClassName] then
						if __DEBUG_MODE then
							warn("Class not Found", ClassName)
						end

						ClassNameOverride = "Folder"
					end
				end
			end

			if not InstanceOverride then
				InstanceOverride = InstancePropertyOverrides[instance]
			end
			local ChildrenOverride = InstanceOverride and InstanceOverride.__Children

			if ChildrenOverride then
				savebuffer[savebuffer_size] = save_specific(ClassName, InstanceOverride.Properties)
				savebuffer_size += 1
			else
				savebuffer[savebuffer_size] = ReturnItem(ClassName, instance)
				savebuffer_size += 1
				if not (IgnorePropertiesOfNotScriptsOnScriptsMode and not isLuaSourceContainer(instance)) then
					local default_instance, new_def_inst

					if IgnoreDefaultProperties then
						default_instance = default_instances[ClassName]
						if not default_instance then
							local ClassTags = ClassList[ClassName].Tags
							if not (ClassTags and ClassTags.NotCreatable) then
								new_def_inst = Instance.new(ClassName)

								default_instance = {}

								default_instances[ClassName] = default_instance
							elseif __DEBUG_MODE then
								warn("Unable to create default Instance", ClassName)
							end
						end
					end
					local proplist = inherited_properties[ClassNameOverride or ClassName]
					if not proplist then
						proplist = GetInheritedProps(ClassNameOverride or ClassName)
						inherited_properties[ClassNameOverride or ClassName] = proplist
					end
					for _, Property in proplist do
						local PropertyName = Property.Name

						if IgnoreProperties[PropertyName] then
							continue
						end

						local Special = Property.Special
						if IgnoreSpecialProperties and Special then
							continue
						end

						local ValueType = Property.ValueType

						if IgnoreSharedStrings and ValueType == "SharedString" then
							continue
						end

						local raw = ReadProperty(instance, Property, PropertyName, Special)
						if raw == "__BREAK" then
							local PropertyFix
							do
								local Inheritors = NotScriptableFixes
								while Inheritors do
									local fix
									for superclass, fixes in Inheritors do
										if instance:IsA(superclass) then
											fix = fixes
											break
										end
									end
									if fix then
										PropertyFix = fix[PropertyName]
										if PropertyFix then
											break
										end
									else
										break
									end
									Inheritors = fix._Inheritors
								end
							end

							if PropertyFix then
								local ok, result = pcall(
									type(PropertyFix) == "string" and getsafeproperty or PropertyFix,
									instance,
									PropertyFix
								)

								if ok then
									raw = result
								else
									if __DEBUG_MODE then
										warn("Fix Failed", PropertyName)
									end
									continue
								end
							else
								continue
							end
						end

						if SharedStringOverwrite and ValueType == "BinaryString" then
							ValueType = "SharedString"
						end

						if
							default_instance
							and not Property.Special
							and not (PropertyName == "Source" and isLuaSourceContainer(instance))
						then
							if new_def_inst then
								default_instance[PropertyName] = getsafeproperty(new_def_inst, PropertyName)
							end
							if default_instance[PropertyName] == raw then
								continue
							end
						end

						local Category = Property.Category

						local tag, value
						if Category == "Class" then
							tag = "Ref"
							if raw then
								if SaveNonCreatableWillBeEnabled then
									local Fix = NotCreatableFixes[raw.ClassName]
									if
										Fix
										and (
											PropertyName == "PlayerToHideFrom"
											or ValueType ~= "Instance" and ValueType ~= Fix
										)
									then
										continue
									end
								end

								value = referents[raw]
								if not value then
									value = ref_size
									referents[raw] = value
									ref_size += 1
								end
							else
								value = "null"
							end
						elseif Category == "Enum" then
							value, tag = XML_Descriptors.__ENUM(raw)
						else
							local Descriptor = XML_Descriptors[ValueType]

							if Descriptor then
								value, tag = ReturnValueAndTag(raw, ValueType, Descriptor)
							elseif "ProtectedString" == ValueType then
								tag = ValueType

								if PropertyName == "Source" then
									if DecompileIgnoring then
										if DecompileIgnoring == 1 then
											DecompileIgnoring = nil
										end
										value = "-- Ignored"
									else
										local should_decompile = true
										local LinkedSource
										local LinkedSource_Url = instance.LinkedSource
										local hasLinkedSource = LinkedSource_Url ~= ""
										if hasLinkedSource then
											local Path = instance:GetFullName()
											if RecoveredScripts then
												table.insert(RecoveredScripts, Path)
											else
												RecoveredScripts = { Path }
											end

											do
												should_decompile = nil
												value = ""
											end

											LinkedSource = string.match(LinkedSource_Url, "%w+$")
											if LinkedSource then
												local cached = ldeccache[LinkedSource]

												if cached then
													value = cached
													should_decompile = nil
												elseif DecompileJobless then
													value = "-- Not found in already decompiled ScriptCache"
													should_decompile = nil
												end

												local function filterResults(str)
													local o, r =
														pcall(service.HttpService.JSONDecode, service.HttpService, str)
													if o and r.errors then
														return false
													end
													return true
												end

												local asset = (string.find(LinkedSource, "%a") and "hash" or "id")
													.. "="
													.. LinkedSource

												local source
												local ok = pcall(function()
													source = game:HttpGet(
														"https://assetdelivery.roproxy.com/v1/asset/?" .. asset
													)
												end)

												if ok then
													ok = filterResults(source)
												end

												if not ok then
													ok = run_with_loading(
														"Getting " .. instance.Name .. " LinkedSource",
														true,
														nil,
														pcall,
														function()
															source = game:HttpGet(
																"https://linkedsource.glitch.me/asset/" .. asset
															)
														end
													)
												end

												if ok then
													ok = filterResults(source)
												end

												if ok then
													ldeccache[LinkedSource] = source

													value = source
												end
											else
												warn(
													"FAILED TO EXTRACT ORIGINAL SCRIPT SOURCE (OPEN A GITHUB ISSUE): ",
													instance:GetFullName(),
													LinkedSource_Url
												)
											end
										end

										if should_decompile then
											local isLocalScript = instance:IsA("LocalScript")
											if
												isLocalScript and instance.RunContext == Enum.RunContext.Server
												or not isLocalScript
													and instance:IsA("Script")
													and instance.RunContext ~= Enum.RunContext.Client
											then
												value = "-- Server Scripts can NOT be decompiled"
											else
												value = ldecompile(instance)
												if SaveBytecode then
													local output = SaveBytecode(instance)
													if output then
														value = output .. value
													end
												end
											end
										end

										value = "-- Saved by UniversalSynSaveInstance (standalone) https://discord.gg/wx4ThpAsmw\n\n"
											.. (hasLinkedSource and "-- Original Source: https://assetdelivery.roblox.com/v1/asset/?id=" .. (LinkedSource or LinkedSource_Url) .. "\n\n" or "")
											.. value
									end
								end
								value = XML_Descriptors.__PROTECTEDSTRING(value)
							else
								if string.sub(ValueType, 1, 8) == "Optional" then
									Descriptor = XML_Descriptors[string.sub(ValueType, 9)]

									if Descriptor then
										if raw ~= nil then
											value, tag = ReturnValueAndTag(raw, ValueType, Descriptor)
										else
											value, tag = "", ValueType
										end
									end
								end
							end
						end

						if tag then
							savebuffer[savebuffer_size] = ReturnProperty(tag, PropertyName, value)
							savebuffer_size += 1
						else
							warn("UNSUPPORTED TYPE (OPEN A GITHUB ISSUE): ", ValueType, ClassName, PropertyName)
						end
					end
				end
				savebuffer[savebuffer_size] = "</Properties>"
				savebuffer_size += 1

				if SaveCacheInterval < savebuffer_size then
					save_cache()
				end
			end

			if SkipEntirely ~= false then
				local Children = ChildrenOverride or queuedHierarchy or instance:GetChildren()

				if #Children ~= 0 then
					save_hierarchy(Children)
				end
			end

			if DecompileIgnoring and DecompileIgnoring == instance then
				DecompileIgnoring = nil
			end

			savebuffer[savebuffer_size] = "</Item>"
			savebuffer_size += 1
		end
	end

	local function save_extra(name, hierarchy, customClassName, source)
		savebuffer[savebuffer_size] = save_specific((customClassName or "Folder"), { Name = name, Source = source })
		savebuffer_size += 1
		if hierarchy then
			save_hierarchy(hierarchy)
		end
		savebuffer[savebuffer_size] = "</Item>"
		savebuffer_size += 1
	end

	local function save_game()
		writefile(placename, "")

		if IsModel then
			savebuffer[savebuffer_size] = '<Meta name="ExplicitAutoJoints">true</Meta>'
			savebuffer_size += 1
		end

		SaveNonCreatableWillBeEnabled = SaveNonCreatable
			or (IsolateLocalPlayer or IsolateLocalPlayerCharacter) and IsolateLocalPlayer
			or IsolatePlayers
			or NilInstances and global_container.getnilinstances
		if ToSaveInstance then
			save_hierarchy({ ToSaveInstance }, ToSaveList)
		else
			save_hierarchy(ToSaveList)
		end

		if IsolateLocalPlayer or IsolateLocalPlayerCharacter then
			local Players = service.Players
			local LocalPlayer = Players.LocalPlayer
			if IsolateLocalPlayer then
				SaveNonCreatable = true
				save_extra("LocalPlayer", LocalPlayer:GetChildren())
			end
			if IsolateLocalPlayerCharacter then
				local LocalPlayerCharacter = LocalPlayer.Character
				if LocalPlayerCharacter then
					save_extra("LocalPlayer Character", LocalPlayerCharacter:GetChildren())
				end
			end
		end

		if IsolateStarterPlayer then
			save_extra("StarterPlayer", service.StarterPlayer:GetChildren())
		end

		if IsolatePlayers then
			SaveNonCreatable = true
			save_extra("Players", service.Players:GetChildren())
		end

		if NilInstances and global_container.getnilinstances then
			local nil_instances, nil_instances_size = {}, 1

			local NilInstancesFixes = OPTIONS.NilInstancesFixes

			for _, instance in global_container.getnilinstances() do
				if instance == game then
					instance = nil
				else
					local ClassName = instance.ClassName

					local Fix = InheritsFix(NilInstancesFixes, ClassName, instance)

					if Fix then
						instance = Fix(instance, InstancePropertyOverrides)
					end

					local Class = ClassList[ClassName]
					if Class then
						local ClassTags = Class.Tags
						if ClassTags and ClassTags.Service then
							instance = nil
						end
					end
				end
				if instance then
					nil_instances[nil_instances_size] = instance
					nil_instances_size += 1
				end
			end
			SaveNonCreatable = true
			save_extra("Nil Instances", nil_instances)
		end

		if OPTIONS.ReadMe then
			save_extra(
				"README",
				nil,
				"Script",
				"--[[\n"
					.. (RecoveredScripts and "\t\tIMPORTANT: Original Source of these Scripts was Recovered: " .. service.HttpService:JSONEncode(
						RecoveredScripts
					) .. "\n" or "")
					.. [[
		Thank you for using UniversalSynSaveInstance.

		If you didn't save in Binary - we recommended to save the game right away to take advantage of the binary format & to preserve values of certain properties if you used IgnoreDefaultProperties setting (as they might change in the future).
		You can do that by going to FILE -> Save to File As -> Make sure File Name ends with .rbxl -> Save

		If your player cannot spawn into the game, please move the scripts in StarterPlayer elsewhere & Set CharacterAutoLoads to true on Players service.

		If the chat system does not work, please use the explorer and delete everything inside the TextChatService/Chat service(s). 

		Or run `game:GetService("Chat"):ClearAllChildren()`
				
		If Union and MeshPart collisions don't work, run the script below in the Studio Command Bar:
				
				
		local C = game:GetService("CoreGui")
		local D = Enum.CollisionFidelity.Default
				
		for _, v in game:GetDescendants() do
			if v:IsA("TriangleMeshPart") and not v:IsDescendantOf(C) then
				v.CollisionFidelity = D
			end
		end
				
		If you can't move the Camera, run the scripts in the Studio Command Bar:
			
		workspace.CurrentCamera.CameraType = Enum.CameraType.Fixed
		
		Or Destroy the Camera.

		This file was generated with the following settings:
				]]
					.. service.HttpService:JSONEncode(OPTIONS)
					.. "\n\n\t\tElapsed time: "
					.. os.clock() - elapse_t
					.. " PlaceId: "
					.. game.PlaceId
					.. " Executor: "
					.. EXECUTOR_NAME
					.. "\n]]"
			)
		end
		do
			local tmp = { "<SharedStrings>" }
			for identifier, value in SharedStrings do
				table.insert(tmp, '<SharedString md5="' .. identifier .. '">' .. value .. "</SharedString>")
			end

			if 1 < #tmp then
				savebuffer[savebuffer_size] = table.concat(tmp)
				savebuffer[savebuffer_size] = "</SharedStrings>"
				savebuffer_size += 2
			end
		end

		savebuffer[savebuffer_size] = "</roblox>"
		savebuffer_size += 1
		save_cache()
		do
			if OPTIONS.Anonymous then
				local LocalPlayer = service.Players.LocalPlayer

				totalstr = string.gsub(string.gsub(totalstr, LocalPlayer.UserId, "1"), LocalPlayer.Name, "Roblox")
			end

			run_with_loading(
				"Writing " .. get_size_format() .. " to File (Depends on Exec)",
				nil,
				true,
				writefile,
				placename,
				totalstr
			)
		end
		table.clear(SharedStrings)
	end

	local Connections
	do
		local Players = service.Players
		local LocalPlayer = Players.LocalPlayer

		if IgnoreList.Model ~= true then
			Connections = {}
			local function ignoreCharacter(player)
				table.insert(
					Connections,
					player.CharacterAdded:Connect(function(character)
						IgnoreList[character] = true
					end)
				)

				local Character = player.Character
				if Character then
					IgnoreList[Character] = true
				end
			end

			if OPTIONS.RemovePlayerCharacters then
				table.insert(
					Connections,
					Players.PlayerAdded:Connect(function(player)
						ignoreCharacter(player)
					end)
				)
				for _, player in Players:GetPlayers() do
					ignoreCharacter(player)
				end
			else
				IgnoreNotArchivable = false
				if IsolateLocalPlayerCharacter then
					ignoreCharacter(LocalPlayer)
				end
			end
		end
		if IsolateLocalPlayer and IgnoreList.Player ~= true then
			IgnoreList[LocalPlayer] = true
		end
	end

	if IsolateStarterPlayer then
		IgnoreList.StarterPlayer = false
	end

	if IsolatePlayers then
		IgnoreList.Players = false
	end

	if OPTIONS.ShowStatus then
		do
			local Exists = GLOBAL_ENV._statustext
			if Exists then
				Exists:Destroy()
			end
		end

		local StatusGui = Instance.new("ScreenGui")

		GLOBAL_ENV._statustext = StatusGui

		StatusGui.DisplayOrder = 2_000_000_000
		pcall(function()
			StatusGui.OnTopOfCoreBlur = true
		end)

		StatusText = Instance.new("TextLabel")

		StatusText.Text = "Saving..."

		StatusText.BackgroundTransparency = 1
		StatusText.Font = Enum.Font.Code
		StatusText.AnchorPoint = Vector2.new(1)
		StatusText.Position = UDim2.new(1)
		StatusText.Size = UDim2.new(0.3, 0, 0, 20)

		StatusText.TextColor3 = Color3.new(1, 1, 1)
		StatusText.TextScaled = true
		StatusText.TextStrokeTransparency = 0.7
		StatusText.TextXAlignment = Enum.TextXAlignment.Right
		StatusText.TextYAlignment = Enum.TextYAlignment.Top

		StatusText.Parent = StatusGui

		local function randomString()
			local length = math.random(10, 20)
			local randomarray = table.create(length)
			for i = 1, length do
				randomarray[i] = string.char(math.random(32, 126))
			end
			return table.concat(randomarray)
		end

		if global_container.gethui then
			StatusGui.Name = randomString()
			StatusGui.Parent = global_container.gethui()
		elseif global_container.protectgui then
			StatusGui.Name = randomString()
			global_container.protectgui(StatusGui)
			StatusGui.Parent = service.CoreGui
		else
			local RobloxGui = service.CoreGui:FindFirstChild("RobloxGui")
			if RobloxGui then
				StatusGui.Parent = RobloxGui
			else
				StatusGui.Name = randomString()
				StatusGui.Parent = service.CoreGui
			end
		end
	end

	do
		if OPTIONS.SafeMode then
			service.Players.LocalPlayer:Kick("\nSaving in Progress..\nPlease do NOT leave")
			service.RunService:Set3dRenderingEnabled(false)
			wait_for_render()
			task.delay(10, service.GuiService.ClearError, service.GuiService)
		end

		elapse_t = os.clock()
		local ok, err = xpcall(save_game, function(err)
			return debug.traceback(err)
		end)
		if Connections then
			for _, connection in Connections do
				connection:Disconnect()
			end
		end
		if StatusText then
			task.spawn(function()
				elapse_t = os.clock() - elapse_t
				local Log10 = math.log10(elapse_t)
				local ExtraTime = 10
				if ok then
					StatusText.Text = string.format("Saved! Time %.3f seconds; Size %s", elapse_t, get_size_format())
					StatusText.TextColor3 = Color3.new(0, 1)
					task.wait(Log10 * 2 + ExtraTime)
				else
					if Loading then
						task.cancel(Loading)
						Loading = nil
					end
					StatusText.Text = "Failed! Check F9 console for more info"
					StatusText.TextColor3 = Color3.new(1)
					warn("Error found while saving:")
					warn(err)
					task.wait(Log10 + ExtraTime)
				end
				StatusText:Destroy()
			end)
		end
	end
end

return synsaveinstance

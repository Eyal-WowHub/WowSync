local _, addon = ...
local Hash = {}
addon.Hash = Hash

--[[
    Hash — a deterministic content fingerprint for arbitrary Lua values.

    Two values with the same content always produce the same fingerprint
    regardless of table key order, so callers can use it for identity and
    change detection (e.g. "nothing changed" skips). This is generic and owns
    no knowledge of what it hashes.
]]

-- Orders table keys by their string form so mixed key types sort deterministically.
local function CompareKeys(leftKey, rightKey)
    return tostring(leftKey) < tostring(rightKey)
end

-- Serialize a value into a canonical string (table keys sorted) so equal
-- content always serializes identically.
local function SerializeToCanonicalString(value, parts)
    local valueType = type(value)
    if valueType == "table" then
        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
        table.sort(keys, CompareKeys)

        parts[#parts + 1] = "{"
        for _, key in ipairs(keys) do
            parts[#parts + 1] = tostring(key)
            parts[#parts + 1] = "="
            SerializeToCanonicalString(value[key], parts)
            parts[#parts + 1] = ";"
        end
        parts[#parts + 1] = "}"
    else
        parts[#parts + 1] = valueType
        parts[#parts + 1] = ":"
        parts[#parts + 1] = tostring(value)
    end
end

-- 64-bit FNV-1a, held as two 32-bit halves because the full offset basis and
-- running hash exceed the 2^53 integer range a Lua double represents exactly.
local OFFSET_HIGH, OFFSET_LOW = 0xcbf29ce4, 0x84222325
local PRIME_HIGH, PRIME_LOW = 0x00000100, 0x000001b3

-- 32x32 -> 64-bit product as (high, low) 32-bit halves, accumulated in 16-bit
-- limbs so no intermediate exceeds 2^53.
local function MultiplyTo64(a, b)
    local a0 = a % 65536
    local a1 = (a - a0) / 65536
    local b0 = b % 65536
    local b1 = (b - b0) / 65536

    local p00 = a0 * b0
    local p01 = a0 * b1
    local p10 = a1 * b0
    local p11 = a1 * b1

    local limb0 = p00 % 65536
    local carry = (p00 - limb0) / 65536

    local mid = carry + (p01 % 65536) + (p10 % 65536)
    local limb1 = mid % 65536
    carry = (mid - limb1) / 65536 + (p01 - p01 % 65536) / 65536 + (p10 - p10 % 65536) / 65536

    local upper = carry + p11
    local limb2 = upper % 65536
    local limb3 = ((upper - limb2) / 65536) % 65536

    return limb3 * 65536 + limb2, limb1 * 65536 + limb0
end

-- (highA:lowA) * (highB:lowB) mod 2^64 -> (high, low) 32-bit halves.
local function Multiply64(highA, lowA, highB, lowB)
    local crossHigh, low = MultiplyTo64(lowA, lowB)
    local _, crossA = MultiplyTo64(lowA, highB)
    local _, crossB = MultiplyTo64(highA, lowB)
    local high = (crossHigh + crossA + crossB) % 4294967296
    return high, low
end

-- The fingerprint yields control back to a driving coroutine every this many
-- bytes, so fingerprinting a large value spreads across frames instead of
-- hitching; a synchronous caller (not in a coroutine) runs straight through.
local YIELD_STRIDE = 1024

-- FNV-1a -> 16-char hex fingerprint of any value.
function Hash:Create(value)
    local parts = {}
    SerializeToCanonicalString(value, parts)
    local text = table.concat(parts)

    local running = coroutine.running()
    local high, low = OFFSET_HIGH, OFFSET_LOW
    for i = 1, #text do
        -- bit.bxor may sign-extend; mask back to an unsigned 32-bit lane.
        low = bit.bxor(low, text:byte(i)) % 4294967296
        high, low = Multiply64(high, low, PRIME_HIGH, PRIME_LOW)
        if running and i % YIELD_STRIDE == 0 then
            coroutine.yield()
        end
    end

    return string.format("%08x%08x", high, low)
end

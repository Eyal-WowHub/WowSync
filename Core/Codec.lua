local _, addon = ...
local Codec = {}
addon.Codec = Codec

--[[
    Codec — the single place that turns a Lua value into a compact, storable
    string and back.

    Encode serializes the value to CBOR, compresses it, and Base64-encodes the
    result so it survives as printable text in SavedVariables; Decode reverses
    those steps. The output carries a version prefix so the format can change
    later without misreading older data. Both directions return nil plus an
    error message instead of raising, so a single bad value can never abort the
    caller.
]]

local C_EncodingUtil = C_EncodingUtil

-- DEFLATE with no wrapper is the smallest output; the checksum that Zlib/Gzip
-- add buys nothing for local, trusted data.
local COMPRESSION_METHOD = Enum.CompressionMethod.Deflate
local COMPRESSION_LEVEL = Enum.CompressionLevel.OptimizeForSize
local BASE64_VARIANT = Enum.Base64Variant.Standard

-- Single-character tag identifying the encoding layout, prepended to every
-- encoded string; Decode rejects anything it does not recognise.
local FORMAT_VERSION = "1"

-- Turns a Lua value into a versioned, compressed, Base64 string.
-- Returns the encoded string, or nil plus an error message.
function Codec:Encode(value)
    local ok, result = pcall(function()
        local serialized = C_EncodingUtil.SerializeCBOR(value)
        local compressed = C_EncodingUtil.CompressString(serialized, COMPRESSION_METHOD, COMPRESSION_LEVEL)
        return FORMAT_VERSION .. C_EncodingUtil.EncodeBase64(compressed, BASE64_VARIANT)
    end)

    if not ok then
        return nil, result
    end
    return result
end

-- Restores the Lua value from a string produced by Encode.
-- Returns the decoded value, or nil plus an error message.
function Codec:Decode(text)
    if type(text) ~= "string" then
        return nil, "expected an encoded string"
    end

    local version = text:sub(1, #FORMAT_VERSION)
    if version ~= FORMAT_VERSION then
        return nil, "unsupported codec version"
    end

    local payload = text:sub(#FORMAT_VERSION + 1)
    local ok, result = pcall(function()
        local compressed = C_EncodingUtil.DecodeBase64(payload, BASE64_VARIANT)
        local serialized = C_EncodingUtil.DecompressString(compressed, COMPRESSION_METHOD)
        return C_EncodingUtil.DeserializeCBOR(serialized)
    end)

    if not ok then
        return nil, result
    end
    return result
end

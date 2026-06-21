local _, addon = ...
local Colorizer = {}
addon.Colorizer = Colorizer

local function WrapText(color, text)
    return color and color:WrapTextInColorCode(text) or text
end

function Colorizer:ToAccent(text)
    return WrapText(addon.ACCENT_COLOR, text)
end

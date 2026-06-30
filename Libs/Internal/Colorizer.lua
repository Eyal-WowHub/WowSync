local _, addon = ...
local Colorizer = {}
addon.Colorizer = Colorizer

-- Wrap text in a color's escape codes; returns text unchanged when color is nil.
function Colorizer:Wrap(color, text)
    return color and color:WrapTextInColorCode(text) or text
end

local _, addon = ...

do
    -- [[ Branding ]]

    -- WowSync accent color (the "40a5f7" blue used in the addon title and chat prefix).
    addon.ACCENT_COLOR = CreateColorFromHexString("ff40a5f7")

    -- Warning yellow, used to tint the body of a chat warning (addon:Warn).
    addon.WARNING_COLOR = CreateColorFromHexString("ffffd100")
end

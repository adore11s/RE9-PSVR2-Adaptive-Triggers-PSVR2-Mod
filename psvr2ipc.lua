-- psvr2ipc.lua (v4.0)
-- Compatibility shim for the PSVR2 trigger bridge state JSON consumed by the external bridge.
-- This preserves the same state file shape used by the recovered adaptive trigger implementation.

local STATUS_FILE = "re9vr_state.json"

local function write_state(weapon_id, ammo, menu_open, reloading, melee_swinging, aiming, haptic_event)
    local f = io.open(STATUS_FILE, "wb")
    if not f then return end

    local json_str = string.format(
        '{"weapon":"%s","weaponClass":"Other","ammo":%d,"menuOpen":%s,"reloading":%s,"meleeSwingin":%s,"aiming":%s,"leftTrigger":0.0,"rightTrigger":0.0,"hapticEvent":"%s"}',
        weapon_id or "none",
        ammo or -1,
        menu_open and "true" or "false",
        reloading and "true" or "false",
        melee_swinging and "true" or "false",
        aiming and "true" or "false",
        haptic_event or "none"
    )
    f:write(json_str)
    f:close()
end

re.on_application_entry("BeforeApplicationQuit", function()
    write_state("disabled", -1, true, false, false, false, "none")
end)

write_state("arm0000", -1, false, false, false, false, "none")

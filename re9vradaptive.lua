-- re9vradaptive.lua (v4.0)
-- PSVR2 Adaptive Triggers - JSON Bridge Integration with Menu & Pause Detection
-- Writes weapon state to re9vr_state.json for PSVR2TriggerBridge.exe to read
-- Disables triggers when: menus open, pause menu active, or game exits

local STATUS_FILE = "re9vr_state.json"
local last_weapon_id = ""
local last_ammo = -1
local last_hand = "right"
local last_menu_open = false
local last_reloading = false
local last_melee_swinging = false
local last_aiming = false
local reload_debounce = 0
local frame_counter = 0

local WEAPON_ID_TO_CLASS = {
    -- Pistols
    arm0000 = "Pistol", arm0001 = "Pistol", arm0003 = "Pistol", arm0004 = "Pistol", arm0007 = "Pistol",
    -- Revolvers
    arm0005 = "Revolver", arm0006 = "Revolver",
    -- Longarms/Rifles/Shotguns
    arm0100 = "Shotgun", arm0103 = "Shotgun", arm0104 = "Shotgun",
    arm0500 = "AutoPistol", arm0501 = "AutoPistol", arm0503 = "AutoPistol", arm0505 = "AutoPistol", arm0550 = "SMG",
    arm0600 = "Rifle", arm0601 = "Rifle",
    arm0400 = "Shotgun",  -- Requiem
    arm0700 = "Shotgun",
    -- Grenades
    arm0200 = "Grenade", arm0202 = "Grenade", arm0203 = "Grenade", arm0204 = "Grenade", arm0207 = "Grenade",
    -- Melee
    arm0300 = "Melee", arm0303 = "Melee", arm0319 = "Melee", arm0335 = "Melee",
    arm0350 = "Melee", arm0351 = "Melee", arm0353 = "Melee", arm0354 = "Melee",
}

local function sc(obj, method, ...)
    if not obj then return nil end
    local ok, r = pcall(function(...) return obj:call(method, ...) end, ...)
    return ok and r or nil
end

-- Menu/UI/Pause detection: returns true if any menu is open or game is paused
local function is_menu_open()
    -- Check if game is paused (pause menu active)
    local is_paused = rawget(_G, "__vr_motion_paused") == true
    if is_paused then return true end

    -- Check if any UI menu is open (inventory, files, items, map, settings, etc.)
    local gm = sdk.get_managed_singleton("app.GuiManager")
    if not gm then return false end

    -- Check CurrentVisibleSituationType
    local ok, situation = pcall(gm.call, gm, "get_CurrentVisibleSituationType")
    if ok and situation ~= nil and situation ~= 0 then return true end

    -- Additional check: look for UI menu panel objects that are active
    pcall(function()
        -- Check if any menu bridge is active (inventory, map, files)
        local inv_bridge = gm:call("get_Inventory")
        if inv_bridge then
            local ok_active, is_active = pcall(inv_bridge.call, inv_bridge, "get_Active")
            if ok_active and is_active == true then return true end
        end

        local map_bridge = gm:call("get_Map")
        if map_bridge then
            local ok_active, is_active = pcall(map_bridge.call, map_bridge, "get_Active")
            if ok_active and is_active == true then return true end
        end
    end)

    return false
end

local function get_current_weapon_id()
    local ctx = sc(sdk.get_managed_singleton("app.CharacterManager"), "get_PlayerContextFast")
    if not ctx then return "none" end
    local upd = sc(ctx, "get_Updater")
    if not upd then return "none" end
    local equip = sc(upd, "get_Equipment")
    if not equip then return "none" end
    local wid = nil
    pcall(function()
        wid = equip:get_field("<EquipWeaponID>k__BackingField")
    end)
    if not wid then return "none" end
    local ok, s = pcall(wid.call, wid, "ToString")
    if ok and s and s ~= "Invalid" then return s end
    return "none"
end

local function get_current_ammo()
    local ammo = -1
    pcall(function()
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        if not cm then return end
        local ctx = sc(cm, "get_PlayerContextFast")
        if not ctx then return end
        local up = sc(ctx, "get_Updater")
        if not up then return end
        local w = sc(up, "get_EquipWeapon")
        if not w then return end

        -- Try private field first (_LoadedAmmoCount)
        local a = w:get_field("_LoadedAmmoCount")
        if a ~= nil then
            ammo = tonumber(a) or -1
            if ammo >= 0 then return end
        end

        -- Fall back to public field (LoadedAmmoCount)
        a = w:get_field("LoadedAmmoCount")
        if a ~= nil then
            ammo = tonumber(a) or -1
            if ammo >= 0 then return end
        end

        -- Try alternate field names for special cases like revolvers
        local fields_to_try = {"_LoadedAmmo", "LoadedAmmo", "Ammo", "_Ammo", "CurrentBulletCount", "_BulletCount"}
        for _, field_name in ipairs(fields_to_try) do
            a = w:get_field(field_name)
            if a ~= nil then
                ammo = tonumber(a) or -1
                if ammo >= 0 then return end
            end
        end

        -- Last resort: Get ammo from inventory system (works for all weapons including revolvers like arm0007)
        pcall(function()
            local user = sc(ctx, "get_InventoryUserID")
            if not user then return end
            local imgr = sdk.get_managed_singleton("app.InventoryManager")
            if not imgr then return end
            local inv = nil
            pcall(function()
                inv = imgr:call("getInventory(app.InventoryUser, app.InventoryType)", user, 0)
            end)
            if not inv then return end
            local panel = nil
            pcall(function()
                panel = inv:call("getEquipPanelState(app.InventoryEquipSlot, System.Boolean)", 0, false)
            end)
            if not panel then return end
            local loading = sc(panel, "get_LeadLoadingItem")
            if not loading then return end
            local loaded = nil
            pcall(function() loaded = loading:call("get_Stock") end)
            if loaded ~= nil then
                ammo = tonumber(loaded) or -1
                if ammo >= 0 then return end
            end
        end)

        -- If we still can't read ammo, return -1 (don't convert to 1)
        if ammo == -1 then
            ammo = -1
        end
    end)
    return ammo
end

local function is_reloading()
    local reloading = false
    pcall(function()
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        if not cm then return end
        local ctx = sc(cm, "get_PlayerContextFast")
        if not ctx then return end
        local up = sc(ctx, "get_Updater")
        if not up then return end
        local w = sc(up, "get_EquipWeapon")
        if not w then return end

        -- Check if weapon is currently in reload state
        -- Try isEnableReload or check for reload animation state
        local reload_state = w:get_field("<ReloadState>k__BackingField")
        if reload_state ~= nil then
            local state_val = tonumber(reload_state) or 0
            if state_val > 0 then reloading = true end
        end
    end)
    return reloading
end

local function is_melee_swinging()
    local swinging = false
    pcall(function()
        local cm = sdk.get_managed_singleton("app.CharacterManager")
        if not cm then return end
        local ctx = sc(cm, "get_PlayerContextFast")
        if not ctx then return end
        local up = sc(ctx, "get_Updater")
        if not up then return end
        local w = sc(up, "get_EquipWeapon")
        if not w then return end

        -- Check if weapon is a melee weapon by checking for melee-specific fields
        local melee_state = w:get_field("<MeleeAttackState>k__BackingField")
        if melee_state ~= nil then
            local state_val = tonumber(melee_state) or 0
            if state_val > 0 then swinging = true end
        end
    end)
    return swinging
end

local function is_right_grip_held()
    local grip_action = nil
    pcall(function() grip_action = vrmod:get_action_grip() end)
    if not grip_action then return false end

    local rj = nil
    pcall(function() rj = vrmod:get_right_joystick() end)
    if not rj then return false end

    local ok, is_active = pcall(function() return vrmod:is_action_active(grip_action, rj) end)
    return ok and is_active == true
end

local function is_aiming()
    -- Docked mode (one-handed with gun supported by hand)
    if (_G.__vr_support_docked == true) then
        return true
    end

    -- One-handed aiming: just check if grip button is held
    -- Be less strict - if holding gun, consider it aiming
    if is_right_grip_held() then
        return true
    end

    -- Also check if two-handed aiming is active (stabilizer animation)
    -- But only if explicitly aiming, not passive holding
    if (_G.__vr_two_hand_aiming_active == true) then
        return true
    end

    return false
end

local function write_state(weapon_id, ammo, menu_open, reloading, melee_swinging, aiming, haptic_event)
    local f = io.open(STATUS_FILE, "wb")
    if not f then return end

    -- Map weapon ID to class
    local weapon_class = WEAPON_ID_TO_CLASS[weapon_id] or "Other"

    -- Disable adaptive triggers for arm0300 and while menus are open
    local disable_adaptive_triggers = (weapon_id == "arm0300") or menu_open
    local output_weapon = disable_adaptive_triggers and "disabled" or weapon_id
    local json_str = string.format(
        '{"weapon":"%s","weaponClass":"%s","ammo":%d,"menuOpen":%s,"reloading":%s,"meleeSwingin":%s,"aiming":%s,"leftTrigger":0.0,"rightTrigger":0.0,"hapticEvent":"%s"}',
        output_weapon, weapon_class, ammo, menu_open and "true" or "false", reloading and "true" or "false", melee_swinging and "true" or "false", aiming and "true" or "false", haptic_event or "none"
    )
    f:write(json_str)
    f:close()
end

-- ────────────────────────────────────────────────────────────────────────────
-- PSVR2 HAPTIC FEEDBACK - Direct Vibration Through IPC
-- ────────────────────────────────────────────────────────────────────────────

local last_haptic_event = "none"
local last_haptic_event_time = 0
local haptic_event_persist_duration = 0.15  -- Persist events for 150ms to ensure Program.cs reads them

-- Get player health/vitality to detect damage/bleeding
local function get_player_health_state()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return {health = 100, max_health = 100, is_bleeding = false} end

    local ctx = sc(cm, "get_PlayerContextFast")
    if not ctx then return {health = 100, max_health = 100, is_bleeding = false} end

    local vital = sc(ctx, "get_Vital")
    if not vital then return {health = 100, max_health = 100, is_bleeding = false} end

    local hp = 100
    local max_hp = 100

    pcall(function()
        hp = tonumber(vital:get_field("_HP")) or 100
        max_hp = tonumber(vital:get_field("_MaxHP")) or 100
    end)

    return {health = hp, max_health = max_hp, is_bleeding = (hp < max_hp * 0.3)}
end

-- Track state changes to trigger appropriate haptics
local last_health = 100
local last_low_health_pulse_time = 0
local last_damage_time = 0

-- Trigger haptic event - write to JSON for Program.cs to read
local function trigger_haptic_event(event_type)
    last_haptic_event = event_type
end

-- Detect and trigger haptics on damage taken
local function update_damage_haptics()
    local health_state = get_player_health_state()
    local current_time = os.time()

    -- Trigger damage haptics when health decreases significantly
    if health_state.health < last_health - 5 and os.difftime(current_time, last_damage_time) > 0.3 then
        last_damage_time = current_time

        if health_state.is_bleeding then
            -- Major damage: strong impact feedback
            trigger_haptic_event("damage_major")
        else
            -- Minor damage: bite feedback
            trigger_haptic_event("damage_minor")
        end
    end

    -- Low health heartbeat pulse - ALWAYS CHECK
    if health_state.health < health_state.max_health * 0.35 then
        if os.difftime(current_time, last_low_health_pulse_time) > 0.8 then
            last_low_health_pulse_time = current_time
            trigger_haptic_event("heartbeat_fast")
        end
    elseif health_state.health < health_state.max_health * 0.5 then
        if os.difftime(current_time, last_low_health_pulse_time) > 1.2 then
            last_low_health_pulse_time = current_time
            trigger_haptic_event("heartbeat_slow")
        end
    end

    last_health = health_state.health
end

re.on_frame(function()
    frame_counter = frame_counter + 1
    if frame_counter < 3 then return end
    frame_counter = 0

    local weapon_id = get_current_weapon_id()
    local ammo = get_current_ammo()
    local menu_open = is_menu_open()
    local reloading = is_reloading()
    local melee_swinging = is_melee_swinging()
    local aiming = is_aiming()

    if weapon_id ~= last_weapon_id or ammo ~= last_ammo or menu_open ~= last_menu_open or reloading ~= last_reloading or melee_swinging ~= last_melee_swinging or aiming ~= last_aiming then
        last_weapon_id = weapon_id
        last_ammo = ammo
        last_menu_open = menu_open
        last_reloading = reloading
        last_melee_swinging = melee_swinging
        last_aiming = aiming
        write_state(weapon_id, ammo, menu_open, reloading, melee_swinging, aiming, last_haptic_event)
    end

    -- Update damage-based haptics every frame
    update_damage_haptics()

    -- Write state with current haptic event
    write_state(weapon_id, ammo, menu_open, reloading, melee_swinging, aiming, last_haptic_event)

    -- Clear haptic event after sending
    if last_haptic_event ~= "none" then
        last_haptic_event = "none"
    end
end)

-- Detect game exit and disable all triggers
re.on_application_entry("BeforeApplicationQuit", function()
    write_state("disabled", -1, true, false, false, false)
end)

write_state("arm0000", -1, false, false, false, false)

-- UI display showing weapon and ammo
re.on_draw_ui(function()
    if imgui.tree_node("RE9VR Adaptive Triggers") then
        local weapon_id = get_current_weapon_id()
        local ammo = get_current_ammo()
        local menu_open = is_menu_open()
        local is_paused = rawget(_G, "__vr_motion_paused") == true

        imgui.text("Weapon: " .. weapon_id)
        imgui.text("Ammo: " .. (ammo >= 0 and tostring(ammo) or "N/A"))
        imgui.text("Menu Open: " .. (menu_open and "YES" or "NO"))
        imgui.text("Paused: " .. (is_paused and "YES" or "NO"))

        local status_color = menu_open and 0xFF0000FF or 0xFF00FF00
        imgui.text_colored(status_color, "Triggers: " .. (menu_open and "DISABLED" or "ACTIVE"))

        imgui.tree_pop()
    end
end)

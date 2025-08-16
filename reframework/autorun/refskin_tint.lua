-- Require and aliases
local F = require("_SharedCore/Functions")
local D = log.debug
local H = sdk.hook
local M = function(type_name, method_name) return sdk.find_type_definition(type_name):get_method(method_name) end

-- Variables
local player_manager
local npc_manager
local loading_gui
local players = {}
local npcs = {}
local npcs_id = {}
local max_failed_count = 20
local player_failed_flag = 0
local npc_failed_flag = 0
local player_failed_cycles_skip = 0
local npc_failed_cycles_skip = 0
local frame_counter = 0
local is_exec_asap = false
local is_dirty = true
local is_dirty_npc = false
local is_loading = false
local is_title_scene = false
local is_hunter_only_scene = false
local hunter_only_scene_key = nil
local continuously_exec_frame_count = -1
local request_update = false
local is_null_or_empty = M("System.String", "IsNullOrEmpty(System.String)")

-- Entry
if reframework.get_game_name() ~= "mhwilds" then
    error("Not supported game \"" .. reframework.get_game_name() .. "\" (REFSKIN_tint)")
    return
end
D("--REFSKIN_tint loaded--")

-- Callbacks
local function noop(v) end
local function mark_dirty(exec_asap)
    is_dirty = true
    if exec_asap then is_exec_asap = true end
end
local function mark_dirty_hook(args)
    is_dirty = true
end

-- Init
local function load_managers()
    if player_manager == nil then player_manager = sdk.get_managed_singleton("app.PlayerManager") end
    if npc_manager == nil then npc_manager = sdk.get_managed_singleton("app.NpcManager") end
end
local function init()
    load_managers()
end

-- Hunter only scene
local function enter_hunter_only_scene(scene_key, exec_asap)
    if is_hunter_only_scene then return end
    is_hunter_only_scene = true
    hunter_only_scene_key = scene_key
    mark_dirty(exec_asap)
end
local function leave_hunter_only_scene(scene_key, exec_asap)
    if not is_hunter_only_scene or hunter_only_scene_key ~= scene_key then return end
    is_hunter_only_scene = false
    hunter_only_scene_key = nil
    mark_dirty(exec_asap)
end

-- Find / apply skin tone
local function get_face(player_object, is_npc)
    if player_object == nil then return nil end
    local transform
    local _, err = pcall(function() transform = player_object:get_Valid() and player_object:get_Transform() end)
    if err or not transform then return nil end
    if is_npc then
        local children = F.get_children(transform)
        if children then
            for i, child in pairs(children) do
                local child_object = child:get_GameObject()
                local name_partial = string.sub(child_object:get_Name(), 1, 6)
                if name_partial == "ch00_5" or name_partial == "ch00_9" then
                    return child_object
                end
            end
        end
        return nil 
    else
        local face_transform = transform:find("Player_Face")
        return face_transform and face_transform:get_GameObject()
    end
end
local function get_skin_tone(player_object, is_npc)
    if player_object == nil then return nil end

    local face = get_face(player_object, is_npc)
    local mesh = face and F.get_GameObjectComponent(face, "via.render.Mesh")
    if mesh == nil then return nil end
    local mat_count = mesh:get_MaterialNum()
    for j = 0, mat_count - 1 do
        local mat_name = mesh:getMaterialName(j)
        local mat_param = mesh:getMaterialVariableNum(j)
        
        if (mat_name == "face" or mat_name == "skin") and mat_param then
            for k = 0, mat_param - 1 do
                local mat_param_name = mesh:getMaterialVariableName(j, k)
                if mat_param_name == "AddColorUV" then
                    return mesh:getMaterialFloat4(j, k)
                end
            end
        end
    end
end
local function tint_skin_tone_game_object(game_object, skin_tone_vec)
    if skin_tone_vec == nil then return end
    local mesh = F.get_GameObjectComponent(game_object, "via.render.Mesh")
    
    if mesh == nil then return end
    local mat_count = mesh:get_MaterialNum()
    for j = 0, mat_count - 1 do
        local mat_name = mesh:getMaterialName(j)
        local mat_param = mesh:getMaterialVariableNum(j)

        if mat_name and mat_param and string.sub(mat_name, 1, 8) == "REFSKIN_" then
            for k = 0, mat_param - 1 do
                local mat_param_name = mesh:getMaterialVariableName(j, k)
                local mat_param_type = mesh:getMaterialVariableType(j, k)
                if mat_param_name == "AddColorUV" and mat_param_type == 4 then
                    mesh:setMaterialFloat4(j, k, skin_tone_vec)
                end
            end
        end
    end
end
local function tint_skin_tone(player_object, skin_tone_vec, is_npc)
    if player_object == nil then return true end
    if skin_tone_vec == nil then skin_tone_vec = get_skin_tone(player_object, is_npc) end
    if skin_tone_vec == nil then return is_npc end -- Return true for NPCs and false for players without skin tone specification.
    local transform = player_object:get_Valid() and player_object:get_Transform()
    local children = transform and F.get_children(transform)
    if children then
        for i, child in pairs(children) do
            local eq = child:get_GameObject()
            if eq and eq:get_Valid() then 
                tint_skin_tone_game_object(eq, skin_tone_vec)
            end
        end
    end
    return true
end

-- Players capturing
local function find_pl000(sub_id)
    local name = "Pl000_" .. string.format("%02d", sub_id)
    local scene = F.get_CurrentScene()
    local transform = scene:get_FirstTransform()
    while transform do
        local game_object = transform:get_GameObject()
        if game_object ~= nil and game_object:get_Name() == "ConstraintUniversalPositionRoot" then
            local pl000_transform = transform:find(name)
            if pl000_transform then
                return pl000_transform:get_GameObject()
            end
        end
        transform = transform:get_Next()
    end
end
local function dump_players()
    init()
    local p = 1
    
    if player_manager then
        local main_player = player_manager:getMasterPlayer()
        if not main_player or not main_player:get_CharacterValid() then return false end
        for i = 0, #player_manager._PlayerList - 1 do
            local player = player_manager._PlayerList[i]:get_PlayerInfo()
            if player:get_Valid() then
                local player_object = player:get_Object()
                if player_object then
                    players[p] = player_object
                    p = p + 1
                end
            end
        end
    end
    while #players > p do table.remove(players, p + 1) end
    dump_player_flag = 0
    return true
end
local function dump_npcs()
    init()
    local p = #npcs
    
    if npc_manager then
        for i = #npcs_id, 1, -1 do
            local npc_id = npcs_id[i]
            local npc = npc_manager:findNpcInfo_NpcId(npc_id)
            if npc and npc:get_CharacterValid() then
                local npc_object = npc:get_Object()
                if npc_object then
                    npcs[p] = npc_object
                    p = p + 1
                    table.remove(npcs_id, i)
                end
            end
        end
    end
    if #npcs_id > 0 then return false end
    return true
end

-- Executor
local function exec_title_scene()
    for i = 0, 1 do
        local hunter_object = find_pl000(i)
        if hunter_object then
            return tint_skin_tone(hunter_object)
        end
    end
    return false
end
local function exec_hunter_only_scene()
    local scene = F.get_CurrentScene()
    local hunter_object = F.get_GameObjects(scene, { hunter_only_scene_key .. "_HunterXX", hunter_only_scene_key .. "_HunterXY" })[1]
    if hunter_object == nil or not tint_skin_tone(hunter_object) then return false end
    local pl000 = find_pl000(0)
    return pl000 == nil or tint_skin_tone(pl000)
end


local function exec()
    if (not is_dirty and not is_dirty_npc) or is_loading then return false end
    local skip_player = player_failed_cycles_skip > 0
    local skip_npc = npc_failed_cycles_skip > 0

    local pl000_succeeded = false
    local player_succeeded = false
    local npc_succeeded = false

    -- worker
    if is_dirty then
        if skip_player then
            player_failed_cycles_skip = player_failed_cycles_skip - 1
        else
            if is_title_scene and not is_hunter_only_scene then
                player_succeeded = exec_title_scene()
            elseif is_hunter_only_scene then
                player_succeeded = exec_hunter_only_scene()
            else
                local pl000 = find_pl000(1)
                if pl000 then
                    pl000_succeeded = tint_skin_tone(pl000)
                end

                if dump_players() then
                    player_succeeded = true
                    for i = #players, 1, -1 do
                        if players[i] == nil or not players[i]:get_Valid() or tint_skin_tone(players[i]) then table.remove(players, i) end
                    end
                    player_succeeded = #players == 0
                end
            end
        end
    end
    if is_dirty_npc then
        if skip_npc then
            npc_failed_cycles_skip = npc_failed_cycles_skip - 1
        else
            npc_succeeded = dump_npcs()
            for i = #npcs, 1, -1 do
                if npcs[i] == nil or tint_skin_tone(npcs[i], nil, true) then table.remove(npcs, i) end
            end
            npc_succeeded = npc_succeeded and #npcs == 0
        end
    end

    -- checker
    if not skip_player then
        if pl000_succeeded or player_succeeded then
            player_failed_flag = 0
            is_dirty = false
        else
            player_failed_flag = player_failed_flag + 1
            if player_failed_flag > max_failed_count then
                player_failed_flag = 0
                is_dirty = false
            elseif player_failed_flag | 1 ~= player_failed_flag then
                -- penalty for every 2 failures
                player_failed_cycles_skip = player_failed_flag
            end
        end
    end
    if not skip_npc then
        if npc_succeeded then
            npc_failed_flag = 0
            is_dirty_npc = false
        else
            npc_failed_flag = npc_failed_flag + 1
            if npc_failed_flag > max_failed_count then
                npc_failed_flag = 0
                is_dirty_npc = false
            elseif npc_failed_flag | 1 ~= npc_failed_flag then
                -- penalty for every 2 failures
                npc_failed_cycles_skip = npc_failed_flag
            end
        end
    end

    return pl000_succeeded or player_succeeded or npc_succeeded
end

-- Hooks
-- -- Loading screen
H(M("app.GUI010000", "onOpen()"),
    function(args)
        loading_gui = sdk.to_managed_object(args[2])
        is_loading = true
    end
)
H(M("app.GUIBaseApp", "onCloseApp()"),
    function(args)
        if is_loading then
            local this = sdk.to_managed_object(args[2])
            local type_name = this and this:GetType():get_FullName()
            if type_name ~= "app.GUI010000" then return end
            is_loading = false
        end
    end
)
-- -- Title scene
H(M("app.TitleFieldSceneActivator", "update()"),
    noop,
    function(result)
        if is_title_scene then return end
        is_title_scene = true
        mark_dirty(true)
    end
)
H(M("app.TitleFieldSceneActivator", "onDestroy()"),
    noop,
    function(result)
        if not is_title_scene then return end
        is_title_scene = false
    end
)
-- -- Equipment select scene (Gemma)
H(M("app.GUI080000", "updateCurrentEquipData(app.EquipDef.EquipSet[], System.Boolean)"),
    noop,
    function(result)
        mark_dirty()
        request_update = true
    end
)
H(M("app.GUI080000", "updateCurrentEquipData(app.EquipDef.EquipSet, System.Boolean)"),
    noop,
    function(result)
        request_update = true
    end
)
H(M("app.GUI080000", "onClose()"),
    noop,
    mark_dirty_hook
)
H(M("app.mcDelayedCarry", "addItem(via.GameObject, via.GameObject, app.user_data.DelayedCarryData)"),
    noop,
    function(result)
        if request_update then mark_dirty(true) end
        request_update = false
    end
)
-- -- Equipment select scene (tent)
H(M("app.GUI080001", "updateEquipParts(app.EquipDef.EQUIP_INDEX)"),
    noop,
    function(result)
        request_update = true
    end
)
H(M("app.GUI080001", "onClose()"),
    noop,
    mark_dirty_hook
)
-- -- Equipment appearance scene (tent)
H(M("app.GUI080200HunterOverview", "callbackDecide(via.gui.Control, via.gui.SelectItem, System.UInt32)"),
    noop,
    function(result)
        request_update = true
    end
)
H(M("app.GUI080200HunterOverview", "updateValuesCore()"),
    noop,
    function(result)
        request_update = true
    end
)
H(M("app.GUI080200HunterOverview", "applyMyset(via.gui.SelectItem)"),
    noop,
    function(result)
        request_update = true
    end
)
-- -- Hunter edit scene
H(M("app.CharaMakeSceneController", "update()"),
    noop,
    function(result)
        enter_hunter_only_scene("CharaMake", true)
    end
)
H(M("app.CharaMakeSceneController", "onDestroy()"),
    noop,
    function(result)
        leave_hunter_only_scene("CharaMake", false)
    end
)
H(M("app.characteredit.protagonist.cUnderwear", "applyCore(app.characteredit.CharacterEditContext)"),
    noop,
    function(result)
        if is_hunter_only_scene and hunter_only_scene_key == "CharaMake" then
            mark_dirty()
        end
    end
)
H(M("app.characteredit.basic.cSkin.Editor", "set_ColorU(System.Single)"),
    function(args)
        if is_hunter_only_scene and hunter_only_scene_key == "CharaMake" and not is_dirty then
            local skin_editor = sdk.to_managed_object(args[2])
            if sdk.to_float(args[3]) == skin_editor:get_ColorU() then return end
            mark_dirty(true)
        end
    end
)
H(M("app.characteredit.basic.cSkin.Editor", "set_ColorV(System.Single)"),
    function(args)
        if is_hunter_only_scene and hunter_only_scene_key == "CharaMake" and not is_dirty then
            local skin_editor = sdk.to_managed_object(args[2])
            if sdk.to_float(args[3]) == skin_editor:get_ColorV() then return end
            mark_dirty(true)
        end
    end
)
-- -- Save data select scene
H(M("app.SaveSelectSceneController", "doStart()"),
    noop,
    function(result)
        enter_hunter_only_scene("SaveSelect", false)
    end
)
H(M("app.SaveSelectSceneController", "displaySaveCharacter()"),
    noop,
    function(result)
        enter_hunter_only_scene("SaveSelect", false)
    end
)
H(M("app.SaveSelectSceneController", "doOnDestroy()"),
    noop,
    function(result)
        leave_hunter_only_scene("SaveSelect", false)
    end
)
-- -- Hunter guild card scene
H(M("app.GuildCardSceneController", "start()"),
    function(args)
        enter_hunter_only_scene("GuildCard", false)
    end
)
H(M("app.GuildCardSceneController", "update()"),
    function(args)
        enter_hunter_only_scene("GuildCard", true)
    end
)
H(M("app.GuildCardSceneController", "exitEnd()"),
    function(args)
        leave_hunter_only_scene("GuildCard", false)
    end
)
-- -- NPC manager
H(M("app.NpcManager", "bindGameObject(via.GameObject, app.cNpcContextHolder)"),
    function(args)
        is_dirty_npc = true
        local npc_context_holder = sdk.to_managed_object(args[4])
        local npc_id = npc_context_holder:get_Npc().NpcID
        for _, _id in ipairs(npcs_id) do
            if npc_id == _id then return end
        end
        npcs_id[#npcs_id + 1] = npc_id
    end
)

-- -- Player manager
H(M("app.PlayerManager", "bindGameObject(via.GameObject, app.cPlayerContextHolder)"),
    mark_dirty_hook
)

--
re.on_frame(function()
    if frame_counter == 0 or is_exec_asap or continuously_exec_frame_count >= 0 then exec() end
    frame_counter = frame_counter + 1
    if frame_counter >= 30 then frame_counter = 0 end
    if continuously_exec_frame_count >= 0 then
        continuously_exec_frame_count = continuously_exec_frame_count - 1
        if continuously_exec_frame_count >= 0 and math.fmod(continuously_exec_frame_count, 30) == 0 then mark_dirty() end
    end
    is_exec_asap = false
end)
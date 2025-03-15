-- Require and aliases
local F = require("_SharedCore/Functions")
local D = log.debug
local H = sdk.hook
local M = function(type_name, method_name) return sdk.find_type_definition(type_name):get_method(method_name) end

-- Variables
local player_manager
local npc_manager
local players = {}
local npcs = {}
local npcs_id = {}
local frame_counter = 0
local is_exec_asap = false
local is_dirty = true
local is_loading = false
local is_loading_screen_updater = false
local is_title_scene = false
local is_hunter_only_scene = false
local hunter_only_scene_key = nil
local continuously_exec_frame_count = -1

-- Entry
if reframework.get_game_name() ~= "mhwilds" then
    error("Not supported game \"" .. reframework.get_game_name() .. "\" (REFSKIN_tint)")
    return
end
D("--REFSKIN_tint loaded--")

-- Callbacks
local function noop(v) return v end
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
    if is_hunter_only_scene and hunter_only_scene_key == scene_key then return end
    if is_title_scene then is_title_scene = false end
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
            if player:get_CharacterValid() then
                local player_object = player:get_Object()
                if player_object then
                    players[p] = player_object
                    p = p + 1
                end
            end
        end
    end
    if npc_manager then
        for _, npc_id in ipairs(npcs_id) do
            local npc = npc_manager:findNpcInfo_NpcId(npc_id)
            if npc and npc:get_CharacterValid() then
                local npc_object = npc:get_Object()
                if npc_object then
                    players[p] = npc_object
                    p = p + 1
                end
            end
        end
    end
    while #players > p do
        table.remove(players, p + 1)
    end
    return true
end
local function is_npc(player_object)
    local tag
    local _, err = pcall(function() tag = player_object:get_Tag() end) 
    return err == nil and tag and string.find(tag, "NPC")
end

-- Skin tone finding / tinting
local function get_face(player_object)
    local transform = player_object:get_Valid() and player_object:get_Transform()
    if not transform then return nil end
    if is_npc(player_object) then
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
local function get_skin_tone_player_object(player_object)
    if player_object == nil then return nil end

    local face = get_face(player_object)

    if face then
        local mesh = F.get_GameObjectComponent(face, "via.render.Mesh")
        if mesh then
            local mat_count = mesh:get_MaterialNum()
            for j = 0, mat_count - 1 do
                local mat_name = mesh:getMaterialName(j)
                local mat_name_partial = string.sub(mat_name, 1, 6)
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
    end
end
local function tint_skin_tone_game_object(game_object, skin_tone_vec)
    if skin_tone_vec == nil then return end
    local mesh = F.get_GameObjectComponent(game_object, "via.render.Mesh")
    
    if mesh then
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
end
local function tint_skin_tone_player_object(player_object, skin_tone_vec)
    if skin_tone_vec == nil then skin_tone_vec = get_skin_tone_player_object(player_object) end
    if skin_tone_vec == nil then return is_npc(player_object) end -- Return true for NPCs and false for players without skin tone specification.
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

-- Executor
local function exec_title_scene()
    for i = 0, 1 do
        local hunter_object = find_pl000(i)
        if hunter_object then
            return tint_skin_tone_player_object(hunter_object)
        end
    end
    return false
end
local function exec_hunter_only_scene()
    local scene = F.get_CurrentScene()
    local hunter_object = F.get_GameObjects(scene, { hunter_only_scene_key .. "_HunterXX", hunter_only_scene_key .. "_HunterXY", hunter_only_scene_key .. "_Hunter" })[1]
    local result = false
    if hunter_object then
        if tint_skin_tone_player_object(hunter_object) then result = true end
    end
    local pl000 = find_pl000(0)
    if pl000 then
        if tint_skin_tone_player_object(pl000) and result then result = true end
    end
    return result
end

local function exec()
    if not is_dirty or is_loading then return false end
    if is_title_scene and not is_hunter_only_scene then
        if not exec_title_scene() then return false end
    elseif is_hunter_only_scene then
        if not exec_hunter_only_scene() then return false end
    else
        local pl000_succeeded = false
        local player_succeeded = false

        local pl000 = find_pl000(1)
        if pl000 then
            pl000_succeeded = tint_skin_tone_player_object(pl000)
        end

        if dump_players() then
            player_succeeded = true
            for i = 1, #players do
                if players[i] then 
                    if not tint_skin_tone_player_object(players[i]) then player_succeeded = false end
                end
            end
        end
        if not pl000_succeeded and not player_succeeded then return false end
    end
    is_dirty = false
    return true
end

-- Hooks
-- -- Loading screen
H(M("app.GUI010000", "guiLateUpdate()"),
    function(args)
        local GUI010000 = sdk.to_managed_object(args[2])
        if GUI010000._Param:getValue() == 90.0 then
            is_loading = true
        else
            if is_loading then is_dirty = true end
            is_loading = false
        end
    end
)
-- -- Title scene
H(M("app.TitleFieldSceneActivator", "update()"),
    noop,
    function(args)
        if is_title_scene then return end
        is_title_scene = true
        mark_dirty(true)
    end
)
H(M("app.TitleFieldSceneActivator", "onDestroy()"),
    noop,
    function(args)
        if not is_title_scene then return end
        is_title_scene = false
        mark_dirty()
    end
)
-- -- Equipment select scene (Gemma)
H(M("app.GUI080000", "updateCurrentEquipData(app.EquipDef.EquipSet[], System.Boolean)"),
    noop,
    function(args)
        mark_dirty()
        -- It has delay between updateEquipData() executed and selected armor shown in equipment edit scene 
        -- to make animation works and I cannot locate the function of show newly selected armor.
        -- Make it work continuously for about 1-5 seconds for now.
        continuously_exec_frame_count = 120
    end
)
H(M("app.GUI080000", "updateCurrentEquipData(app.EquipDef.EquipSet, System.Boolean)"),
    noop,
    function(args)
        mark_dirty()
        continuously_exec_frame_count = 120
    end
)
H(M("app.GUI080000", "onClose()"),
    noop,
    mark_dirty_hook
)
-- -- Equipment select scene (tent)
H(M("app.GUI080001", "updateEquipParts(app.EquipDef.EQUIP_INDEX)"),
    noop,
    function(args)
        mark_dirty()
        continuously_exec_frame_count = 120
    end
)
H(M("app.GUI080001", "onClose()"),
    noop,
    mark_dirty_hook
)
-- -- Equipment appearance scene (tent)
H(M("app.GUI080200", "get_ID()"),
    noop,
    function(args)
        mark_dirty()
        continuously_exec_frame_count = 120
    end
)
-- -- Hunter edit scene
H(M("app.CharaMakeSceneController", "update()"),
    noop,
    function(args)
        enter_hunter_only_scene("CharaMake", true)
    end
)
H(M("app.CharaMakeSceneController", "onDestroy()"),
    noop,
    function(args)
        leave_hunter_only_scene("CharaMake", false)
    end
)
H(M("app.characteredit.basic.cSkin.Editor", "set_ColorU(System.Single)"),
    function(args)
        if is_hunter_only_scene and hunter_only_scene_key == "CharaMake" then 
            mark_dirty(true)
        end
    end
)
H(M("app.characteredit.basic.cSkin.Editor", "set_ColorV(System.Single)"),
    function(args)
        if is_hunter_only_scene and hunter_only_scene_key == "CharaMake" then 
            mark_dirty(true)
        end
    end
)
-- -- Save data select scene
H(M("app.SaveSelectSceneController", "doStart()"),
    noop,
    function(args)
        enter_hunter_only_scene("SaveSelect", false)
    end
)
H(M("app.SaveSelectSceneController", "update()"),
    noop,
    function(args)
        enter_hunter_only_scene("SaveSelect", true)
    end
)
H(M("app.SaveSelectSceneController", "doOnDestroy()"),
    noop,
    function(args)
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
        mark_dirty()
        local npc_context_holder = sdk.to_managed_object(args[4])
        local npc_id = sdk.to_managed_object(args[4]):get_Npc().NpcID
        for _, _id in ipairs(npcs_id) do
            if npc_id == _id then return end
        end
        npcs_id[#npcs_id + 1] = npc_id
    end
)
H(M("app.NpcManager", "unbindGameObject(via.GameObject, app.cNpcContextHolder)"),
    function(args)
        for _i, _id in ipairs(npcs_id) do
            if npc_id == _id then
                table.remove(npcs_id, _i)
                return
            end
        end
    end
)
-- -- Player manager
H(M("app.PlayerManager", "bindGameObject(via.GameObject, app.cPlayerContextHolder)"),
    mark_dirty_hook
)
H(M("app.PlayerManager", "unbindGameObject(via.GameObject, app.cPlayerContextHolder)"),
    mark_dirty_hook
)

--
re.on_frame(function()
    if frame_counter == 0 or is_exec_asap or (continuously_exec_frame_count >= 0 and math.fmod(continuously_exec_frame_count, 16) == 0) then exec() end
    frame_counter = math.fmod(frame_counter + 1, 16)
    if continuously_exec_frame_count >= 0 then 
        continuously_exec_frame_count = continuously_exec_frame_count - 1
        if continuously_exec_frame_count >= 0 then mark_dirty() end
    end
    is_exec_asap = false
end)
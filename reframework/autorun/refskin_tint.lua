local func = require("_SharedCore/Functions")

local player_manager
local npc_manager
local players = {}
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

log.debug("--REFSKIN_tint loaded--")

local function load_managers()
    if player_manager == nil then player_manager = sdk.get_managed_singleton("app.PlayerManager") end
    if npc_manager == nil then npc_manager = sdk.get_managed_singleton("app.NpcManager") end
end
local function init()
    load_managers()
end

local function debug_traverse_transform(transform, indent)
    local game_object = transform:get_GameObject()
    if game_object == nil then return false end
    local name = game_object:get_Name()
    if game_object then log.debug(string.rep("  ", indent) .. name .. ": " .. game_object:get_Tag()) end
    local children = func.get_children(transform)
    if children then
        for _, child in ipairs(children) do
            debug_traverse_transform(child, indent + 1)
        end
    end
end

local function dump_players()
    init()
    local c = 1
    
    if player_manager then
        local main_player = player_manager:getMasterPlayer()
        if not main_player or not main_player:get_CharacterValid() then return false end
        for i = 0, #player_manager._PlayerList - 1 do
            local player = player_manager._PlayerList[i]:get_PlayerInfo() -- app.cPlayerManageInfo
            if player:get_CharacterValid() then
                local player_object = player:get_Object()
                if player_object then
                    players[c] = player_object
                    c = c + 1
                end
            end
        end
    end
    if npc_manager then
        for _, npc_id in ipairs(npcs_id) do
            local npc = npc_manager:findNpcInfo_NpcId(npc_id) -- app.cNpcManageInfo
            if npc and npc:get_CharacterValid() then
                local npc_object = npc:get_Object()
                if npc_object then
                    players[c] = npc_object
                    c = c + 1
                end
            end
        end
    end
    while #players > c do
        table.remove(players, c + 1)
    end
    return true
end
local function get_face(player_object)
    local is_npc = string.find(player_object:get_Tag(), "NPC")
    local transforms = player_object:get_Valid() and player_object:get_Transform()
    if not transforms then return nil end
    if is_npc then
        local children = func.get_children(transforms)
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
        local face_transform = transforms:find("Player_Face")
        return face_transform and face_transform:get_GameObject()
    end
end
local function get_skin_tone_player_object(player_object)
    if player_object == nil then return nil end

    local face = get_face(player_object)

    if face then
        local mesh = func.get_GameObjectComponent(face, "via.render.Mesh")
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
                -- if (mat_name == "ch00_5" or mat_name == "ch00_9") and mat_param then
                --     -- for k = 0, mat_param - 1 do
                --     --     local mat_param_name = mesh:getMaterialVariableName(j, k)
                --     --     if mat_param_name == "AddColorUV" then
                --     --         return mesh:getMaterialFloat4(j, k)
                --     --     end
                --     -- end
                --     log.debug("bypass now")
                -- end
            end
        end
    end
end
local function tint_skin_tone_game_object(game_object, skin_tone_vec)
    if skin_tone_vec == nil then return end
    local mesh = func.get_GameObjectComponent(game_object, "via.render.Mesh")
    
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
    if skin_tone_vec == nil then
        log.debug("No skin tone applied")
        return
    end
    local transforms = player_object:get_Valid() and player_object:get_Transform()
    local children = transforms and func.get_children(transforms)
    if children then
        for i, child in pairs(children) do
            local eq = child:get_GameObject()

            if eq and eq:get_Valid() then 
                tint_skin_tone_game_object(eq, skin_tone_vec)
            end
        end
    end
end
local function tint_skin_tone(player, skin_tone_vec)
    local player_object = player and player:get_Valid() and player:get_Object()
    if player_object then tint_skin_tone_player_object(player_object, skin_tone_vec) end
end
local function tint_skin_tone_hunter_object(hunter_object, skin_tone_vec)
    -- local chara = player:get_Character() -- app.HunterCharacter

    -- for i = 1, 6 do
    --     local game_object = chara:getParts(i - 1)
    --     tint_skin_tone_game_object(game_object, skin_tone_vec)
    -- end
    tint_skin_tone_player_object(hunter_object, skin_tone_vec)
end

local function exec_title_scene()
    local scene = func.get_CurrentScene()
    local subtransform = scene:get_FirstTransform()
    while subtransform do
        local subtransform_object = subtransform:get_GameObject()
        if subtransform_object ~= nil and subtransform_object:get_Name() == "ConstraintUniversalPositionRoot" then
            local hunter_transform = subtransform:find("Pl000_00") or subtransform:find("Pl000_01")
            if hunter_transform then
                local hunter_object = hunter_transform:get_GameObject()
                local skin_tone_vec = get_skin_tone_player_object(hunter_object)
                if hunter_object then
                    tint_skin_tone_hunter_object(hunter_object, skin_tone_vec)
                else
                    return false
                end
                return true
            end
        end
        subtransform = subtransform:get_Next()
    end
    return false
end
local function exec_hunter_only_scene()
    local scene = func.get_CurrentScene()
    local hunter_object = func.get_GameObjects(scene, { hunter_only_scene_key .. "_HunterXX", hunter_only_scene_key .. "_HunterXY", hunter_only_scene_key .. "_Hunter" })[1]
    local skin_tone_vec = get_skin_tone_player_object(hunter_object)
    if hunter_object then
        tint_skin_tone_hunter_object(hunter_object, skin_tone_vec)
    else
        return false
    end
    return true
end
local function exec()
    if not is_dirty or is_loading then return false end
    if is_title_scene and not is_hunter_only_scene then
        if not exec_title_scene() then return false end
    elseif is_hunter_only_scene then
        if not exec_hunter_only_scene() then return false end
    else
        if not dump_players() then return false end
        local failed = false
        for i = 1, #players do
            if players[i] then 
                if not tint_skin_tone_player_object(players[i]) then failed = false end
            end
        end
        if failed then return false end
    end
    is_dirty = false
    return true
end

local function enter_hunter_only_scene(scene_key, exec_asap)
    if is_hunter_only_scene and hunter_only_scene_key == scene_key then return end
    if is_title_scene then is_title_scene = false end
    is_dirty = true
    is_hunter_only_scene = true
    hunter_only_scene_key = scene_key
    if exec_asap then is_exec_asap = exec_asap end
end
local function leave_hunter_only_scene(scene_key, exec_asap)
    if not is_hunter_only_scene or hunter_only_scene_key ~= scene_key then return end
    is_dirty = true
    is_hunter_only_scene = false
    hunter_only_scene_key = nil
    if exec_asap then is_exec_asap = exec_asap end
end

-- Hooks
if reframework.get_game_name() == "mhwilds" then
    -- Loading screen
    sdk.hook(sdk.find_type_definition("app.GUI010000"):get_method("guiLateUpdate()"),
        function(args)
            local GUI010000 = sdk.to_managed_object(args[2])
            if GUI010000._Param:getValue() == 90.0 then
                is_loading = true
            else
                is_loading = false
                is_loading_screen_updater = false
                is_dirty = true
            end
        end,
        function(retval)
            return retval
        end
    )
    -- Title scene
    sdk.hook(sdk.find_type_definition("app.TitleFieldSceneActivator"):get_method("update()"),
        function(retval)
            return retval
        end,
        function(args)
            if is_title_scene then return end
            is_title_scene = true
            is_dirty = true
            is_exec_asap = true
        end
    )
    sdk.hook(sdk.find_type_definition("app.TitleFieldSceneActivator"):get_method("onDestroy()"),
        function(retval)
            return retval
        end,
        function(args)
            if not is_title_scene then return end
            is_title_scene = false
            is_dirty = true
        end
    )
    -- Equipment select scene (Gemma)
    sdk.hook(sdk.find_type_definition("app.GUI080000"):get_method("updateCurrentEquipData(app.EquipDef.EquipSet[], System.Boolean)"),
        function(retval)
            return retval
        end,
        function(args)
            is_dirty = true
            is_exec_asap = true
            -- It has delay between updateEquipData() executed and selected armor shown in equipment edit scene 
            -- to make animation works and I cannot locate the function of show newly selected armor.
            -- Make it work continuously for about 3-10 seconds for now.
            continuously_exec_frame_count = 300
        end
    )
    sdk.hook(sdk.find_type_definition("app.GUI080000"):get_method("updateCurrentEquipData(app.EquipDef.EquipSet, System.Boolean)"),
        function(retval)
            return retval
        end,
        function(args)
            is_dirty = true
            is_exec_asap = true
            continuously_exec_frame_count = 300
        end
    )
    sdk.hook(sdk.find_type_definition("app.GUI080000"):get_method("onClose()"),
        function(retval)
            return retval
        end,
        function(args)
            is_dirty = true
        end
    )
    -- Equipment select scene (tent)
    sdk.hook(sdk.find_type_definition("app.GUI080001"):get_method("updateEquipParts(app.EquipDef.EQUIP_INDEX)"),
        function(retval)
            return retval
        end,
        function(args)
            is_dirty = true
            is_exec_asap = true
            continuously_exec_frame_count = 300
        end
    )
    sdk.hook(sdk.find_type_definition("app.GUI080001"):get_method("onClose()"),
        function(retval)
            return retval
        end,
        function(args)
            is_dirty = true
        end
    )
    -- Hunter edit scene
    sdk.hook(sdk.find_type_definition("app.CharaMakeSceneController"):get_method("update()"),
        function(retval)
            return retval
        end,
        function(args)
            enter_hunter_only_scene("CharaMake", true)
        end
    )
    sdk.hook(sdk.find_type_definition("app.CharaMakeSceneController"):get_method("onDestroy()"),
        function(retval)
            return retval
        end,
        function(args)
            leave_hunter_only_scene("CharaMake", false)
        end
    )
    sdk.hook(sdk.find_type_definition("app.characteredit.basic.cSkin.Editor"):get_method("set_ColorU(System.Single)"),
        function(args)
            if is_hunter_only_scene and hunter_only_scene_key == "CharaMake" then 
                is_dirty = true 
                is_exec_asap = true
            end
        end
    )
    sdk.hook(sdk.find_type_definition("app.characteredit.basic.cSkin.Editor"):get_method("set_ColorV(System.Single)"),
        function(args)
            if is_hunter_only_scene and hunter_only_scene_key == "CharaMake" then 
                is_dirty = true 
                is_exec_asap = true
            end
        end
    )
    -- Save data select scene
    sdk.hook(sdk.find_type_definition("app.SaveSelectSceneController"):get_method("doStart()"),
        function(retval)
            return retval
        end,
        function(args)
            enter_hunter_only_scene("SaveSelect", false)
        end
    )
    sdk.hook(sdk.find_type_definition("app.SaveSelectSceneController"):get_method("update()"),
        function(retval)
            return retval
        end,
        function(args)
            enter_hunter_only_scene("SaveSelect", true)
        end
    )
    sdk.hook(sdk.find_type_definition("app.SaveSelectSceneController"):get_method("doOnDestroy()"),
        function(retval)
            return retval
        end,
        function(args)
            leave_hunter_only_scene("SaveSelect", false)
        end
    )
    -- Hunter guild card scene
    sdk.hook(sdk.find_type_definition("app.GuildCardSceneController"):get_method("start()"),
        function(args)
            enter_hunter_only_scene("GuildCard", false)
        end
    )
    sdk.hook(sdk.find_type_definition("app.GuildCardSceneController"):get_method("update()"),
        function(args)
            enter_hunter_only_scene("GuildCard", true)
        end
    )
    sdk.hook(sdk.find_type_definition("app.GuildCardSceneController"):get_method("exitEnd()"),
        function(args)
            leave_hunter_only_scene("GuildCard", false)
        end
    )
    -- NPC manager
    sdk.hook(sdk.find_type_definition("app.NpcManager"):get_method("bindGameObject(via.GameObject, app.cNpcContextHolder)"),
        function(args)
            is_dirty = true
            local npc_context_holder = sdk.to_managed_object(args[4])
            local npc_id = sdk.to_managed_object(args[4]):get_Npc().NpcID
            for _, _id in ipairs(npcs_id) do
                if npc_id == _id then return end
            end
            npcs_id[#npcs_id + 1] = npc_id
        end
    )
    sdk.hook(sdk.find_type_definition("app.NpcManager"):get_method("unbindGameObject(via.GameObject, app.cNpcContextHolder)"),
        function(args)
            for _i, _id in ipairs(npcs_id) do
                if npc_id == _id then
                    table.remove(npcs_id, _i)
                    return
                end
            end
        end
    )
    -- Player manager
    sdk.hook(sdk.find_type_definition("app.PlayerManager"):get_method("bindGameObject(via.GameObject, app.cPlayerContextHolder)"),
        function(args)
            is_dirty = true
        end
    )
    sdk.hook(sdk.find_type_definition("app.PlayerManager"):get_method("unbindGameObject(via.GameObject, app.cPlayerContextHolder)"),
        function(args)
            is_dirty = true
        end
    )
end

re.on_frame(function()
    if frame_counter == 0 or is_exec_asap or continuously_exec_frame_count >= 0 then exec() end
    frame_counter = math.fmod(frame_counter + 1, 16)
    if continuously_exec_frame_count >= 0 then 
        continuously_exec_frame_count = continuously_exec_frame_count - 1
        if continuously_exec_frame_count >= 0 then is_dirty = true end
    end
    is_exec_asap = false
end)
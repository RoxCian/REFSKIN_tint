local func = require("_SharedCore/Functions")

local player_manager
local npc_manager

local function load_managers()
    if player_manager == nil then player_manager = sdk.get_managed_singleton("app.PlayerManager") end
    if npc_manager == nil then npc_manager = sdk.get_managed_singleton("app.NpcManager") end
end
local function init()
    load_managers()
end
local players = {}
local function dump_players()
    init()
    local c = 1
    
    if player_manager then
        for i = 0, #player_manager._PlayerList - 1 do
            local player = player_manager._PlayerList[i]:get_PlayerInfo() -- app.cPlayerManageInfo
            if (player:get_CharacterValid()) then
                players[c] = player
                c = c + 1
            end
        end
    end
    -- if npc_manager then
    --     for local i = 0 to npc_manager:_npcList:get_Count() do
    --         local npc = npc_manager:_npcList[i] /* app.cNpcManageInfo */
    --         if (npc:get_CharacterValid()) then
    --             players[c] = npc:get_NpcCtrl():get_Character()
    --             c++
    --         end
    --     end
    -- end
    while #players > c do
        table.remove(players, c + 1)
    end
end

local function get_skin_tone(player)
    local transforms = player and player:get_Valid() and player:get_Object():get_Transform()
    
    if transforms then
        local face = transforms:find("Player_Face"):get_GameObject()

        if face then
            local mesh = func.get_GameObjectComponent(face, "via.render.Mesh")
            if mesh then
                local mat_count = mesh:get_MaterialNum()
                for j = 0, mat_count - 1 do
                    local mat_name = mesh:getMaterialName(j)
                    local mat_param = mesh:getMaterialVariableNum(j)
                    
                    
                    if mat_name == "face" and mat_param then
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
end

local function tint_skin_tone(player)
    local chara = player:get_Character() -- app.HunterCharacter
    local parts = { chara:getParts(0), chara:getParts(1), chara:getParts(2), chara:getParts(3), chara:getParts(4), chara:getParts(5) }

    local skin_tone_vec = get_skin_tone(player)
    local scene = func.get_CurrentScene()

    for i = 1, 6 do
        local game_object = parts[i]
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
end

re.on_frame(function ()
    if reframework.get_game_name() == "mhwilds" then
        dump_players()
        for i = 1, #players do
            if players[i] then 
                tint_skin_tone(players[i])
            end
        end
    end
end)
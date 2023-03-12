local hboxes = {} -- in lua api
hboxes["head"]            = 0
hboxes["neck"]            = 1
hboxes["pelvis"]          = 2
hboxes["stomach"]         = 3
hboxes["lower_chest"]     = 4
hboxes["chest"]           = 5
hboxes["upper_chest"]     = 6
hboxes["left_thigh"]      = 7
hboxes["right_thigh"]     = 8
hboxes["left_calf"]       = 9
hboxes["right_calf"]      = 10
hboxes["left_foot"]       = 11
hboxes["right_foot"]      = 12
hboxes["left_hand"]       = 13
hboxes["right_hand"]      = 14
hboxes["left_upper_arm"]  = 15
hboxes["left_forearm"]    = 16
hboxes["right_upper_arm"] = 17
hboxes["right_forearm"]   = 18

-- ui
local ui_dormant             = ui.create("Dormant Aimbot")
local ui_dormant_switch      = ui_dormant:switch("Dormant Aimbot", false)

local ui_settings            = ui.create("Settings")
local ui_settings_hitboxes   = ui_settings:selectable("Hitboxes", "Head", "Chest", "Stomach", "Arms", "Legs", "Feet")

local ui_settings_mindmg     = ui_settings:slider("Minimum Damage", 1, 100, 1)
local ui_settings_hitchance  = ui_settings:slider("Hitchance", 1, 100, 70)
local ui_settings_valid_time = ui_settings:slider("Dormant Valid Time", 0, 500, 50, 0.01, "s")

local ui_accuracy            = ui.create("Accuracy")
local ui_accuracy_autoscope  = ui_accuracy:switch("Auto Scope", false)
local ui_accuracy_autostop   = ui_accuracy:switch("Auto Stop", false)
local ui_accuracy_velfix     = ui_accuracy:switch("Velocity Fix", false)

local ui_misc                = ui.create("Misc")
local ui_misc_logs           = ui_misc:switch("Logs", false)
local ui_misc_debug_mode     = ui_misc:switch("Debug mode", false)

local dormant_aimbot = new_class()
    :struct 'consts' {
        WEAPONTYPE_UNKNOWN 	     = -1,
        WEAPONTYPE_KNIFE   	     = 0,
        WEAPONTYPE_PISTOL        = 1,
        WEAPONTYPE_SUBMACHINEGUN = 2,
        WEAPONTYPE_RIFLE         = 3,
        WEAPONTYPE_SHOTGUN       = 4,
        WEAPONTYPE_SNIPER_RIFLE  = 5,
        WEAPONTYPE_MACHINEGUN    = 6,
        WEAPONTYPE_C4            = 7,
        WEAPONTYPE_TASER         = 8,
        WEAPONTYPE_GRENADE       = 9,
        WEAPONTYPE_HEALTHSHOT 	 = 11,

        hbox_radius              = { 4.2, 3.5, 6.0, 6.0, 6.5, 6.2, 5.0, 5.0, 5.0, 4.0, 4.0, 3.6, 3.7, 4.0, 4.0, 3.3, 3.0, 3.3, 3.0 },
        hitgroup_str             = { [0] = "generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "generic", "gear" }
    }
    -- :struct 'aimbot_shot' {
    --     tickcount = nil,
    --     victim    = nil,
    --     hitchance = nil,
    --     hitgroup  = nil,
    --     damage    = nil,
    --     point     = nil,
    --     handled   = nil
    -- }
    :struct 'player_info' {
        last_origin_pos = {},
        last_velocity   = {},
        tickcount       = {},
        is_valid        = {},
        misscount       = {}
    }
    :struct 'variables' {
        hbox_state       = { false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false },
        is_reachable     = {},
        
        cmd              = nil,
        lp               = nil,
        eyepos           = nil,

        weapon           = nil,
        weapon_info      = nil,
        weapon_type      = nil,
        range_modifier   = nil,

        camera_position  = nil,
        camera_direction = nil,

        mindmg           = nil,
        minhc            = nil,

        dmg              = nil,
        hbox             = nil,

        initialize       = function(self, cmd)
            self.cmd              = cmd
            self.lp               = entity.get_local_player()
            self.eyepos           = self.lp:get_eye_position()

            self.weapon           = self.lp:get_player_weapon()
            self.weapon_info      = self.weapon:get_weapon_info()
            self.weapon_type      = self.weapon_info["weapon_type"]
            self.range_modifier   = self.weapon_info["range_modifier"]

            self.camera_position  = render.camera_position()
            self.camera_direction = vector():angles(render.camera_angles())

            self.mindmg           = ui_settings_mindmg:get()
            self.minhc            = ui_settings_hitchance:get()
        end
    }
    :struct 'aimbot' {
        lp_check = function(self) 
            if not globals.is_connected then
                return false
            end
            if not globals.is_in_game then
                return false
            end

            return true
        end,

        target_check = function(self, target)
            if target == nil then
                return false
            end
            
            if not target:is_alive() then
                return false
            end

            if self.variables.lp:get_origin():dist(target:get_origin()) > self.variables.weapon_info["range"] then -- out of weapon's range
                return false
            end
    
            if target:get_network_state() == 0 then -- not dormant
                return false
            end

            if target:get_network_state() == 5 then -- dormant is outdated
                return false
            end
            
            return true
        end,
    
        weapon_check = function(self)
            if self.variables.weapon == nil then
                return false
            end
    
            if self.variables.weapon_type == nil or self.variables.weapon_type == self.consts.WEAPONTYPE_KNIFE or self.variables.weapon_type >= self.consts.WEAPONTYPE_C4 then
                return false
            end

            if self.variables.weapon:get_weapon_reload() ~= -1 then -- is reloading
                return false
            end
    
            if math.max(self.variables.lp["m_flNextAttack"], self.variables.weapon["m_flNextPrimaryAttack"]) > globals.curtime then
                return false
            end

            return true
        end,

        get_hitgroup_index = function(self, hbox)
            if hbox == 1 then
                return 1
            end
            if hbox == 2 then
                return 8
            end
            if 3 <= hbox and hbox <= 4 then
                return 3
            end
            if 5 <= hbox and hbox <= 7 then
                return 2
            end
            if 8 <= hbox and hbox <= 13 then
                if hbox % 2 == 0 then
                    return 6
                else
                    return 7
                end
            end
            if 14 <= hbox and hbox <= 19 then
                if hbox % 2 == 1 then
                    return 4
                else
                    return 5
                end
            end

            return 0 -- a little bit incorrect but who cares?
        end,

        get_hitgroup_name = function(self, hbox)
            return self.consts.hitgroup_str[self:get_hitgroup_index(hbox)]
        end,

        get_weighted_damage = function(self, hbox, dmg) -- safety order: stomach, chest, limbs, head (head is so fucking unsafe)
            local hgroup = self:get_hitgroup_name(hbox)

            if hgroup == "head" or hgroup == "neck" then
                return dmg * 0.125
            end
            if hgroup == "left arm" or hgroup == "right arm" or hgroup == "left leg" or hgroup == "right leg" then
                return dmg * 0.25
            end
            if hgroup == "chest" then
                return dmg * 0.8
            end
            if hgroup == "stomach" then
                return dmg
            end

            return 0
        end,

        get_hbox_radius = function(self, hbox)
            if hbox == nil then
                return 0.0
            end
    
            return self.consts.hbox_radius[hbox]
        end,

        calculate_hc = function(self, inaccuracy, point, radius) -- [0, 1] | with help of CShotManipulator::ApplySpread
            if inaccuracy < 1e-6 then 
                return 1.0
            end

            local distance = point:dist(self.variables.eyepos)
            local R = distance * math.tan(inaccuracy)
        
            local ratio = radius / R
            if ratio >= 1.0 then
                return 1.0
            end
        
            return (0.5 * ratio^4 - 8 / 3 * ratio^3 + math.pi * ratio^2) / 0.9749259869231 -- some propability math, constant is formula evaluated at ratio=1
        end,

        max_hc = function(self, point, radius) -- [0, 1]
            if self.variables.weapon_type == self.consts.WEAPONTYPE_SNIPER_RIFLE and (ui_accuracy_autoscope:get() or self.variables.lp["m_bIsScoped"]) then 
                if self.variables.cmd.in_duck == 1 then
                    return self:calculate_hc(self.variables.weapon_info["inaccuracy_crouch_alt"], point, radius)
                else
                    return self:calculate_hc(self.variables.weapon_info["inaccuracy_stand_alt"], point, radius)
                end
            else
                if self.variables.cmd.in_duck == 1 then
                    return self:calculate_hc(self.variables.weapon_info["inaccuracy_crouch"], point, radius)
                else
                    return self:calculate_hc(self.variables.weapon_info["inaccuracy_stand"], point, radius)
                end
            end
        end,

        choose_hbox = function(self, target) -- tries to prefer safety over dmg
            local idx           = target:get_index()
            local m_bDormant    = ffi.cast("bool*", ffi.cast("uintptr_t", target[0]) + 0xED) -- 0xED - m_bDormant offset
            local best_hbox     = nil
            local highest_w_dmg = 0.0

            self.variables.is_reachable[idx] = false

            for hbox = 1, #self.variables.hbox_state do
                if self.variables.hbox_state[hbox] then
                    local target_hbox_pos = target:get_hitbox_position(hbox - 1) 
                    
                    m_bDormant[0] = 0 -- dmg calc fix found in old chimera source : if entity is not dormant then utils.trace_bullet takes an impact with it into account. If entity is dormant then it ignores entity
                    local dmg, trace = utils.trace_bullet(self.variables.lp, self.variables.eyepos, target_hbox_pos)
                    m_bDormant[0] = 1

                    if trace.entity ~= nil and not trace.entity:is_enemy() or dmg < self.variables.mindmg then
                        goto continue
                    end

                    self.variables.is_reachable[idx] = true
                    local maxhc = 100 * self:max_hc(target_hbox_pos, self:get_hbox_radius(hbox))
                    if maxhc < self.variables.minhc then
                        goto continue
                    end

                    local w_dmg = self:get_weighted_damage(hbox, dmg)
                    if w_dmg > highest_w_dmg then
                        best_hbox          = hbox
                        highest_w_dmg      = w_dmg
                        self.variables.dmg = dmg
                    end
                end
                ::continue::
            end

            return best_hbox
        end,

        choose_target = function(self) -- closest to camera
            local enemies = entity.get_players(true)

            local closest_enemy    = nil
            local closest_distance = math.huge
            for _, enemy in ipairs(enemies) do
                local alpha = enemy:get_bbox().alpha

                if self:target_check(enemy) and 5 * (0.8 - alpha) < ui_settings_valid_time:get() * 0.01 then 
                    local hbox = self:choose_hbox(enemy)
                    if hbox ~= nil then -- dmg check
                        local origin = enemy:get_origin()
                        local ray_distance = origin:dist_to_ray(self.variables.camera_position, self.variables.camera_direction)
                        if ray_distance < closest_distance then
                            closest_distance    = ray_distance
                            closest_enemy       = enemy
                            self.variables.hbox = hbox
                        end
                    end
                end
            end

            return closest_enemy
        end,

        autostop = function(self)
            local min_speed = math.sqrt((self.variables.cmd.forwardmove * self.variables.cmd.forwardmove) + (self.variables.cmd.sidemove * self.variables.cmd.sidemove))
            local goal_speed = self.variables.lp["m_bIsScoped"] and self.variables.weapon_info["max_player_speed_alt"] or self.variables.weapon_info["max_player_speed"]

            if goal_speed > 0 and min_speed > 0 then
                if not self.variables.cmd.in_duck then
                    goal_speed = goal_speed * 0.33 -- if ure standing and ur speed is a third of max_player_speed(_alt) then moving doesnt affect accuracy at all
                end
        
                if min_speed > goal_speed then
                    local factor = goal_speed / min_speed
                    self.variables.cmd.forwardmove = self.variables.cmd.forwardmove * factor
                    self.variables.cmd.sidemove    = self.variables.cmd.sidemove * factor
                end
            end
        end,
    
        autoscope = function(self)
            if not self.variables.lp["m_bIsScoped"] then
                self.variables.cmd.in_attack2 = true
            end
        end,

        run = function(self, cmd)
            if not ui_dormant_switch:get() then
                return
            end
            if not self:lp_check() then 
                return 
            end

            self.variables:initialize(cmd)
            
            -- if self.aimbot_shot.tickcount ~= nil and globals.tickcount - self.aimbot_shot.tickcount > 1 and not self.aimbot_shot.handled then
            --     if ui_misc_logs:get() then
            --         print_raw(("\a00FF00[Dormant Aimbot] \aFFFFFFMissed %s(%d%s) in %s for %d damage"):format(
            --         self.aimbot_shot.victim:get_name(), 
            --         self.aimbot_shot.hitchance,
            --         "%",
            --         self.aimbot_shot.hitgroup,
            --         self.aimbot_shot.damage
            --     ))
            --     end
            --     self.aimbot_shot.handled = true
            -- end

            if not self:weapon_check() then 
                return 
            end 

            local target = self:choose_target()
            if target == nil then
                return
            end

            local idx       = target:get_index()
            local aim_point = target:get_hitbox_position(self.variables.hbox - 1)
 
            if self.player_info.is_valid[idx] and ui_accuracy_velfix:get() then -- velocity adjustment
                local delta = (globals.tickcount - self.player_info.tickcount[idx]) * globals.tickinterval
                if delta < 1.0 then 
                    aim_point = aim_point + self.player_info.last_velocity[idx] * delta
                end
            end

            local aim_angles = self.variables.eyepos:to(aim_point):angles()

            if ui_accuracy_autostop:get() then
                self:autostop()
            end
            if ui_accuracy_autoscope:get() then
                self:autoscope()
            end

            local hc
            if self.variables.weapon_info["is_revolver"] then
                if self.variables.cmd.in_duck == 1 then
                    hc = self:calculate_hc(self.variables.weapon:get_inaccuracy() * 0.2 + self.variables.weapon:get_spread() * 0.00765, aim_point, self:get_hbox_radius(self.variables.hbox)) -- 0.00765 = (13 / 17) / 100
                else
                    hc = self:calculate_hc(self.variables.weapon:get_inaccuracy() * 0.166 + self.variables.weapon:get_spread() * 0.00765, aim_point, self:get_hbox_radius(self.variables.hbox)) 
                end
            else 
                hc = self:calculate_hc(self.variables.weapon:get_inaccuracy() + self.variables.weapon:get_spread(), aim_point, self:get_hbox_radius(self.variables.hbox))
            end
            hc = 100 * hc

            if hc >= self.variables.minhc then
                self.variables.cmd.view_angles = aim_angles
                self.variables.cmd.in_attack   = true

                if ui_misc_logs:get() then
                    print_raw(("\a00FF00[Dormant Aimbot] \aFFFFFFShot in %s(%d%s)'s %s for %d damage"):format(
                        target:get_name(), 
                        hc,
                        "%",
                        self:get_hitgroup_name(self.variables.hbox),
                        self.variables.dmg
                    ))
                end

                -- log
                -- self.aimbot_shot.tickcount     = globals.tickcount
                -- self.aimbot_shot.victim        = target
                -- self.aimbot_shot.hitchance     = hc
                -- self.aimbot_shot.hitgroup      = self:get_hitgroup_name(self.variables.hbox)
                -- self.aimbot_shot.damage        = utils.trace_bullet(self.variables.lp, self.variables.eyepos, aim_point)
                -- self.aimbot_shot.handled       = false
                -- self.aimbot_shot.point         = aim_point
            end
        end,

        update_enemy_info = function(self)
            local enemies = entity.get_players(true)

            for _, enemy in ipairs(enemies) do
                local idx = enemy:get_index()

                if enemy ~= nil and enemy:is_alive() then
                    local origin = enemy:get_origin()

                    if self.player_info.last_origin_pos[idx] == nil then
                        self.player_info.last_origin_pos[idx] = vector(0, 0, 0)
                        self.player_info.last_velocity[idx]   = vector(0, 0, 0)
                        self.player_info.tickcount[idx]       = globals.tickcount
                        self.player_info.is_valid[idx]        = false
                    elseif self.player_info.last_origin_pos[idx] ~= origin then
                        if enemy:get_network_state() == 0 then
                            self.player_info.last_velocity[idx] = enemy["m_vecVelocity"]
                        else
                            local delta = (globals.tickcount - self.player_info.tickcount[idx]) * globals.tickinterval
                            if self.player_info.is_valid[idx] and delta < 1.0 then -- dont update velocity if prev enemy pos was too old
                                self.player_info.last_velocity[idx] = (origin - self.player_info.last_origin_pos[idx]) / delta
                            else
                                self.player_info.last_velocity[idx] = vector(0, 0, 0)
                            end
                        end
                        self.player_info.last_origin_pos[idx] = origin
                        self.player_info.tickcount[idx]       = globals.tickcount
                        self.player_info.is_valid[idx]        = true
                    end
                else
                    self.player_info.is_valid[idx] = false
                end
            end
        end,
        
        update_hboxes = function(self)
            local hbox_list = ui_settings_hitboxes:get()

            local state = {}
            state["Head"]    = false
            state["Chest"]   = false
            state["Stomach"] = false
            state["Arms"]    = false
            state["Legs"]    = false
            state["Feet"]    = false

            for _, value in ipairs(hbox_list) do
                state[value] = true
            end

            for i = 1, 1 do
                self.variables.hbox_state[1] = state["Head"]
            end
            for i = 5, 7 do
                self.variables.hbox_state[i] = state["Chest"]
            end
            for i = 3, 4 do
                self.variables.hbox_state[i] = state["Stomach"]
            end
            for i = 14, 19 do
                self.variables.hbox_state[i] = state["Arms"]
            end
            for i = 8, 11 do
                self.variables.hbox_state[i] = state["Legs"]
            end
            for i = 12, 13 do
                self.variables.hbox_state[i] = state["Feet"]
            end
        end
    }
    
-- on start
dormant_aimbot.aimbot:update_hboxes()

-- callbacks
events.createmove:set(function(cmd)
    if ui_accuracy_velfix:get() then
        dormant_aimbot.aimbot:update_enemy_info()
    end
    dormant_aimbot.aimbot:run(cmd)
end)

events.render:set(function(ctx)
    if ui_misc_debug_mode:get() then
        local enemies = entity.get_players(true)
        for _, enemy in ipairs(enemies) do
            local origin = enemy:get_origin()
            local alpha = enemy:get_bbox().alpha
            render.text(1, origin:to_screen(), color(255, 255, 255), nil, alpha)
        end
    end
end)

ui_settings_hitboxes:set_callback(function() 
    dormant_aimbot.aimbot:update_hboxes()
end)

local esp_dormant_flag = esp.enemy:new_text("Dormant Aimbot", "DA", function(player)
    if ui_dormant_switch:get() and dormant_aimbot.variables.is_reachable[player:get_index()] and player:get_network_state() ~= 0 and player:get_network_state() ~= 5 then
        return "DA"
    end
end)

events.player_hurt:set(function(e)
    local attacker = entity.get(e.attacker, true)
    local victim = entity.get(e.userid, true)

    if attacker == dormant_aimbot.variables.lp then
        dormant_aimbot.player_info.misscount[victim:get_index()] = 0
    end
end)

-- events.player_hurt:set(function(e)
--     local shot_time = dormant_aimbot.aimbot_shot.tickcount
--     if shot_time == nil then
--         return
--     end

--     if globals.tickcount - shot_time == 1 then
--         local attacker = entity.get(e.attacker, true)

--         if dormant_aimbot.variables.lp == attacker then
--             local victim = entity.get(e.userid, true)
--             local hgroup = dormant_aimbot.consts.hitgroup_str[e.hitgroup]

--             if ui_misc_logs:get() then
--                 print_raw(("\a00FF00[Dormant Aimbot] \aFFFFFFHit %s(%d%s) in %s(%s) for %d(%d) damage (%d health remaining)"):format(
--                     victim:get_name(), 
--                     dormant_aimbot.aimbot_shot.hitchance, 
--                     "%",
--                     hgroup, 
--                     dormant_aimbot.aimbot_shot.hitgroup, 
--                     e.dmg_health, 
--                     dormant_aimbot.aimbot_shot.damage,
--                     e.health
--                 ))
--             end
--             dormant_aimbot.aimbot_shot.handled = true
--         end
--     end
-- end)

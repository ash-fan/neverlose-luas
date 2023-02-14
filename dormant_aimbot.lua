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
local ui_dormant        = ui.create("Dormant Aimbot")
local ui_dormant_switch = ui_dormant:switch("Dormant Aimbot", false)
local ui_dormant_logs   = ui_dormant:switch("Logs", false)

local ui_settings          = ui.create("Settings")
local ui_settings_hitboxes = ui_settings:selectable("Hitboxes", "Head", "Chest", "Stomach", "Arms", "Legs", "Feet")

local ui_settings_mindmg     = ui_settings:slider("Minimum Damage", 1, 100, 1)
local ui_settings_hitchance  = ui_settings:slider("Hitchance", 1, 100, 60)
local ui_settings_alpha      = ui_settings:slider("Alpha", 1, 1000, 650)

local ui_accuracy           = ui.create("Accuracy")
local ui_accuracy_autoscope = ui_accuracy:switch("Auto Scope", false)
local ui_accuracy_autostop  = ui_accuracy:switch("Auto Stop", false)

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
        hbox_radius = { 4.2, 3.5, 6, 6, 6.5, 6.2, 5, 5, 5, 4, 4, 3.6, 3.7, 4, 4, 3.3, 3, 3.3, 3 },
        hbox_factor = { 0.5, 0.1, 0.8, 0.8, 0.7, 0.7, 0.6, 0.5, 0.5, 0.5, 0.5, 0.4, 0.4, 0.4, 0.4, 0.5, 0.5, 0.5, 0.5 },
        hitgroup_str = {
            [0] = 'generic',
            'head', 'chest', 'stomach',
            'left arm', 'right arm',
            'left leg', 'right leg',
            'neck', 'generic', 'gear'
        }
    }
    :struct 'aimbot_shot' {
        tickcount = nil,
        victim    = nil,
        hitchance = nil,
        hitgroup  = nil,
        damage    = nil,
        handled   = nil
    }
    :struct 'variables' {
        hbox_state   = { false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false },
        is_reachable = {},

        cmd         = nil,
        lp          = nil,
        weapon      = nil,
        weapon_info = nil,
        eyepos      = nil,

        camera_position  = nil,
        camera_direction = nil,

        mindmg = nil,
        minhc  = nil,

        dmg = nil,

        initialize = function(self, cmd)
            self.cmd         = cmd
            self.lp          = entity.get_local_player()
            self.weapon      = self.lp:get_player_weapon()
            self.weapon_info = self.weapon:get_weapon_info()
            self.eyepos      = self.lp:get_eye_position()
            
            self.camera_position = render.camera_position()
            self.direction       = vector():angles(render.camera_angles())

            self.mindmg = ui_settings_mindmg:get()
            self.minhc  = ui_settings_hitchance:get()
        end,
    }
    :struct 'aimbot' {
        get_hitgroup_name = function(self, hbox)
            if hbox == 1 then
                return "head"
            end
            if hbox == 2 then
                return "neck"
            end
            if 3 <= hbox and hbox <= 4 then
                return "stomach"
            end
            if 5 <= hbox and hbox <= 7 then
                return "chest"
            end
            if 8 <= hbox and hbox <= 13 then
                if hbox % 2 == 0 then
                    return "left leg"
                else
                    return "right leg"
                end
            end
            if 14 <= hbox and hbox <= 19 then
                if hbox % 2 == 1 then
                    return "left arm"
                else
                    return "right arm"
                end
            end
            return "generic" -- a little bit incorrect but who cares?
        end,

        get_weighted_damage = function(self, hbox, dmg) -- safety order: stomach, chest, limbs, head (head is so fucking unsafe)
            local hgroup = self:get_hitgroup_name(hbox)
            if hgroup == "generic" then
                return 0
            end
            if hgroup == "head" or hgroup == "neck" then
                return dmg / 8
            end
            if hgroup == "left arm" or hgroup == "right arm" or hgroup == "left leg" or hgroup == "right leg" then
                return dmg / 4
            end
            if hgroup == "chest" then
                return dmg / 1.5
            end
            if hgroup == "stomach" then
                return dmg
            end
        end,

        get_hbox_radius = function(self, hbox)
            if hbox == nil then
                return 0
            end
    
            return self.consts.hbox_radius[hbox] * self.consts.hbox_factor[hbox]
        end,

        calculate_hc = function(self, inaccuracy, point, radius) 
            -- if x -> 0 then tan(x) ~ x therefore R ~ distance * inaccuracy
            -- max distance is 8192 so R <= 8192 * inaccuracy
            -- hc = (radius / R) ^ 2 >= (radius / (8192 * inaccuracy)) ^ 2 
            -- so if (radius / (8192 * inaccuracy)) ^ 2 >= 100 then hc >= 100
            -- assume that radius >= 0.1
            -- then inaccuracy <= 1 / 819200 < 1e-6
            -- so if inaccuracy < 1e-6 then hc > 100 
            if inaccuracy < 1e-6 then 
                return 100
            end

            local distance = self.variables.eyepos:dist(point)
            local R = distance * math.tan(inaccuracy / 2) -- / 2 cuz of geometry

            return math.min(radius * radius / (R * R), 1) * 100
        end,

        max_hc = function(self, point, radius)
            if self.variables.weapon_info["weapon_type"] == self.consts.WEAPONTYPE_SNIPER_RIFLE and (ui_accuracy_autoscope:get() or self.variables.lp["m_bIsScoped"]) then 
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
            local best_hbox
            local highest_w_dmg = 0
            local idx = target:get_index()
        
            self.variables.is_reachable[idx] = false
            
            for hbox = 1, #self.variables.hbox_state do
                if self.variables.hbox_state[hbox] then
                    local target_hbox_pos = target:get_hitbox_position(hbox - 1) -- lua starts array indexes with 1

                    local dmg = utils.trace_bullet(self.variables.lp, self.variables.eyepos, target_hbox_pos)
                    local hc = self:max_hc(target_hbox_pos, self:get_hbox_radius(hbox))

                    if dmg > 0 then
                        self.variables.is_reachable[idx] = true
                    end

                    if dmg >= self.variables.mindmg and hc >= self.variables.minhc then
                        local w_dmg = self:get_weighted_damage(hbox, dmg)
                        if w_dmg > highest_w_dmg then
                            best_hbox = hbox
                            highest_w_dmg = w_dmg
                            self.variables.dmg = dmg
                        end
                    end
                end
            end
            return best_hbox
        end,

        target_check = function(self, target)
            if target == nil then
                return false
            end
    
            if not target["m_bConnected"] == 1 then
                return false
            end
    
            if not target:is_alive() then
                return false
            end
    
            if target:get_network_state() == 0 or target:get_bbox().alpha < ui_settings_alpha:get() / 1000 then
                return false
            end

            if self:choose_hbox(target) == nil then
                return false
            end
    
            return true
        end,
    
        weapon_check = function(self, target)
            if self.variables.weapon == nil then
                return false
            end
    
            local weapon_type = self.variables.weapon_info["weapon_type"]
    
            if weapon_type == nil or weapon_type == self.consts.WEAPONTYPE_KNIFE or weapon_type >= self.consts.WEAPONTYPE_C4 then
                return false
            end

            if self.variables.weapon:get_weapon_reload() ~= -1 then
                return false
            end
    
            if self.variables.lp:get_origin():dist(target:get_origin()) > self.variables.weapon_info["range"] then
                return false
            end
    
            if self.variables.weapon["m_flNextPrimaryAttack"] > globals.curtime then
                return false
            end

            return true
        end,
    
        choose_target = function(self) -- closest to camera | pasted from nl lua api gitbook
            local players = entity.get_players(true)

            local best_player
            local best_distance = math.huge
    
            for _, player in ipairs(players) do
                if self:target_check(player) and self:weapon_check(player) then
                    local origin = player:get_origin()
                    local ray_distance = origin:dist_to_ray(self.variables.camera_position, self.variables.direction)
                    if ray_distance < best_distance then
                        best_distance = ray_distance
                        best_player = player
                    end
                end
            end

            return best_player
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
                    self.variables.cmd.sidemove = self.variables.cmd.sidemove * factor
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

            if self.aimbot_shot.tickcount ~= nil and globals.tickcount - self.aimbot_shot.tickcount > 1 and not self.aimbot_shot.handled then
                if ui_dormant_logs:get() then
                    print_raw(("\a00FF00[Dormant Aimbot] \aFFFFFFMissed %s(%d) in %s for %d damage"):format(
                    self.aimbot_shot.victim:get_name(), 
                    self.aimbot_shot.hitchance,
                    self.aimbot_shot.hitgroup,
                    self.aimbot_shot.damage
                ))
                end
                self.aimbot_shot.handled = true
            end

            self.variables:initialize(cmd)

            local target = self:choose_target()

            if target == nil then
                return
            end
    
            local hbox = self:choose_hbox(target)
            
            local aim_point = target:get_hitbox_position(hbox - 1)
            local aim_angles = self.variables.eyepos:to(aim_point):angles()

            if ui_accuracy_autostop:get() then
                self:autostop()
            end
            if ui_accuracy_autoscope:get() then
                self:autoscope()
            end

            local hc = self:calculate_hc(self.variables.weapon:get_inaccuracy(), aim_point, self:get_hbox_radius(hbox))

            if hc >= self.variables.minhc then
                self.variables.cmd.view_angles = aim_angles
                self.variables.cmd.in_attack   = true

                self.aimbot_shot.tickcount = globals.tickcount
                self.aimbot_shot.victim    = target
                self.aimbot_shot.hitchance = hc
                self.aimbot_shot.hitgroup  = self:get_hitgroup_name(hbox)
                self.aimbot_shot.damage    = self.variables.dmg
                self.aimbot_shot.handled   = false
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

            self.variables.hbox_state[1] = state["Head"]
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
    
dormant_aimbot.aimbot:update_hboxes()

-- callbacks
events.createmove:set(function(cmd)
    dormant_aimbot.aimbot:run(cmd)
end)

ui_settings_hitboxes:set_callback(function() 
    dormant_aimbot.aimbot:update_hboxes()
end)

local esp_dormant_flag = esp.enemy:new_text("Dormant Aimbot", "DA", function(player)
    if dormant_aimbot.variables.is_reachable[player:get_index()] and player:get_network_state() ~= 0 and player:get_network_state() ~= 5 then
        return "DA"
    end
end)

events.player_hurt:set(function(e)
    local shot_time = dormant_aimbot.aimbot_shot.tickcount
    if shot_time == nil then
        return
    end
    if globals.tickcount - shot_time == 1 then
        local attacker = entity.get(e.attacker, true)

        if dormant_aimbot.variables.lp == attacker then
            local victim = entity.get(e.userid, true)
            local hgroup = dormant_aimbot.consts.hitgroup_str[e.hitgroup]
            if ui_dormant_logs:get() then

                print_raw(("\a00FF00[Dormant Aimbot] \aFFFFFFHit %s(%d) in %s(%s) for %d(%d) damage (%d health remaining)"):format(
                    victim:get_name(), 
                    dormant_aimbot.aimbot_shot.hitchance, 
                    hgroup, 
                    dormant_aimbot.aimbot_shot.hitgroup, 
                    e.dmg_health, 
                    dormant_aimbot.aimbot_shot.damage, 
                    e.health
                ))
            end
            dormant_aimbot.aimbot_shot.handled = true
        end
    end
end)
local S = minetest.get_translator("soundblock_core")

soundblock = {}
soundblock.registered_sounds = {}

function soundblock.register_sound(name,def)
	soundblock.registered_sounds[name] = def
end

function soundblock.unregister_sound(name)
	soundblock.registered_sounds[name] = nil
end

soundblock.registered_sound_keys = {}
soundblock.registered_sound_descriptions = {}
minetest.register_on_mods_loaded(function()
	for k,v in pairs(soundblock.registered_sounds) do
		local i = #soundblock.registered_sound_keys + 1
		soundblock.registered_sound_keys[i] = k
		soundblock.registered_sound_descriptions[i] = v.description or "UNKNOWN"
		soundblock.registered_sounds[k].i = i
	end
end)

soundblock.register_sound("soundblock_core:white_noice",{
	description = S("Test White Noice"),
	infotext = S("Pure White Noice.\nThis is a loop."),
	spec = { -- SimpleSoundSpec
		name = "soundblock_core_white_noice", -- Sound name
		gain = 0.1,
		pitch = 1.0,
	},
	default_config = { -- Parameters
		loop = true,
	}
})

soundblock.block_playing_sounds = {}
function soundblock.block_get_config(pos)
	local meta = minetest.get_meta(pos)
	local config = {}
	config.name = meta:get_string("sound_name")
	if config.name == "" then return false, "META_INVALID" end
	config.gain = meta:get_float("gain")
	if config.gain == 0 then return false, "META_INVALID" end
	config.radius = math.min(meta:get_int("radius"),40)
	if config.radius == 0 then return false, "META_INVALID" end
	config.loop = (meta:get_int("loop") == 1)
	return true, config
end
function soundblock.block_apply_sound(pos,config)
	if not config then
		local status, msg = soundblock.block_get_config(pos)
		if not status then return false, msg end
		config = msg
	end
	local sound_def = soundblock.registered_sounds[config.name]
	if not sound_def then
		return false, "SOUND_NF"
	end
	local pos_str = minetest.hash_node_position(pos)
	if soundblock.block_playing_sounds[pos_str] then
		minetest.sound_stop(soundblock.block_playing_sounds[pos_str])
	end
	local spec = sound_def.spec
	local params = {
		pos = pos,
		gain = config.gain,
		max_hear_distance = config.radius,
		loop = config.loop
	}
	soundblock.block_playing_sounds[pos_str] = minetest.sound_play(spec,params)
	return true, soundblock.block_playing_sounds[pos_str]
end
function soundblock.block_play_at(pos,config)
	local sound_def = soundblock.registered_sounds[config.name]
	if not sound_def then
		return false, "SOUND_NF"
	end
	local meta = minetest.get_meta(pos)
	config.radius = math.min(config.radius,40)
	meta:set_string("sound_name",config.name)
	meta:set_float("gain",config.gain or 1)
	meta:set_int("radius",config.radius)
	meta:set_int("loop",config.loop and 1 or 0)
	meta:set_string("infotext",S("Soundblock Playing: @1",sound_def.description or "UNKNOWN"))
	return soundblock.block_apply_sound(pos,config)
end
function soundblock.stop_play(pos,digblock)
	local pos_str = minetest.hash_node_position(pos)
	if not digblock then
		local meta = minetest.get_meta(pos)
		meta:set_string("sound_name","") -- This is enough to stop ABM from restartng the sound
		meta:set_string("infotext",S("Soundblock Idle"))
	end
	if soundblock.block_playing_sounds[pos_str] then
		minetest.sound_stop(soundblock.block_playing_sounds[pos_str])
	end
end

local function privs_check(player,pos)
	if not player:is_player() then return false end
	local name = player:get_player_name()
	local privs = minetest.get_player_privs(name)
	if privs.server or privs.protection_bypass then return true end
	if minetest.is_protected(pos, name) then
		minetest.record_protection_violation(pos, name)
		return false
	end
	return true
end

local gui = flow.widgets
local block_gui = flow.make_gui(function(player,ctx)
	if not ctx.pos then return gui.Label { label = "ERR" } end
	if not privs_check(player,ctx.pos) then
		return gui.Label { label = S("Position is protected!") }
	end
	if not ctx.curr_config then
		local status, config = soundblock.block_get_config(ctx.pos)
		if not status then
			ctx.curr_config = {}
		else
			ctx.curr_config = config
		end
	end

	if not ctx.curr_config.name then ctx.curr_config.name = soundblock.registered_sound_keys[ctx.form.list_desc or 1] end
	local curr_def = ctx.curr_config.name and soundblock.registered_sounds[ctx.curr_config.name]
	if not curr_def then
		return gui.HBox {
			gui.Label { label = S("No sounds registered.") },
			gui.ButtonExit { label = S("Exit") }
		}
	end

	return gui.HBox {
		gui.Textlist {
			w = 3, h = 6,
			name = "list_desc",
			listelems = soundblock.registered_sound_descriptions,
			selected_idx = curr_def.i
		},
		gui.VBox {
			w = 6,
			gui.Label {
				label = curr_def.description or "UNKNOWN",
			},
			gui.Box{w = 1, h = 0.05, color = "grey", padding = 0},
			gui.Textarea {
				default = curr_def.infotext or "",
				expand = true, align_v = "top",
			},
			gui.Box{w = 1, h = 0.05, color = "grey", padding = 0},
			gui.Checkbox {name="loop",label = S("Loop"),selected = ctx.curr_config.loop or curr_def.default_config.loop or nil},
			gui.HBox {
				gui.Field { w=1,name = "gain",label = S("Gain"), default = tostring(ctx.form.gain or ctx.curr_config.gain or curr_def.default_config.gain or 1),expand=true},
				gui.Field { w=1,name = "radius",label = S("Radius (max. 40)"), default = tostring(ctx.form.radius or ctx.curr_config.radius or curr_def.default_config.radius or 40),expand=true},
			},
			gui.HBox {
				gui.Button {
					label = S("Stop all"),expand=true,
					on_event = function(player,ctx)
						if not privs_check(player,ctx.pos) then
							return gui.Label { label = S("Position is protected!") }
						end
						soundblock.stop_play(ctx.pos,false)
						return true
					end
				},
				gui.Button {
					label = S("Play"),expand=true,
					on_event = function(player,ctx)
						if not privs_check(player,ctx.pos) then
							return gui.Label { label = S("Position is protected!") }
						end
						local config = {}
						config.name = soundblock.registered_sound_keys[ctx.form.list_desc]
						if not config.name then return gui.Label { label = "ERR" } end
						config.gain = ctx.form.gain
						config.radius = ctx.form.radius
						config.loop = ctx.form.loop
						soundblock.block_play_at(ctx.pos,config)
						ctx.curr_config = nil
						return true
					end
				},
			}
		}
	}
end)

minetest.register_node(":soundblock:block",{
	description = S("Soundblock"),
	tiles = {"soundblock_block.png"},
	on_construct = function(pos)
		soundblock.stop_play(pos,false)
	end,
	after_destruct = function(pos)
		soundblock.stop_play(pos,true)
	end,
	on_rightclick = function(pos,node,clicker,itemstack,pointer_thing)
		if not privs_check(clicker,pos) then return end
		block_gui:show(clicker,{pos=pos})
	end,
	is_ground_content = false,
	groups = {oddly_breakable_by_hand = 3,},
})

minetest.register_abm({
	label = "soundblock:active_soundblocks_over_restarts",
	nodenames = {"soundblock:block"},
	interval = 2,
	chance = 1,
	catch_up = false,
	action = function(pos, node, active_object_count, active_object_count_wider)
		local pos_str = minetest.hash_node_position(pos)
		if not soundblock.block_playing_sounds[pos_str] then
			soundblock.block_apply_sound(pos)
		end
	end,
})

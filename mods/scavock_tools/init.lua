-- Gathering tools: pick + axe per material tier (§6 tier ladder).
-- Tool tiers and weapon tiers are separate progressions (§6 Confirmed) —
-- weapons live in scavock_weapons.
-- Rarity vs power is a gradual slope, never exponential (§6).

local tiers = {
	-- cracky/choppy dig-time tables per tier; higher tiers unlock harder rock
	scrap = {
		cracky = { times = { [3] = 1.6 }, uses = 40 },
		choppy = { times = { [2] = 2.4, [3] = 1.6 }, uses = 40 },
		dmg = 3,
	},
	iron = {
		cracky = { times = { [2] = 2.0, [3] = 1.2 }, uses = 90 },
		choppy = { times = { [2] = 1.6, [3] = 1.1 }, uses = 90 },
		dmg = 4,
	},
	steel = {
		cracky = { times = { [1] = 2.6, [2] = 1.4, [3] = 0.9 }, uses = 160 },
		choppy = { times = { [1] = 2.4, [2] = 1.2, [3] = 0.8 }, uses = 160 },
		dmg = 4,
	},
	titanium = {
		cracky = { times = { [1] = 1.8, [2] = 1.0, [3] = 0.6 }, uses = 300 },
		choppy = { times = { [1] = 1.7, [2] = 0.9, [3] = 0.55 }, uses = 300 },
		dmg = 5,
	},
	graphene = {
		cracky = { times = { [1] = 1.2, [2] = 0.7, [3] = 0.4 }, uses = 600 },
		choppy = { times = { [1] = 1.1, [2] = 0.6, [3] = 0.35 }, uses = 600 },
		dmg = 5,
	},
}

for _, m in ipairs(scavock.materials) do
	local t = tiers[m.name]
	local ingot = "scavock_core:" .. m.name .. "_ingot"

	core.register_tool("scavock_tools:pick_" .. m.name, {
		description = m.desc .. " Pickaxe",
		inventory_image = "scavock_pick_" .. m.name .. ".png",
		tool_capabilities = {
			full_punch_interval = 1.2,
			max_drop_level = 1,
			groupcaps = { cracky = t.cracky },
			damage_groups = { fleshy = t.dmg },
		},
		groups = { pickaxe = 1 },
	})

	core.register_tool("scavock_tools:axe_" .. m.name, {
		description = m.desc .. " Axe (tool)",
		inventory_image = "scavock_axe_" .. m.name .. ".png",
		tool_capabilities = {
			full_punch_interval = 1.2,
			max_drop_level = 1,
			groupcaps = { choppy = t.choppy },
			damage_groups = { fleshy = t.dmg },
		},
		groups = { axe = 1 },
	})

	core.register_craft({
		output = "scavock_tools:pick_" .. m.name,
		recipe = {
			{ ingot, ingot, ingot },
			{ "", "scavock_core:stick", "" },
			{ "", "scavock_core:stick", "" },
		},
	})
	core.register_craft({
		output = "scavock_tools:axe_" .. m.name,
		recipe = {
			{ ingot, ingot },
			{ ingot, "scavock_core:stick" },
			{ "", "scavock_core:stick" },
		},
	})
end

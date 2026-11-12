--[[
	Glow effects: how the light on an object is drawn.

	An effect is a list of layers (the textures in Glow\Media, white shapes tinted by
	code) with a resting look for each state of the object (out of reach, in reach,
	refused) and loops played by the game's animation engine. Lua only runs when
	something changes: the state blends over a fraction of a second, and a particle
	picks a new spot when its loop ends. A glow therefore costs next to nothing per frame,
	and several can be shown at once (the real target and the preview).

	Layer fields:
	  t            texture in Glow\Media
	  layer, sub   draw layer and sublevel; blend "BLEND" for dark or shaded layers (else ADD)
	  w, h, x, y   size and place, in fractions of the effect size (h defaults to w)
	  tone         "base" (the color), "light", "white" (towards white), "dark", "gem"
	  a            alpha, or {out of reach, in reach}
	  lock         alpha kept on an object the game refuses (default 0.5)
	  grow, rot    size factor and rotation, numbers or {out of reach, in reach}
	  ease         "back": overshoots a little when grow/rot change (the brackets locking on)
	  anims        engine loops, each {kind, ...}: see Builders below
	  trigger      one-shot played when the object comes in reach ("flash", "lockon")
--]]

local ADDON, ns = ...

local FX = {}
ns.GlowFX = FX

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Glow\\Media\\"
FX.MEDIA = MEDIA

local REF = 100 -- effects are drawn for a size of 100, then the whole frame is scaled
local GROUND = 0.36 -- a circle lying on the ground, seen at the usual camera angle
local FOOT = -0.12 -- the ground below the middle of the object
local RING = 0.37 -- radius of the ring in ring.tga / dots.tga, in fractions of the width

local pi, TWO_PI = math.pi, 2 * math.pi
local sin, cos, random, sqrt, floor, min, max = math.sin, math.cos, math.random, math.sqrt, math.floor, math.min, math.max

local function Lerp(a, b, t)
	return a + (b - a) * t
end
FX.Lerp = Lerp

-- Speed of the loops in each state: livelier in reach, almost still when refused.
local SPEED = {far = 1, ready = 1.5, locked = 0.35}
local BLEND_TIME = 0.3 -- seconds for a state or color change
local GREY = 0.62 -- what the color fades to on a refused object


--[[ Paths ]]--

-- Points around a tilted ellipse (closed loop), for the "orbit" animation.
local function Ellipse(count, rx, ry, tilt, cx, cy)
	local points, ct, st = {}, cos(tilt or 0), sin(tilt or 0)
	for i = 0, count - 1 do
		local angle = i / count * TWO_PI
		local x, y = cos(angle) * rx, sin(angle) * ry
		points[#points + 1] = {(cx or 0) + x * ct - y * st, (cy or 0) + x * st + y * ct}
	end
	return points
end

-- A figure of eight lying around the object.
local function Eight(count, reach, height, cy)
	local points = {}
	for i = 0, count - 1 do
		local angle = i / count * TWO_PI
		points[#points + 1] = {sin(angle) * reach, (cy or 0) + sin(2 * angle) * height}
	end
	return points
end


--[[ Builders: one animation group per entry of a layer's anims ]]--

local function Smooth(animation, smoothing)
	if smoothing and animation.SetSmoothing then animation:SetSmoothing(smoothing) end
end

local function ScaleAnim(group, from, to, seconds, origin, smoothing, order)
	local scale = group:CreateAnimation("Scale")
	local fx, fy = type(from) == "table" and from[1] or from, type(from) == "table" and from[2] or from
	local tx, ty = type(to) == "table" and to[1] or to, type(to) == "table" and to[2] or to
	if scale.SetScaleFrom then
		scale:SetScaleFrom(fx, fy)
		scale:SetScaleTo(tx, ty)
	else
		scale:SetFromScale(fx, fy)
		scale:SetToScale(tx, ty)
	end
	if scale.SetOrigin then scale:SetOrigin(origin or "CENTER", 0, 0) end
	scale:SetDuration(seconds)
	if order then scale:SetOrder(order) end
	Smooth(scale, smoothing)
	return scale
end

local function AlphaAnim(group, from, to, seconds, delay, order)
	local alpha = group:CreateAnimation("Alpha")
	alpha:SetFromAlpha(from)
	alpha:SetToAlpha(to)
	alpha:SetDuration(seconds)
	if delay and delay > 0 then alpha:SetStartDelay(delay) end
	if order then alpha:SetOrder(order) end
	return alpha
end

-- Moves a layer to x, y (fractions) inside its effect.
local function Place(item, x, y)
	local tex = item.tex
	tex:ClearAllPoints()
	tex:SetPoint("CENTER", item.holder, "CENTER", x * REF, y * REF)
end

local Builders = {}

-- {"spin", seconds}: a full turn; negative turns clockwise.
function Builders.spin(item, a)
	local group = item.tex:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	local turn = group:CreateAnimation("Rotation")
	turn:SetDegrees(a[2] > 0 and 360 or -360)
	turn:SetDuration(math.abs(a[2]))
	if turn.SetOrigin then turn:SetOrigin("CENTER", 0, 0) end
	return group
end

-- {"pulse", low, high, seconds}: the layer's own alpha goes up and down.
function Builders.pulse(item, a)
	local group = item.tex:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local fade = AlphaAnim(group, a[2], a[3], a[4])
	Smooth(fade, "IN_OUT")
	return group
end

-- {"breathe", from, to, seconds, origin = "BOTTOM"}: swells and shrinks (numbers or {x, y}).
function Builders.breathe(item, a)
	local group = item.tex:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	ScaleAnim(group, a[2], a[3], a[4], a.origin, "IN_OUT")
	return group
end

-- {"bob", dx, dy, seconds}: floats back and forth.
function Builders.bob(item, a)
	local group = item.tex:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local move = group:CreateAnimation("Translation")
	move:SetOffset(a[2] * REF, a[3] * REF)
	move:SetDuration(a[4])
	Smooth(move, "IN_OUT")
	return group
end

-- {"sway", degrees, seconds}: turns a little one way, then the other.
function Builders.sway(item, a)
	local group = item.tex:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local turn = group:CreateAnimation("Rotation")
	turn:SetDegrees(a[2])
	turn:SetDuration(a[3])
	if turn.SetOrigin then turn:SetOrigin("CENTER", 0, 0) end
	Smooth(turn, "IN_OUT")
	return group
end

-- {"orbit", points, seconds, phase}: travels around a closed path. The phase picks the
-- starting point, so trails are exact copies a little behind.
function Builders.orbit(item, a)
	local points, count = a[2], #a[2]
	local shift = floor((a[4] or 0) % 1 * count + 0.5)
	local start = points[shift % count + 1]
	item.x, item.y = start[1], start[2]
	Place(item, start[1], start[2])
	local group = item.tex:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	local path = group:CreateAnimation("Path")
	path:SetDuration(a[3])
	if path.SetCurveType then path:SetCurveType("SMOOTH") end
	for i = 1, count do
		local point = points[(shift + i) % count + 1]
		local control = path:CreateControlPoint()
		control:SetOffset((point[1] - start[1]) * REF, (point[2] - start[2]) * REF)
		control:SetOrder(i)
	end
	return group
end

-- {"rise", dx, dy, seconds, phase, jitter = {x1, x2, y1, y2}, grow = {from, to}}: a particle
-- that appears, drifts and fades, then starts again somewhere else in the jitter box.
function Builders.rise(item, a)
	local tex, seconds = item.tex, a[4]
	tex:SetAlpha(0)
	local group = tex:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	local move = group:CreateAnimation("Translation")
	move:SetOffset(a[2] * REF, a[3] * REF)
	move:SetDuration(seconds)
	Smooth(move, "OUT")
	AlphaAnim(group, 0, 1, seconds * 0.25)
	AlphaAnim(group, 1, 0, seconds * 0.75, seconds * 0.25)
	if a.grow then ScaleAnim(group, a.grow[1], a.grow[2], seconds) end
	local box = a.jitter
	local function Respawn()
		if box then
			Place(item, item.x + Lerp(box[1], box[2], random()), item.y + Lerp(box[3], box[4], random()))
		end
	end
	Respawn()
	group:SetScript("OnLoop", Respawn)
	return group, (a[5] or 0) * seconds
end

-- {"expand", from, to, seconds, phase, hold = seconds}: a ring that widens and fades.
function Builders.expand(item, a)
	local tex, seconds = item.tex, a[4]
	tex:SetAlpha(0)
	local group = tex:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	ScaleAnim(group, a[2], a[3], seconds, nil, "OUT")
	AlphaAnim(group, 0, 1, seconds * 0.15)
	local out = AlphaAnim(group, 1, 0, seconds * 0.85, seconds * 0.15)
	Smooth(out, "IN")
	if a.hold then out:SetEndDelay(a.hold) end
	return group, (a[5] or 0) * (seconds + (a.hold or 0))
end

-- {"twinkle", radius, phase}: a star lights up somewhere in a disc, goes out, and comes
-- back elsewhere with another size and life.
function Builders.twinkle(item, a)
	local tex = item.tex
	tex:SetAlpha(0)
	local group = tex:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	local grow = ScaleAnim(group, 0.35, 1, 0.5, nil, "OUT", 1)
	local shrink = ScaleAnim(group, 1, 0.35, 0.5, nil, "IN", 2)
	local up = AlphaAnim(group, 0, 1, 0.5, nil, 1)
	local down = AlphaAnim(group, 1, 0, 0.5, nil, 2)
	local radius = a[2]
	local function Respawn()
		local angle, reach = random() * TWO_PI, sqrt(random()) * radius
		Place(item, item.x + cos(angle) * reach, item.y + sin(angle) * reach)
		local half = 0.35 + 0.45 * random()
		grow:SetDuration(half)
		up:SetDuration(half)
		shrink:SetDuration(half)
		down:SetDuration(half)
		down:SetEndDelay(0.4 * random())
		item.scale = 0.6 + 0.6 * random()
		local w = (item.spec.w or 1) * REF * item.scale
		tex:SetSize(w, w)
	end
	Respawn()
	group:SetScript("OnLoop", Respawn)
	return group, (a[3] or 0) * 1.2
end

-- {"flicker", spread, rest = {min, max}, phase}: a bolt that strikes, then rests a while.
function Builders.flicker(item, a)
	local tex = item.tex
	tex:SetAlpha(0)
	local group = tex:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	AlphaAnim(group, 0, 1, 0.04, nil, 1)
	local fade = AlphaAnim(group, 1, 0, 0.24, nil, 2)
	local rest = a.rest
	local function Respawn()
		Place(item, item.x + (random() - 0.5) * a[2], item.y)
		tex:SetRotation((random() - 0.5) * 0.4)
		fade:SetEndDelay(Lerp(rest[1], rest[2], random()))
	end
	Respawn()
	group:SetScript("OnLoop", Respawn)
	return group, a[3] or 0
end

-- {"fountain", height, spread, seconds, phase}: a drop thrown up from the foot that falls
-- back beside it, each time to another side.
function Builders.fountain(item, a)
	local tex, seconds = item.tex, a[4]
	tex:SetAlpha(0)
	local group = tex:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	local path = group:CreateAnimation("Path")
	path:SetDuration(seconds)
	if path.SetCurveType then path:SetCurveType("SMOOTH") end
	local controls = {}
	for i = 1, 4 do
		controls[i] = path:CreateControlPoint()
		controls[i]:SetOrder(i)
	end
	AlphaAnim(group, 0, 1, seconds * 0.1)
	AlphaAnim(group, 1, 0, seconds * 0.45, seconds * 0.55)
	ScaleAnim(group, 1, 0.5, seconds)
	local function Respawn()
		local reach = (random() - 0.5) * 2 * a[3]
		local height = a[2] * (0.65 + 0.45 * random())
		for i = 1, 4 do
			local s = i / 4
			controls[i]:SetOffset(reach * s * REF, 4 * height * s * (1 - s) * REF)
		end
	end
	Respawn()
	group:SetScript("OnLoop", Respawn)
	return group, (a[5] or 0) * seconds
end

-- One-shots played when the object comes in reach; the texture is shown only meanwhile.
local Triggers = {}

local function ShowWhilePlaying(group, tex)
	tex:Hide()
	group:SetScript("OnPlay", function() tex:Show() end)
	group:SetScript("OnFinished", function() tex:Hide() end)
	group:SetScript("OnStop", function() tex:Hide() end)
	return group
end

-- A burst of light that swells and goes out.
function Triggers.flash(item)
	local tex = item.tex
	tex:SetAlpha(0)
	local group = tex:CreateAnimationGroup()
	ScaleAnim(group, 0.5, 1.7, 0.5, nil, "OUT")
	AlphaAnim(group, 0, 1, 0.06)
	AlphaAnim(group, 1, 0, 0.44, 0.06)
	return ShowWhilePlaying(group, tex)
end

-- A ring that closes in on the light, as if it locked on.
function Triggers.lockon(item)
	local tex = item.tex
	tex:SetAlpha(0)
	local group = tex:CreateAnimationGroup()
	ScaleAnim(group, 1.5, 1, 0.35, nil, "OUT")
	AlphaAnim(group, 0, 0.9, 0.24)
	AlphaAnim(group, 0.9, 0, 0.12, 0.24)
	return ShowWhilePlaying(group, tex)
end


--[[ Effects ]]--

local E = {}
FX.EFFECTS = E
-- menu order: around the object first, then on the ground or rising from it
FX.ORDER = {"aura", "subtle", "sigil", "brackets", "vortex", "rift", "flame", "storm", "beam", "geyser",
	"beacon", "orbit", "spirit", "ripple", "sparkle"}

-- dark veil under the light, so an additive glow still shows on snow and sand
local function Shade(w, h, y, a)
	return {t = "glow", layer = "BACKGROUND", sub = -1, blend = "BLEND", tone = "dark", w = w, h = h, y = y or 0,
		a = a or 0.3, lock = 1}
end

-- light lying on the ground at the foot of the object
local function Pool(w, a)
	return {t = "glow", layer = "BACKGROUND", w = w, h = w * GROUND * 1.3, y = FOOT, tone = "base", a = a or {0.55, 0.9},
		anims = {{"breathe", 0.95, 1.06, 2.2}}}
end

-- bright star in the heart of the effect
local function Core(w, y, a)
	return {t = "flare", layer = "OVERLAY", sub = 2, w = w, y = y or 0, tone = "white", a = a or {0.3, 0.9},
		grow = {1, 1.2}, lock = 0, anims = {{"pulse", 0.7, 1, 0.9}}}
end

E.aura = {
	ghost = "halo",
	layers = {
		Shade(1.15),
		{t = "halo", layer = "BACKGROUND", w = 1, tone = "base", a = {0.45, 0.75},
			anims = {{"breathe", 0.97, 1.04, 3}, {"pulse", 0.8, 1, 1.7}}},
		{t = "wisp", layer = "BACKGROUND", sub = 1, w = 1.04, tone = "light", a = {0.28, 0.42}, lock = 0.3, anims = {{"spin", 34}}},
		{t = "wisp", layer = "BACKGROUND", sub = 1, w = 0.93, rot = 2.1, tone = "light", a = {0.22, 0.34}, lock = 0.3,
			anims = {{"spin", -24}}},
		{t = "ring", layer = "ARTWORK", w = 1, tone = "light", a = {0.25, 0.75}},
		{t = "arcs", layer = "ARTWORK", sub = 1, w = 1, tone = "light", a = {0.4, 0.9}, lock = 0, anims = {{"spin", -5.5}}},
		{t = "dots", layer = "OVERLAY", w = 1, tone = "light", a = {0.15, 0.95}, lock = 0, anims = {{"spin", 9}}},
		{t = "dots", layer = "OVERLAY", w = 1.32, rot = 1, tone = "light", a = {0.2, 0.45}, lock = 0,
			anims = {{"spin", -16}, {"pulse", 0.3, 1, 1.3}}},
		Core(0.38),
	},
	icon = {{"halo", 1, 1, 0, 0, 0.45}, {"wisp", 1, 1, 0, 0, 0.5}, {"ring", 1, 1, 0, 0, 1}, {"arcs", 1, 1, 0, 0, 0.9},
		{"flare", 0.6, 0.6, 0, 0, 1, true}},
}

E.subtle = {
	ghost = "halo", wave = {gain = 0.4},
	layers = {
		Shade(1.05, nil, 0, 0.24),
		{t = "halo", layer = "BACKGROUND", w = 0.95, tone = "base", a = {0.4, 0.65},
			anims = {{"breathe", 0.96, 1.05, 3.2}, {"pulse", 0.75, 1, 2}}},
		Core(0.3, 0, {0.25, 0.6}),
	},
	icon = {{"halo", 1, 1, 0, 0, 0.9}, {"flare", 0.36, 0.36, 0, 0, 0.6, true}},
}

E.sigil = {
	ghost = "halo",
	layers = {
		Shade(1.1, nil, 0, 0.34),
		{t = "halo", layer = "BACKGROUND", w = 0.94, tone = "base", a = {0.25, 0.45}, anims = {{"breathe", 0.96, 1.04, 2.8}}},
		{t = "sigil", layer = "ARTWORK", w = 0.94, tone = "light", a = {0.55, 0.95}, anims = {{"spin", 30}}},
		{t = "glyph", layer = "ARTWORK", sub = 1, w = 0.66, tone = "light", a = {0.35, 0.85}, lock = 0.3, anims = {{"spin", -13}}},
		Core(0.28, 0, {0.2, 0.8}),
	},
	icon = {{"sigil", 1, 1, 0, 0, 1}, {"glyph", 0.7, 0.7, 0, 0, 0.9, true}},
}

E.brackets = {
	wave = {t = "brackets", gain = 0.7},
	layers = {
		Shade(1.9, nil, 0, 0.28),
		{t = "glow", layer = "BACKGROUND", w = 1.5, tone = "base", a = {0.3, 0.5}, anims = {{"breathe", 0.95, 1.05, 2.4}}},
		-- out of reach a diamond that searches, in reach a square locked on the object
		{t = "brackets", layer = "ARTWORK", w = 1, grow = {1.04, 0.94}, rot = {pi / 4, 0}, ease = "back", tone = "light",
			a = {0.6, 0.95}, anims = {{"sway", 6, 1.7}}},
		{t = "ring", layer = "ARTWORK", sub = 1, w = 1, grow = {1.25, 0.74}, tone = "light", a = {0, 0.55}, lock = 0},
		{t = "brackets", layer = "ARTWORK", sub = 2, w = 0.5, grow = {1.1, 0.9}, rot = {0, pi / 4}, ease = "back",
			tone = "white", a = {0, 0.8}, lock = 0, anims = {{"pulse", 0.7, 1, 0.8}}},
		Core(0.24, 0, {0.12, 0.85}),
	},
	icon = {{"glow", 1, 1, 0, 0, 0.45}, {"brackets", 0.94, 0.94, 0, 0, 1}, {"ring", 0.62, 0.62, 0, 0, 0.55},
		{"flare", 0.4, 0.4, 0, 0, 0.9, true}},
}

E.vortex = {
	ghost = "halo", wave = {gain = 0.7},
	layers = {
		Shade(1.1, nil, 0, 0.32),
		{t = "halo", layer = "BACKGROUND", w = 0.98, tone = "base", a = {0.3, 0.5}, anims = {{"breathe", 0.96, 1.05, 2.6}}},
		{t = "swirl", layer = "ARTWORK", w = 1.18, tone = "base", a = {0.6, 0.9}, anims = {{"spin", -10}}},
		{t = "swirl", layer = "ARTWORK", sub = 1, w = 0.74, rot = 1.3, tone = "light", a = {0.45, 0.95}, anims = {{"spin", -4.6}}},
		{t = "dots", layer = "OVERLAY", w = 0.55, tone = "white", a = {0.45, 1}, lock = 0, anims = {{"spin", -2.4}}},
		{t = "dots", layer = "OVERLAY", w = 0.85, rot = 1.1, tone = "white", a = {0.3, 0.75}, lock = 0, anims = {{"spin", -3.6}}},
		Core(0.3),
	},
	icon = {{"halo", 1, 1, 0, 0, 0.4}, {"swirl", 1.05, 1.05, 0, 0, 1}, {"flare", 0.4, 0.4, 0, 0, 0.9, true}},
}

E.rift = {
	ghost = "halo", wave = {gain = 0.8},
	layers = {
		Shade(1.2, nil, 0, 0.35),
		{t = "swirl", layer = "BACKGROUND", w = 1.3, tone = "base", a = {0.55, 0.9}, anims = {{"spin", -3.2}}},
		{t = "swirl", layer = "ARTWORK", w = 0.82, rot = 1, tone = "light", a = {0.5, 0.95}, anims = {{"spin", -1.5}}},
		-- the hole: plain black, ringed with light
		{t = "glow", layer = "ARTWORK", sub = 1, blend = "BLEND", w = 0.66, tone = "dark", a = 0.97, lock = 1,
			anims = {{"breathe", 0.95, 1.03, 1.9}}},
		{t = "ring", layer = "ARTWORK", sub = 2, w = 0.42, tone = "white", a = {0.55, 1}, lock = 0.3, anims = {{"pulse", 0.85, 1, 0.6}}},
		-- shards pulled in, spiralling
		{t = "dots", layer = "OVERLAY", w = 1.35, tone = "white", a = {0.6, 1}, lock = 0,
			anims = {{"expand", 1, 0.25, 1.6, 0}, {"spin", -2.2}}},
		{t = "dots", layer = "OVERLAY", w = 1.35, rot = 1.05, tone = "white", a = {0.6, 1}, lock = 0,
			anims = {{"expand", 1, 0.25, 1.6, 0.5}, {"spin", -2.2}}},
		{t = "flare", layer = "OVERLAY", sub = 1, w = 0.26, x = -0.14, y = 0.14, tone = "white", a = {0.3, 0.9}, lock = 0,
			anims = {{"pulse", 0.4, 1, 1.1}}},
	},
	icon = {{"swirl", 1.1, 1.1, 0, 0, 1}, {"ring", 0.5, 0.5, 0, 0, 1, true}, {"flare", 0.3, 0.3, -0.3, 0.26, 0.9, true},
		{"flare", 0.22, 0.22, 0.3, -0.22, 0.8, true}},
}

do -- flame: tongues of fire rising from the object
	local layers = {
		{t = "glow", layer = "BACKGROUND", sub = -1, blend = "BLEND", tone = "dark", w = 1.7, h = 1.9, y = 0.3, a = 0.22, lock = 1},
		Pool(1.15),
	}
	-- x, height, seconds per flicker
	local tongues = {{-0.21, 0.62, 0.47}, {-0.1, 0.9, 0.39}, {0.01, 1.12, 0.43}, {0.12, 0.84, 0.36}, {0.23, 0.58, 0.5}}
	for i, shape in ipairs(tongues) do
		local x, height, seconds = shape[1], shape[2], shape[3]
		layers[#layers + 1] = {t = "flame", layer = "ARTWORK", w = 0.5, h = height, x = x, y = FOOT + height / 2 - 0.03,
			rot = -0.7 * x, tone = "base", a = {0.5, 0.8},
			anims = {{"breathe", {0.92, 0.86}, {1.05, 1.12}, seconds, origin = "BOTTOM"}}}
		if i > 1 and i < #tongues then
			layers[#layers + 1] = {t = "flame", layer = "ARTWORK", sub = 1, w = 0.3, h = height * 0.66, x = x,
				y = FOOT + height * 0.33 - 0.02, rot = -0.7 * x, tone = "white", a = {0.35, 0.7}, lock = 0.2,
				anims = {{"breathe", {0.9, 0.85}, {1.05, 1.1}, seconds, origin = "BOTTOM"}}}
		end
	end
	for i = 1, 2 do
		layers[#layers + 1] = {t = "glow", layer = "BACKGROUND", sub = -1, blend = "BLEND", tone = "dark", w = 0.5,
			y = FOOT + 0.75, a = 0.24, lock = 1,
			anims = {{"rise", 0, 0.8, 3.2, i / 2, jitter = {-0.1, 0.1, 0, 0}, grow = {1, 1.8}}}}
	end
	for i = 1, 7 do
		layers[#layers + 1] = {t = "glow", layer = "OVERLAY", w = 0.09, y = FOOT + 0.25, tone = "light", a = 1, lock = 0,
			anims = {{"rise", 0, 0.95, 1.5 + 0.12 * i, i / 7, jitter = {-0.24, 0.24, 0, 0.1}, grow = {1, 0.5}}}}
	end
	layers[#layers + 1] = Core(0.26, FOOT + 0.05, {0.2, 0.7})
	E.flame = {
		wave = {flat = GROUND, y = FOOT, w = 0.95, gain = 0.6},
		layers = layers,
		icon = {{"glow", 1, 0.5, 0, -0.32, 0.9}, {"flame", 0.5, 0.82, -0.17, -0.02, 0.9}, {"flame", 0.46, 0.7, 0.19, -0.08, 0.9},
			{"flame", 0.56, 1, 0.02, 0.07, 1}, {"flame", 0.3, 0.6, 0.02, -0.13, 1, true}},
	}
end

do -- storm: a dark cloud gathers above the object and lightning strikes it
	local layers = {
		Shade(2.4, 2.4 * GROUND * 1.3, FOOT, 0.3),
		Pool(1.1, {0.4, 0.65}),
		{t = "glow", layer = "ARTWORK", w = 0.5, y = FOOT + 0.1, tone = "light", a = {0.15, 0.3}, lock = 0.4,
			anims = {{"pulse", 0.5, 1, 1.4}}},
	}
	for i = 1, 3 do
		layers[#layers + 1] = {t = "bolt", layer = "ARTWORK", sub = 1, w = 0.42, h = 1.3, y = FOOT + 0.62, tone = "white",
			a = 1, lock = 0, anims = {{"flicker", 0.32, i * 0.9, rest = {1.4, 4.2}}}}
	end
	-- the cloud: x, y (around its middle), width, height
	local cloud = {{-0.36, -0.02, 0.62, 0.36}, {-0.12, 0.07, 0.74, 0.46}, {0.14, 0.04, 0.7, 0.42}, {0.38, -0.03, 0.58, 0.34},
		{0, -0.08, 0.86, 0.34}}
	for i, puff in ipairs(cloud) do
		local x, y, w, h = puff[1], FOOT + 1.25 + puff[2], puff[3] * 1.9, puff[4] * 1.9
		local drift = {"bob", 0.03, 0.012, 3 + i * 0.4}
		layers[#layers + 1] = {t = "glow", layer = "OVERLAY", blend = "BLEND", tone = "dark", w = w, h = h, x = x, y = y,
			a = 0.82, lock = 1, anims = {drift}}
		layers[#layers + 1] = {t = "glow", layer = "OVERLAY", sub = 1, tone = "base", w = w * 0.8, h = h * 0.75, x = x,
			y = y - h * 0.05, a = {0.16, 0.32}, anims = {drift, {"pulse", 0.6, 1, 2 + i * 0.3}}}
	end
	layers[#layers + 1] = Core(0.22, FOOT + 0.04, {0.15, 0.6})
	E.storm = {
		wave = {flat = GROUND, y = FOOT, gain = 0.8},
		layers = layers,
		icon = {{"glow", 1, 0.5, 0, -0.34, 0.8}, {"bolt", 0.44, 0.8, -0.06, -0.08, 1, true}, {"glow", 0.8, 0.5, -0.14, 0.3, 0.5},
			{"glow", 0.8, 0.5, 0.16, 0.32, 0.45}},
	}
end

do -- beam: a column of light rising from the object
	local layers = {
		{t = "glow", layer = "BACKGROUND", sub = -1, blend = "BLEND", tone = "dark", w = 1.5, h = 2.8, y = 0.75, a = 0.2, lock = 1},
		Pool(1.1),
		{t = "flare", layer = "BACKGROUND", sub = 1, w = 1.9, h = 0.55, y = FOOT, tone = "light", a = {0.25, 0.6}, lock = 0},
		{t = "beam", layer = "ARTWORK", w = 0.66, h = 2, y = FOOT + 1, grow = {0.9, 1.05}, tone = "base", a = {0.5, 0.85},
			anims = {{"breathe", 1, {1.12, 1}, 1.8, origin = "BOTTOM"}}},
		{t = "beam", layer = "ARTWORK", sub = 1, w = 0.3, h = 1.9, y = FOOT + 0.95, grow = {0.9, 1.05}, tone = "white",
			a = {0.5, 0.95}, lock = 0.4, anims = {{"breathe", 1, {1.15, 1}, 1.3, origin = "BOTTOM"}}},
	}
	for i = 1, 6 do
		layers[#layers + 1] = {t = "glow", layer = "OVERLAY", w = 0.12, y = FOOT + 0.05, tone = "light", a = 1, lock = 0,
			anims = {{"rise", 0, 1.55, 2 + 0.15 * i, i / 6, jitter = {-0.09, 0.09, 0, 0.05}, grow = {1, 0.5}}}}
	end
	-- two motes winding around the column
	for i = 1, 2 do
		local path = Ellipse(16, 0.17, 0.05, 0, 0, FOOT + 0.45 * i)
		layers[#layers + 1] = {t = "glow", layer = "OVERLAY", sub = 1, w = 0.11, tone = "white", a = {0.4, 0.95}, lock = 0,
			anims = {{"orbit", path, 1.6 + 0.3 * i, i / 2}}}
	end
	layers[#layers + 1] = Core(0.3, FOOT, {0.35, 0.9})
	E.beam = {
		wave = {flat = GROUND, y = FOOT, w = 0.9},
		layers = layers,
		icon = {{"glow", 1, 0.46, 0, -0.3, 0.9}, {"beam", 0.62, 0.96, 0, 0.02, 1}, {"beam", 0.3, 0.9, 0, 0.02, 1, true}},
	}
end

do -- geyser: a fountain of light thrown up from the object
	local layers = {
		Shade(2.4, 2.4 * GROUND * 1.3, FOOT, 0.3),
		Pool(1.2),
		{t = "beam", layer = "ARTWORK", w = 0.75, h = 0.9, y = FOOT + 0.45, tone = "base", a = {0.55, 0.9},
			anims = {{"breathe", {1, 0.85}, {1, 1.12}, 0.45, origin = "BOTTOM"}}},
		{t = "beam", layer = "ARTWORK", sub = 1, w = 0.34, h = 0.8, y = FOOT + 0.4, tone = "white", a = {0.5, 0.95}, lock = 0.4,
			anims = {{"breathe", {1, 0.85}, {1, 1.12}, 0.45, origin = "BOTTOM"}}},
	}
	for i = 1, 12 do
		local star = i % 3 == 0
		layers[#layers + 1] = {t = star and "flare" or "glow", layer = "OVERLAY", w = star and 0.3 or 0.14, y = FOOT,
			tone = "white", a = 1, lock = 0, anims = {{"fountain", 1, 1.1, 1.5, i / 12}}}
	end
	layers[#layers + 1] = Core(0.3, FOOT + 0.03)
	E.geyser = {
		wave = {flat = GROUND, y = FOOT, gain = 0.7},
		layers = layers,
		icon = {{"glow", 1, 0.5, 0, -0.32, 0.9}, {"beam", 0.5, 0.7, 0, -0.1, 1}, {"glow", 0.2, 0.2, -0.26, 0.2, 1, true},
			{"glow", 0.18, 0.18, 0.28, 0.12, 1, true}, {"flare", 0.34, 0.34, 0.06, 0.3, 1, true}},
	}
end

do -- beacon: a crystal floating above the object
	local hover = 0.62
	local float = {"bob", 0, 0.035, 1.7}
	E.beacon = {
		wave = {flat = GROUND, y = FOOT, w = 0.8},
		layers = {
			Shade(1.7, 1.7 * GROUND * 1.3, FOOT, 0.3),
			Pool(0.95, {0.5, 0.85}),
			{t = "beam", layer = "BACKGROUND", sub = 1, w = 0.22, h = 0.48, y = FOOT + 0.24, tone = "light", a = {0.4, 0.75}, lock = 0},
			{t = "glow", layer = "ARTWORK", w = 1.1, y = hover, tone = "base", a = {0.5, 0.9}, anims = {float, {"breathe", 0.95, 1.08, 2.2}}},
			{t = "gem", layer = "ARTWORK", sub = 1, blend = "BLEND", w = 0.52, y = hover, tone = "gem", a = {0.85, 1}, lock = 0.8,
				anims = {float}},
			{t = "flare", layer = "OVERLAY", w = 0.3, x = -0.04, y = hover + 0.09, tone = "white", a = {0.3, 0.85}, lock = 0,
				anims = {float, {"pulse", 0.2, 1, 1.1}}},
		},
		icon = {{"glow", 0.9, 0.4, 0, -0.33, 0.8}, {"beam", 0.2, 0.44, 0, -0.15, 0.8}, {"glow", 0.85, 0.85, 0, 0.15, 0.6},
			{"gem", 0.52, 0.52, 0, 0.15, 1, true}},
	}
end

do -- orbit: three motes on tilted orbits around the object, like around a nucleus
	local layers = {
		Shade(1.9, nil, 0, 0.28),
		{t = "glow", layer = "BACKGROUND", w = 0.8, tone = "base", a = {0.4, 0.65}, anims = {{"breathe", 0.92, 1.06, 2}}},
	}
	local radius = 0.46
	-- tilt, seconds per turn, phase
	for _, orbit in ipairs({{0, 2.6, 0}, {1.05, 3, 0.33}, {-1.05, 2.3, 0.66}}) do
		local tilt, seconds, phase = orbit[1], orbit[2], orbit[3]
		local width = 2 * radius / (2 * RING)
		layers[#layers + 1] = {t = "ring", layer = "BACKGROUND", sub = 1, w = width, h = width * GROUND, rot = tilt,
			tone = "light", a = {0.14, 0.3}}
		local path = Ellipse(24, radius, radius * GROUND, tilt)
		for k = 4, 0, -1 do
			layers[#layers + 1] = {t = "glow", layer = "OVERLAY", sub = k == 0 and 1 or 0, w = 0.2 * 0.9 ^ k,
				tone = k == 0 and "white" or "light", a = k == 0 and {0.75, 1} or {0.5 * 0.78 ^ k, 0.85 * 0.78 ^ k},
				lock = k == 0 and 0.7 or 0, anims = {{"orbit", path, seconds, phase - k / 24}}}
		end
	end
	layers[#layers + 1] = Core(0.3)
	E.orbit = {
		wave = {gain = 0.6},
		layers = layers,
		icon = {{"ring", 1, 0.46, 0, 0, 0.5}, {"glow", 0.32, 0.32, -0.33, 0.03, 1, true}, {"glow", 0.3, 0.3, 0.3, -0.1, 1, true},
			{"glow", 0.2, 0.2, 0.12, 0.14, 0.7}, {"flare", 0.3, 0.3, 0, 0, 0.6, true}},
	}
end

do -- spirit: two wisps dancing a figure of eight around the object, trailing light
	local layers = {
		Shade(2, nil, 0, 0.26),
		{t = "glow", layer = "BACKGROUND", w = 1.3, tone = "base", a = {0.3, 0.5}, anims = {{"breathe", 0.94, 1.06, 2.4}}},
	}
	-- size, seconds per figure, phase
	for _, spirit in ipairs({{1, 3.6, 0}, {0.72, 4.8, 0.5}}) do
		local size, seconds, phase = spirit[1], spirit[2], spirit[3]
		local path = Eight(32, 0.6 * size, 0.25 * size, 0.04)
		for k = 6, 1, -1 do
			layers[#layers + 1] = {t = "glow", layer = "ARTWORK", w = 0.24 * size * 0.9 ^ k, tone = "light",
				a = {0.5 * 0.85 ^ k, 0.85 * 0.85 ^ k}, anims = {{"orbit", path, seconds, phase - k / 32}}}
		end
		layers[#layers + 1] = {t = "glow", layer = "OVERLAY", w = 0.32 * size, tone = "white", a = {0.75, 1},
			anims = {{"orbit", path, seconds, phase}}}
		layers[#layers + 1] = {t = "flare", layer = "OVERLAY", sub = 1, w = 0.46 * size, tone = "white", a = {0.55, 1}, lock = 0.3,
			anims = {{"orbit", path, seconds, phase}, {"spin", 6}}}
	end
	E.spirit = {
		ghost = "halo", wave = {gain = 0.5},
		layers = layers,
		icon = {{"glow", 0.9, 0.9, 0, 0, 0.35}, {"arcs", 0.95, 0.95, 0, 0, 1}, {"flare", 0.42, 0.42, -0.41, 0.03, 1, true},
			{"flare", 0.36, 0.36, 0.41, -0.03, 1, true}},
	}
end

do -- ripple: rings spreading on the ground around the object
	local layers = {
		Shade(2.6, 2.6 * GROUND * 1.3, FOOT, 0.3),
		Pool(1.2),
	}
	for i = 1, 3 do
		layers[#layers + 1] = {t = "ring", layer = "ARTWORK", w = 1, h = GROUND, y = FOOT, tone = "light", a = {0.6, 1},
			anims = {{"expand", 0.3, 1.7, 2.4, (i - 1) / 3}}}
	end
	layers[#layers + 1] = Core(0.26, FOOT, {0.25, 0.8})
	E.ripple = {
		wave = {flat = GROUND, y = FOOT, w = 1.1}, ping = false,
		layers = layers,
		icon = {{"glow", 1, 0.5, 0, 0, 0.5}, {"ring", 1, 0.44, 0, 0, 0.7}, {"ring", 0.62, 0.27, 0, 0, 0.9},
			{"ring", 0.28, 0.12, 0, 0, 1, true}},
	}
end

do -- sparkle: stars lighting up and going out all around the object
	local layers = {
		Shade(1.9, nil, 0, 0.28),
		{t = "glow", layer = "BACKGROUND", w = 1.55, tone = "base", a = {0.4, 0.62},
			anims = {{"breathe", 0.95, 1.06, 2.6}, {"pulse", 0.85, 1, 1.9}}},
	}
	for i = 1, 3 do
		layers[#layers + 1] = {t = "glow", layer = "ARTWORK", w = 0.11, x = (i - 2) * 0.24, y = -0.3, tone = "light", a = 0.75,
			lock = 0, anims = {{"rise", 0, 0.8, 3.5, i / 3, jitter = {-0.05, 0.05, 0, 0.1}}}}
	end
	for i = 1, 6 do
		layers[#layers + 1] = {t = "flare", layer = "OVERLAY", w = 0.55, tone = "white", a = 1, lock = 0,
			anims = {{"twinkle", 0.4, i / 6}}}
	end
	E.sparkle = {
		ping = false,
		layers = layers,
		icon = {{"glow", 1, 1, 0, 0, 0.45}, {"flare", 0.64, 0.64, -0.12, 0.1, 1, true}, {"flare", 0.42, 0.42, 0.22, -0.2, 0.9, true},
			{"flare", 0.3, 0.3, 0.2, 0.26, 0.8, true}},
	}
end

-- Every effect also gets: a ring that pings outwards now and then, a ring that closes in
-- when the object comes in reach and a flash at the same moment.
for _, effect in pairs(E) do
	local wave = effect.wave or {}
	wave.t, wave.flat, wave.y, wave.w, wave.gain = wave.t or "ring", wave.flat or 1, wave.y or 0, wave.w or 1, wave.gain or 1
	effect.wave = wave
	local layers = effect.layers
	if effect.ping ~= false then
		layers[#layers + 1] = {t = wave.t, layer = "BORDER", w = wave.w, h = wave.w * wave.flat, y = wave.y, tone = "light",
			a = {0.5 * wave.gain, 0.65 * wave.gain}, lock = 0, anims = {{"expand", 0.55, 1.45, 1, 0.6, hold = 2.2}}}
	end
	layers[#layers + 1] = {t = wave.t, layer = "ARTWORK", sub = 7, w = wave.w, h = wave.w * wave.flat, y = wave.y,
		tone = "light", a = wave.gain, lock = 0, trigger = "lockon"}
	layers[#layers + 1] = {t = "flare", layer = "OVERLAY", sub = 7, w = 0.9, y = wave.y, tone = "white", a = 1, lock = 0,
		trigger = "flash"}
end


--[[ A glow: one frame showing one effect at a time ]]--

local Glow = {}
Glow.__index = Glow

local function Pair(value, t)
	if type(value) == "table" then return Lerp(value[1], value[2], t) end
	return value or 0
end

-- overshoot towards the end (easeOutBack), for things that snap into place
local function Back(t)
	local s = t - 1
	return 1 + 2.70158 * s * s * s + 1.70158 * s * s
end

local function Build(glow, key)
	local def = E[key]
	local holder = CreateFrame("Frame", nil, glow.body)
	holder:SetSize(1, 1)
	holder:SetPoint("CENTER")
	holder:Hide()
	local built = {holder = holder, items = {}, shaped = {}, groups = {}, triggers = {}}
	for _, spec in ipairs(def.layers) do
		local tex = holder:CreateTexture(nil, spec.layer or "ARTWORK", nil, spec.sub or 0)
		tex:SetTexture(MEDIA .. spec.t .. ".tga")
		tex:SetBlendMode(spec.blend or "ADD")
		if tex.SetSnapToPixelGrid then
			tex:SetSnapToPixelGrid(false)
			tex:SetTexelSnappingBias(0)
		end
		local item = {tex = tex, spec = spec, holder = holder, x = spec.x or 0, y = spec.y or 0}
		Place(item, item.x, item.y)
		built.items[#built.items + 1] = item
		-- size and rotation: set once, unless they follow the state (then on every blend frame)
		if spec.grow or type(spec.rot) == "table" then
			built.shaped[#built.shaped + 1] = item
		else
			tex:SetSize((spec.w or 1) * REF, (spec.h or spec.w or 1) * REF)
			if spec.rot then tex:SetRotation(spec.rot) end
		end
		for _, anim in ipairs(spec.anims or {}) do
			local group, delay = Builders[anim[1]](item, anim)
			built.groups[#built.groups + 1] = {group = group, delay = delay or 0}
		end
		if spec.trigger then
			built.triggers[#built.triggers + 1] = Triggers[spec.trigger](item)
		end
	end
	glow.built[key] = built
	if glow.mask then
		for _, item in ipairs(built.items) do pcall(item.tex.AddMaskTexture, item.tex, glow.mask) end
	end
	return built
end

-- Paints every layer for the current blend of states, color and intensity.
local function Paint(glow)
	local built = glow.current
	if not built then return end
	local ready, locked = glow.ready, glow.locked
	local eased = Back(glow.readyRaw)
	local grey = 0.75 * locked
	local r, g, b = Lerp(glow.r, GREY, grey), Lerp(glow.g, GREY, grey), Lerp(glow.b, GREY, grey)
	local tones = glow.tones
	tones.base[1], tones.base[2], tones.base[3] = r, g, b
	tones.light[1], tones.light[2], tones.light[3] = Lerp(r, 1, 0.55), Lerp(g, 1, 0.55), Lerp(b, 1, 0.55)
	tones.white[1], tones.white[2], tones.white[3] = Lerp(r, 1, 0.75), Lerp(g, 1, 0.75), Lerp(b, 1, 0.75)
	tones.gem[1], tones.gem[2], tones.gem[3] = Lerp(r, 1, 0.25), Lerp(g, 1, 0.25), Lerp(b, 1, 0.25)
	local intensity = glow.intensity
	for _, item in ipairs(built.items) do
		local spec = item.spec
		local tone = tones[spec.tone or "base"]
		local alpha = Pair(spec.a, ready) * Lerp(1, spec.lock or 0.5, locked) * intensity
		item.tex:SetVertexColor(tone[1], tone[2], tone[3], alpha >= 1 and 1 or alpha)
	end
	for _, item in ipairs(built.shaped) do
		local spec, tex = item.spec, item.tex
		local t = spec.ease == "back" and eased or ready
		local grow = spec.grow and Pair(spec.grow, t) or 1
		tex:SetSize(max((spec.w or 1) * REF * grow, 0.01), max((spec.h or spec.w or 1) * REF * grow, 0.01))
		if spec.rot then tex:SetRotation(Pair(spec.rot, t)) end
	end
end

local function Approach(value, target, step)
	if value < target then return min(value + step, target) end
	return max(value - step, target)
end

-- Runs only while a state or color blends, or loops wait for their turn to start.
local function OnUpdate(frame, elapsed)
	local glow = frame.glow
	local busy = false
	local pending = glow.pending
	if #pending > 0 then
		local now = GetTime()
		for i = #pending, 1, -1 do
			local entry = pending[i]
			if now >= entry.at then
				entry.group:Play()
				table.remove(pending, i)
			end
		end
		busy = #pending > 0
	end
	if glow.blending then
		local step = elapsed / BLEND_TIME
		glow.readyRaw = Approach(glow.readyRaw, glow.targetReady, step)
		glow.ready = glow.readyRaw
		glow.locked = Approach(glow.locked, glow.targetLocked, step)
		local blend = min(elapsed * 8, 1)
		glow.r, glow.g, glow.b = Lerp(glow.r, glow.tr, blend), Lerp(glow.g, glow.tg, blend), Lerp(glow.b, glow.tb, blend)
		local done = glow.readyRaw == glow.targetReady and glow.locked == glow.targetLocked
			and math.abs(glow.r - glow.tr) + math.abs(glow.g - glow.tg) + math.abs(glow.b - glow.tb) < 0.01
		if done then
			glow.r, glow.g, glow.b = glow.tr, glow.tg, glow.tb
			glow.blending = false
		end
		Paint(glow)
		busy = busy or not done
	end
	if not busy then frame:SetScript("OnUpdate", nil) end
end

local function Wake(glow)
	glow.root:SetScript("OnUpdate", OnUpdate)
end

local function SetSpeed(built, speed)
	for _, entry in ipairs(built.groups) do
		if entry.group.SetAnimationSpeedMultiplier then entry.group:SetAnimationSpeedMultiplier(speed) end
	end
end

local function Start(glow)
	local built = glow.current
	if not built or not glow.root:IsShown() then return end
	built.holder:Show()
	local now = GetTime()
	wipe(glow.pending)
	for _, entry in ipairs(built.groups) do
		entry.group:Stop()
		if entry.delay > 0 then
			glow.pending[#glow.pending + 1] = {group = entry.group, at = now + entry.delay}
		else
			entry.group:Play()
		end
	end
	SetSpeed(built, SPEED[glow.state] or 1)
	if #glow.pending > 0 then Wake(glow) end
end

local function Stop(glow)
	wipe(glow.pending)
	local built = glow.current
	if not built then return end
	for _, entry in ipairs(built.groups) do entry.group:Stop() end
	for _, group in ipairs(built.triggers) do group:Stop() end
end

-- Creates a glow. Hidden until Attach.
function FX.New()
	local root = CreateFrame("Frame")
	root:SetSize(1, 1)
	root:Hide()
	local body = CreateFrame("Frame", nil, root)
	body:SetSize(1, 1)
	body:SetPoint("CENTER")
	-- arrival: the light gathers onto the object
	local arrive = body:CreateAnimationGroup()
	ScaleAnim(arrive, 1.4, 1, 0.45, nil, "OUT")
	AlphaAnim(arrive, 0, 1, 0.3)
	local glow = setmetatable({
		root = root, body = body, arrive = arrive, built = {}, pending = {},
		r = 1, g = 1, b = 1, tr = 1, tg = 1, tb = 1,
		ready = 0, readyRaw = 0, locked = 0, targetReady = 0, targetLocked = 0,
		state = "far", intensity = 1, size = REF,
		tones = {base = {1, 1, 1}, light = {1, 1, 1}, white = {1, 1, 1}, gem = {1, 1, 1}, dark = {0, 0, 0}},
	}, Glow)
	root.glow = glow
	return glow
end

-- Switches the drawn effect; true if it changed (the caller paints).
local function Switch(glow, key)
	if not E[key] then key = "aura" end
	if glow.key == key then return false end
	local wasShown = glow.root:IsShown()
	if glow.current then
		Stop(glow)
		glow.current.holder:Hide()
	end
	glow.key = key
	glow.effect = E[key]
	glow.current = glow.built[key] or Build(glow, key)
	if wasShown then Start(glow) end
	return true
end

function Glow:SetEffect(key)
	if Switch(self, key) then Paint(self) end
end

-- Everything for a new target at once, painted once: effect, size, intensity (%), color
-- and state, without blending.
function Glow:Setup(key, size, percent, r, g, b, state)
	self:SetSize(size)
	self.intensity = percent / 100
	self.r, self.g, self.b, self.tr, self.tg, self.tb = r, g, b, r, g, b
	self.state = state
	self.targetReady = state == "ready" and 1 or 0
	self.targetLocked = state == "locked" and 1 or 0
	self.readyRaw, self.ready, self.locked = self.targetReady, self.targetReady, self.targetLocked
	self.blending = false
	Switch(self, key)
	Paint(self)
end

function Glow:SetSize(size)
	self.size = size
	self.body:SetScale(max(size, 1) / REF)
end

function Glow:SetIntensity(percent)
	self.intensity = percent / 100
	Paint(self)
end

-- Blends to a color; instant for the first color of a new target.
function Glow:SetColor(r, g, b, instant)
	self.tr, self.tg, self.tb = r, g, b
	if instant then
		self.r, self.g, self.b = r, g, b
		Paint(self)
	else
		self.blending = true
		Wake(self)
	end
end

-- "far", "ready" or "locked" (the game refuses it for now).
function Glow:SetState(state, instant)
	local previous = self.state
	self.state = state
	self.targetReady = state == "ready" and 1 or 0
	self.targetLocked = state == "locked" and 1 or 0
	if self.current then SetSpeed(self.current, SPEED[state] or 1) end
	if instant then
		self.readyRaw, self.ready, self.locked = self.targetReady, self.targetReady, self.targetLocked
		Paint(self)
		return
	end
	if state == "ready" and previous ~= "ready" and self.current and self.root:IsShown() then
		for _, group in ipairs(self.current.triggers) do
			group:Stop()
			group:Play()
		end
	end
	self.blending = true
	Wake(self)
end

-- Places the glow on a frame (a nameplate), offsetY below or above its middle.
function Glow:Attach(anchor, offsetY, followAlpha)
	local root = self.root
	root:SetParent(anchor)
	local ok, level = pcall(anchor.GetFrameLevel, anchor)
	if ok and type(level) == "number" then root:SetFrameLevel(max(level - 1, 0)) end -- under the name, which stays readable
	self:Move(anchor, offsetY, followAlpha)
	root:Show()
	self.arrive:Stop()
	self.arrive:Play()
	Start(self)
end

function Glow:Move(anchor, offsetY, followAlpha)
	local root = self.root
	root:ClearAllPoints()
	root:SetPoint("CENTER", anchor, "CENTER", 0, offsetY or 0)
	root:SetIgnoreParentAlpha(not followAlpha)
end

function Glow:Detach()
	Stop(self)
	self.arrive:Stop()
	local root = self.root
	root:SetScript("OnUpdate", nil)
	root:Hide()
	root:ClearAllPoints()
	root:SetParent(nil)
	if self.blending then
		self.blending = false
		self.r, self.g, self.b = self.tr, self.tg, self.tb
		self.readyRaw, self.ready, self.locked = self.targetReady, self.targetReady, self.targetLocked
		Paint(self)
	end
end

function Glow:IsAttached()
	return self.root:IsShown()
end

-- Masks every layer with a mask texture (the silhouette), or removes it (nil).
function Glow:SetMask(mask)
	if mask == self.mask then return true end
	local ok = true
	for _, built in pairs(self.built) do
		for _, item in ipairs(built.items) do
			if self.mask then pcall(item.tex.RemoveMaskTexture, item.tex, self.mask) end
			if mask and not pcall(item.tex.AddMaskTexture, item.tex, mask) then ok = false end
		end
	end
	self.mask = mask
	return ok
end

-- Where the glow is on the screen, in UIParent units, and its size there; nil if unknown.
function Glow:ScreenPosition()
	local root = self.root
	local ok, x, y = pcall(root.GetCenter, root)
	local okScale, scale = pcall(root.GetEffectiveScale, root)
	if not (ok and okScale and type(x) == "number" and type(y) == "number" and type(scale) == "number") then return end
	if issecretvalue and (issecretvalue(x) or issecretvalue(y) or issecretvalue(scale)) then return end
	local ratio = scale / UIParent:GetEffectiveScale()
	return x * ratio, y * ratio, ratio
end


--[[ Ghost: the light spreads and fades where it was when its nameplate goes away ]]--

local ghost

function FX.Ghost(glow)
	if not glow.current or glow.arrive:IsPlaying() then return end
	local x, y, ratio = glow:ScreenPosition()
	if not x then return end
	if not ghost then
		ghost = CreateFrame("Frame", nil, UIParent)
		ghost:SetFrameStrata("BACKGROUND")
		ghost:SetSize(1, 1)
		ghost:Hide()
		ghost.band = ghost:CreateTexture(nil, "BACKGROUND")
		ghost.band:SetBlendMode("ADD")
		ghost.band:SetPoint("CENTER")
		ghost.ring = ghost:CreateTexture(nil, "BORDER")
		ghost.ring:SetBlendMode("ADD")
		ghost.ring:SetPoint("CENTER")
		local group = ghost:CreateAnimationGroup()
		ScaleAnim(group, 1, 1.4, 0.4, nil, "OUT")
		AlphaAnim(group, 1, 0, 0.4)
		group:SetScript("OnFinished", function() ghost:Hide() end)
		ghost.group = group
	end
	local effect = glow.effect
	local wave = effect.wave
	local size = glow.size * ratio
	local spread = effect.ghost == "halo" and 1 or 1.5
	ghost.band:SetTexture(MEDIA .. (effect.ghost or "glow") .. ".tga")
	ghost.ring:SetTexture(MEDIA .. wave.t .. ".tga")
	ghost.band:SetSize(size * spread * wave.w, size * spread * wave.w * wave.flat)
	ghost.ring:SetSize(size * wave.w, size * wave.w * wave.flat)
	local alpha = glow.intensity * Lerp(1, 0.5, glow.locked)
	local r, g, b = glow.r, glow.g, glow.b
	ghost.band:SetVertexColor(r, g, b, min(0.7 * alpha, 1))
	ghost.ring:SetVertexColor(Lerp(r, 1, 0.55), Lerp(g, 1, 0.55), Lerp(b, 1, 0.55), min(alpha, 1))
	ghost:ClearAllPoints()
	ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y + wave.y * size)
	ghost.group:Stop()
	ghost:Show()
	ghost.group:Play()
end


--[[ Menu icons: a small drawing of each effect ]]--

-- Draws an effect's icon on a button; returns the textures with their alpha and
-- whether they are whitened, for Tint.
function FX.DrawIcon(button, key, side)
	local layers = {}
	for depth, layer in ipairs(E[key].icon or {}) do
		local tex = button:CreateTexture(nil, "ARTWORK", nil, min(depth, 7))
		tex:SetTexture(MEDIA .. layer[1] .. ".tga")
		tex:SetBlendMode(layer[1] == "gem" and "BLEND" or "ADD")
		tex:SetSize(layer[2] * side, layer[3] * side)
		tex:SetPoint("CENTER", layer[4] * side, layer[5] * side)
		layers[#layers + 1] = {tex = tex, alpha = layer[6], hot = layer[7]}
	end
	return layers
end

function FX.TintIcon(layers, r, g, b)
	for _, layer in ipairs(layers) do
		if layer.hot then
			layer.tex:SetVertexColor(Lerp(r, 1, 0.5), Lerp(g, 1, 0.5), Lerp(b, 1, 0.5), layer.alpha)
		else
			layer.tex:SetVertexColor(r, g, b, layer.alpha)
		end
	end
end

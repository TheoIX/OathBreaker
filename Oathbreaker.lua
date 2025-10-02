--[[
OathBreaker.lua - Turtle WoW 1.12 (Lua 5.0 safe) - v1.4
Author: Theodan

NEW in v1.4 (Swing-gated equips using your swing timer):
  • Adds a post-swing gate that waits for your main-hand white swing to land,
    detected via swing timer globals `st_timer` and `st_timerMax`, then equips
    ~50 ms after that edge. No combat-log reads.
  • Toggle with /obswinggate on|off (default: ON). If OFF, behavior is
    identical to v1.3 timing.

v1.3 recap (Priority-only cooldowns):
  • Per-weapon soft cooldowns after Holy Strength proc (default 13s).
  • When anchor CD reaches 0, snap back to anchor immediately (priority only).
  • Round-robin mode ignores cooldowns.

Key slash commands:
  /oathbreaker                 -- run logic once (macro/keypress)
  /obmode priority | round     -- choose anchor-first vs round-robin
  /obanchor <idx|name>         -- set anchor
  /obcd <seconds> | /obcdlist  -- set/list soft cooldown (priority only)
  /obswinggate on|off          -- enable/disable post-swing gating
]]

-- ===== Fast locals (do NOT localize DEFAULT_CHAT_FRAME) =====
local UIParent             = UIParent
local GameTooltip          = GameTooltip
local GameTooltipTextLeft1 = GameTooltipTextLeft1
local GetTime              = GetTime
local EquipItemByName      = EquipItemByName
local GetInventoryItemLink = GetInventoryItemLink
local GetContainerNumSlots = GetContainerNumSlots
local GetContainerItemLink = GetContainerItemLink
local UseContainerItem     = UseContainerItem
local RunMacroText         = RunMacroText
local PickupContainerItem  = PickupContainerItem
local PickupInventoryItem  = PickupInventoryItem
local CursorHasItem        = CursorHasItem
local ClearCursor          = ClearCursor

local floor                = math.floor
local tinsert              = table.insert
local getn                 = table.getn
local strlower, strfind    = string.lower, string.find
local gsub                 = string.gsub
local sub                  = string.sub
local sfind                = string.find

-- Optional PlayerBuff APIs (commonly present on Turtle 1.12)
local GetPlayerBuff         = _G.GetPlayerBuff
local GetPlayerBuffTimeLeft = _G.GetPlayerBuffTimeLeft
local GetPlayerBuffTexture  = _G.GetPlayerBuffTexture

-- ===== Constants & state =====
OB_PREFIX       = "[OathBreaker] "
HOLY_STRENGTH   = "Holy Strength"
HOLY_ICON_SUB   = "spell_holy_blessingofstrength"

OB_Queue        = {}   -- { "Weapon Name", ... }
OB_NextIndex    = 1

-- Detection state
OB_Primed       = false
OB_LastCount    = 0
OB_LastExpSet   = {}   -- set[exp]=true for last scan (fingerprint mode)

-- Equip pending state (press-to-press retries)
OB_PendingName  = nil

-- Chat verbosity
OB_Quiet        = true  -- default: only print on successful swaps

-- Priority mode state
OB_ModePriority = true   -- priority (anchor-first) enabled by default
OB_AnchorIndex  = 1      -- first item in queue is the anchor
OB_Chasing      = false  -- after anchor proc, trying B/C...
OB_BaseCount    = 0      -- fallback baseline if fingerprints are unavailable
OB_ChaseIndex   = 2      -- next weapon to try in priority mode
OB_AnchorExp    = nil    -- expiration fingerprint of the *anchor* HS instance

-- NEW: Per-weapon cooldowns (priority mode ONLY)
OB_CD_WINDOW    = 13     -- default seconds (can be changed via /obcd)
OB_Cooldowns    = {}     -- map[strlower(name)] = expiresAt (GetTime-based)

-- =====================
-- Post-swing gate (uses swing timer globals st_timer/st_timerMax)
-- =====================
local OB_SwingGate        = true      -- default ON; toggle with /obswinggate
local OB_POST_SWING_DELAY = 0.05      -- seconds after swing edge to equip
local OB_WaitForNextSwing = false
local OB_GatedName        = nil
local OB_LastSwingTS      = 0
local OB_prevPct          = nil       -- previous st_timer / st_timerMax

-- Delay ticker that fires ~50ms after a detected swing edge
local OB_DelayFrame = CreateFrame("Frame")
OB_DelayFrame:Hide()
OB_DelayFrame:SetScript("OnUpdate", function()
  if not OB_WaitForNextSwing or not OB_GatedName then OB_DelayFrame:Hide(); return end
  local t = (type(GetTime)=="function" and GetTime()) or 0
  if (t - (OB_LastSwingTS or 0)) >= (OB_POST_SWING_DELAY or 0.05) then
    local nm = OB_GatedName
    OB_WaitForNextSwing = false
    OB_GatedName = nil
    OB_DelayFrame:Hide()
    -- Hand back to normal equip path
    OB_PendingName = nm
    OathBreaker_Pulse()
  end
end)

-- OnUpdate watcher that detects the rising edge of st_timer → st_timerMax
local OB_ST_Frame = CreateFrame("Frame")
OB_ST_Frame:Hide()
OB_ST_Frame:SetScript("OnUpdate", function()
  if not OB_WaitForNextSwing or not OB_SwingGate then return end
  local cur, max = _G.st_timer, _G.st_timerMax
  if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then OB_prevPct = nil; return end
  local curPct = cur / max
  -- Edge: near zero last frame, near full this frame (swing just happened)
  if OB_prevPct and OB_prevPct < 0.08 and curPct > 0.90 then
    local inRangeOK = true
    if type(_G.SP_ST_InRange) == "function" then inRangeOK = _G.SP_ST_InRange() and true or false end
    if inRangeOK then
      OB_LastSwingTS = (type(GetTime)=="function" and GetTime()) or 0
      OB_DelayFrame:Show()
    end
  end
  OB_prevPct = curPct
end)

-- Public entry: call this instead of setting OB_PendingName directly
function OB_RequestPostSwingSwap(name)
  if not name or name == "" then return end
  if not OB_SwingGate then
    OB_PendingName = name
    return
  end
  OB_GatedName = name
  OB_WaitForNextSwing = true
  OB_prevPct = nil
  OB_ST_Frame:Show()
end

-- ===== Chat helpers =====
local function Frame()
  local f = DEFAULT_CHAT_FRAME or ChatFrame1
  if f and f.AddMessage then return f end
  return nil
end

local function OB_Msg(msg, r, g, b)
  local f = Frame(); if not f then return end
  f:AddMessage(OB_PREFIX .. (msg or ""), r or 1, g or 1, b or 0)
end

local function OB_Err(msg)
  local f = Frame(); if not f then return end
  f:AddMessage(OB_PREFIX .. (msg or ""), 1, 0.3, 0.3)
end

-- ===== Utils =====
local function Trim(s)
  if not s then return "" end
  local s2 = gsub(s, "^%s+", "")
  s2 = gsub(s2, "%s+$", "")
  return s2
end

-- Lua 5.0-safe: extract [Name] from a WoW link string; return nil if not a link
local function BracketName(s)
  if not s then return nil end
  local a = sfind(s, "%[")
  if not a then return nil end
  local c = sfind(s, "%]", a + 1)
  if not c then return nil end
  return sub(s, a + 1, c - 1)
end

-- Accept plain names OR full item links; always return a plain item name
local function NormalizeItemInput(s)
  if not s then return "" end
  local nameFromLink = BracketName(s)
  if nameFromLink and nameFromLink ~= "" then
    return nameFromLink
  end
  return Trim(s)
end

local function ExtractNameFromLink(link)
  if not link then return nil end
  return BracketName(link)
end

local function IsMainHandEquipped(name)
  if not name or name == "" then return false end
  if type(GetInventoryItemLink) ~= "function" then return false end
  local link = GetInventoryItemLink("player", 16)
  if not link then return false end
  local eq = ExtractNameFromLink(link)
  return eq and (strlower(eq) == strlower(name))
end

local function GetEquippedMHName()
  if type(GetInventoryItemLink) ~= "function" then return nil end
  local link = GetInventoryItemLink("player", 16)
  if not link then return nil end
  return ExtractNameFromLink(link)
end

local function AdvanceIdx()
  OB_NextIndex = OB_NextIndex + 1
  if OB_NextIndex > getn(OB_Queue) then OB_NextIndex = 1 end
end

local function AdvanceChase()
  local n = getn(OB_Queue)
  if n <= 1 then OB_ChaseIndex = 1; return end
  OB_ChaseIndex = OB_ChaseIndex + 1
  if OB_ChaseIndex > n then OB_ChaseIndex = 1 end
  if OB_ChaseIndex == OB_AnchorIndex then
    OB_ChaseIndex = OB_ChaseIndex + 1
    if OB_ChaseIndex > n then OB_ChaseIndex = 1 end
  end
end

-- ===== Cooldown helpers (priority mode only) =====
local function Now()
  return (type(GetTime)=="function" and GetTime()) or 0
end

local function KeyFor(name)
  return name and strlower(name) or nil
end

local function StartCooldown(name)
  if not name or name == "" then return end
  if not OB_ModePriority then return end -- only track in priority mode
  OB_Cooldowns[KeyFor(name)] = Now() + (OB_CD_WINDOW or 13)
end

local function SecondsLeft(name)
  if not name or name == "" then return 0 end
  local t = OB_Cooldowns[KeyFor(name)]
  if not t then return 0 end
  local left = t - Now()
  if left < 0 then left = 0 end
  return left
end

local function IsOnCooldown(name)
  return SecondsLeft(name) > 0
end

local function NextChaseCandidate()
  local n = getn(OB_Queue)
  if n == 0 then return nil, nil end
  local i = OB_ChaseIndex
  local start = i
  repeat
    local nm = OB_Queue[i]
    if i ~= OB_AnchorIndex and not IsOnCooldown(nm) then
      return i, nm
    end
    i = i + 1; if i > n then i = 1 end
  until i == start
  return nil, nil
end

-- If every non-anchor weapon is on cooldown, prefer anchor for max uptime
local function AllNonAnchorOnCooldown()
  local n = getn(OB_Queue)
  if n <= 1 then return true end
  local i
  for i = 1, n do
    if i ~= OB_AnchorIndex then
      local nm = OB_Queue[i]
      if SecondsLeft(nm) == 0 then
        return false
      end
    end
  end
  return true
end

-- ===== Equip attempt (single-press try) =====
local function TryEquipOnce(name)
  if not name or name == "" then return false end

  -- 1) Native API if present on this core
  if type(EquipItemByName) == "function" then
    EquipItemByName(name)
    if IsMainHandEquipped(name) then return true end
  end

  -- 2) Macro fallback
  if type(RunMacroText) == "function" then
    RunMacroText("/equip " .. name)
    if IsMainHandEquipped(name) then return true end
  end

  -- 3) Bag-scan soft use, then hard swap
  if type(GetContainerNumSlots) == "function" and type(GetContainerItemLink) == "function" then
    local bag
    for bag = 0, 4 do
      local slots = GetContainerNumSlots(bag) or 0
      local slot
      for slot = 1, slots do
        local link = GetContainerItemLink(bag, slot)
        if link then
          local iname = ExtractNameFromLink(link)
          if iname and strlower(iname) == strlower(name) then
            if type(UseContainerItem) == "function" then
              UseContainerItem(bag, slot)
              if IsMainHandEquipped(name) then return true end
            end
            if type(PickupContainerItem) == "function" and type(PickupInventoryItem) == "function" then
              PickupContainerItem(bag, slot)
              if CursorHasItem and CursorHasItem() then
                PickupInventoryItem(16)
                if type(ClearCursor) == "function" then ClearCursor() end
                if IsMainHandEquipped(name) then return true end
              end
            end
            return IsMainHandEquipped(name)
          end
        end
      end
    end
  end

  return IsMainHandEquipped(name)
end

-- ===== Fingerprint helpers =====
local function FingerprintCapable()
  return (type(GetPlayerBuff)=="function" and type(GetPlayerBuffTimeLeft)=="function" and type(GetPlayerBuffTexture)=="function")
end

local function FingerprintHS()
  if not FingerprintCapable() then return nil end
  local exps = {}
  local i = 0
  while true do
    local idx = GetPlayerBuff(i, "HELPFUL")
    if not idx or idx < 0 then break end
    local tex = GetPlayerBuffTexture(idx)
    if tex and strfind(strlower(tex), HOLY_ICON_SUB, 1, true) then
      local tl = GetPlayerBuffTimeLeft(idx) or 0
      local exp = floor(Now() + tl + 0.5)
      tinsert(exps, exp)
    end
    i = i + 1
  end
  if getn(exps) == 0 then return {} end
  return exps
end

local function BuildSetFromExps(exps)
  local s = {}
  local i
  for i = 1, (exps and getn(exps) or 0) do s[exps[i]] = true end
  return s
end

local function CountHS_ByTooltip()
  if not (GameTooltip and GameTooltip.SetUnitBuff and GameTooltip.SetOwner and GameTooltip.ClearLines) then
    return 0
  end
  local c = 0
  local i
  for i = 1, 40 do
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:SetUnitBuff("player", i)
    local text = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
    if text and strfind(text, HOLY_STRENGTH, 1, true) then
      c = c + 1
    end
  end
  return c
end

local function OB_CurrentHSCount()
  local exps = FingerprintHS()
  if exps then return getn(exps) end
  return CountHS_ByTooltip()
end

-- Returns true if a *new* HS appeared since last scan. Also updates OB_LastExpSet/OB_LastCount
local function IsNewHolyStrength()
  local exps = FingerprintHS()
  if exps then
    local currSet = BuildSetFromExps(exps)
    if not OB_Primed then
      OB_Primed = true
      OB_LastExpSet = currSet
      OB_LastCount  = getn(exps)
      return false
    end
    local foundNew = false
    local i
    for i = 1, getn(exps) do
      local v = exps[i]
      if not OB_LastExpSet[v] then foundNew = true; break end
    end
    OB_LastExpSet = currSet
    OB_LastCount  = getn(exps)
    return foundNew
  end
  -- count fallback only
  local c = CountHS_ByTooltip()
  if not OB_Primed then OB_Primed = true; OB_LastCount = c; return false end
  local isNew = (c > OB_LastCount)
  OB_LastCount = c
  return isNew
end

-- ===== Main pulse =====
function OathBreaker_Pulse()
  local n = getn(OB_Queue)
  if n == 0 then OB_Err("Queue empty. Use /obadd <weapon>.") return end

  -- 1) If we have a pending swap, keep trying until verified
  if OB_PendingName then
    if IsMainHandEquipped(OB_PendingName) then
      if not OB_Quiet then OB_Msg("Equipped: " .. OB_PendingName) end
      if not OB_ModePriority then AdvanceIdx() end
      OB_PendingName = nil
      return
    end
    local ok = TryEquipOnce(OB_PendingName)
    if ok then
      if not OB_Quiet then OB_Msg("Equipped: " .. OB_PendingName) end
      if not OB_ModePriority then AdvanceIdx() end
      OB_PendingName = nil
    end
    return
  end

  -- 2) Mode-specific behavior
  if OB_ModePriority then
    -- ensure indices sane
    if OB_AnchorIndex < 1 or OB_AnchorIndex > n then OB_AnchorIndex = 1 end
    if OB_ChaseIndex  < 1 or OB_ChaseIndex  > n then OB_ChaseIndex  = 2 end
    if OB_ChaseIndex == OB_AnchorIndex then AdvanceChase() end

    local anchorName = OB_Queue[OB_AnchorIndex]

    -- EARLY RETURN TO ANCHOR when its soft-CD expires (even if no new proc)
    if OB_Chasing and SecondsLeft(anchorName) == 0 then
      if not IsMainHandEquipped(anchorName) then OB_RequestPostSwingSwap(anchorName) end
      OB_Chasing   = false
      OB_AnchorExp = nil     -- stop tracking the old anchor instance
      OB_Primed    = false   -- re-prime for next new HS
      return
    end

    -- capture previous set BEFORE checking for new
    local prevSet = nil
    if FingerprintCapable() then
      prevSet = OB_LastExpSet -- from last pulse; good enough for diff
    end

    if OB_Chasing then
      -- If all non-anchor weapons are on cooldown, snap back to anchor
      if AllNonAnchorOnCooldown() then
        if not IsMainHandEquipped(anchorName) then OB_RequestPostSwingSwap(anchorName) end
        OB_Chasing   = false
        OB_AnchorExp = nil
        OB_Primed    = false
        return
      end
      -- while chasing, if anchor's specific instance fell, return to anchor
      if FingerprintCapable() and OB_AnchorExp then
        local currExps = FingerprintHS()
        local currSet  = BuildSetFromExps(currExps)
        if not currSet[OB_AnchorExp] then
          if not IsMainHandEquipped(anchorName) then OB_RequestPostSwingSwap(anchorName) end
          OB_Chasing   = false
          OB_AnchorExp = nil
          OB_Primed    = false
          return
        end
      else
        -- fallback: if total drops below baseline, assume anchor fell
        local curr = OB_CurrentHSCount()
        if curr < OB_BaseCount then
          if not IsMainHandEquipped(anchorName) then OB_RequestPostSwingSwap(anchorName) end
          OB_Chasing   = false
          OB_AnchorExp = nil
          OB_Primed    = false
          return
        end
      end

      -- handle chaining: if a new HS appeared, mark CD for current weapon,
      -- then move to the next chase target that is NOT on cooldown
      if IsNewHolyStrength() then
        local currW = GetEquippedMHName(); if currW then StartCooldown(currW) end
        OB_BaseCount = OB_CurrentHSCount()
        -- pick next non-CD candidate
        local idx, nm = NextChaseCandidate()
        if idx and nm then
          OB_ChaseIndex = idx
          if not IsMainHandEquipped(nm) then OB_RequestPostSwingSwap(nm) end
        else
          -- No eligible non-anchor (all on cooldown): favor anchor uptime
          if not IsMainHandEquipped(anchorName) then OB_RequestPostSwingSwap(anchorName) end
          OB_Chasing   = false
          OB_AnchorExp = nil
          OB_Primed    = false
        end
        return
      end
      return
    else
      -- not chasing: look for a *fresh* anchor proc
      if IsNewHolyStrength() then
        -- start cooldown for the weapon that just procced (should be anchor)
        local currW = GetEquippedMHName(); if currW then StartCooldown(currW) end
        -- fingerprint the *new* one to stick to the anchor instance
        if FingerprintCapable() then
          local currExps = FingerprintHS()
          local currSet  = BuildSetFromExps(currExps)
          -- Find exp value that wasn't in prevSet
          local newExp = nil
          local i
          for i = 1, (currExps and getn(currExps) or 0) do
            local v = currExps[i]
            if not (prevSet and prevSet[v]) then newExp = v; break end
          end
          if not newExp then
            -- fallback: pick max exp (youngest buff)
            local maxv = nil
            for i = 1, (currExps and getn(currExps) or 0) do
              local v = currExps[i]
              if not maxv or v > maxv then maxv = v end
            end
            newExp = maxv
          end
          OB_AnchorExp = newExp
          OB_LastExpSet = currSet
        end
        OB_BaseCount = OB_CurrentHSCount()
        OB_Chasing   = true
        -- initialize chase index then pick a non-CD candidate
        OB_ChaseIndex = OB_AnchorIndex + 1; if OB_ChaseIndex > n then OB_ChaseIndex = 1 end
        if OB_ChaseIndex == OB_AnchorIndex then AdvanceChase() end
        local idx, nm = NextChaseCandidate()
        if idx and nm then
          OB_ChaseIndex = idx
          if not IsMainHandEquipped(nm) then OB_RequestPostSwingSwap(nm) end
        end
        return
      end
      return
    end
  else
    -- Round-robin (legacy) — cooldowns intentionally ignored
    if IsNewHolyStrength() then
      local tries = 0
      while tries < n do
        local nextName = OB_Queue[OB_NextIndex]
        if not IsMainHandEquipped(nextName) then
          OB_RequestPostSwingSwap(nextName)
          return
        else
          AdvanceIdx()
          tries = tries + 1
        end
      end
    end
  end
end

-- ===== Queue management (globals for SlashCmdList) =====
function OB_Add_Slash(msg)
  local name = NormalizeItemInput(msg)
  if name == "" then OB_Err("Usage: /obadd <weapon or item link>") return end
  tinsert(OB_Queue, name)
  OB_Msg("Added " .. name .. " at position " .. getn(OB_Queue) .. ".")
  if getn(OB_Queue) == 1 then
    OB_NextIndex   = 1
    OB_AnchorIndex = 1
    OB_ChaseIndex  = 2
  end
end

function OB_Del_Slash(msg)
  local arg = NormalizeItemInput(msg)
  if arg == "" then OB_Err("Usage: /obdel <index|weapon or item link>") return end
  local idx = tonumber(arg)
  local n = getn(OB_Queue)
  if idx and idx >= 1 and idx <= n then
    local removed = table.remove(OB_Queue, idx)
    OB_Msg("Removed position " .. idx .. ": " .. removed)
  else
    local targetLower = strlower(arg)
    local i
    for i = 1, n do
      local nm = OB_Queue[i]
      if strlower(nm) == targetLower then
        table.remove(OB_Queue, i)
        OB_Msg("Removed: " .. nm)
        break
      end
    end
  end
  local nn = getn(OB_Queue)
  if nn == 0 then
    OB_NextIndex   = 1
    OB_AnchorIndex = 1
    OB_ChaseIndex  = 2
    OB_Chasing     = false
    OB_AnchorExp   = nil
    OB_Cooldowns   = {}
    return
  end
  if OB_AnchorIndex > nn then OB_AnchorIndex = 1 end
  if OB_ChaseIndex  > nn then OB_ChaseIndex  = 1 end
  if OB_NextIndex   > nn then OB_NextIndex   = 1 end
end

function OB_List_Slash()
  local n = getn(OB_Queue)
  if n == 0 then OB_Msg("Queue empty. Use /obadd <weapon>.") return end
  local mode = OB_ModePriority and "PRIORITY" or "ROUND"
  OB_Msg("Queue (mode=" .. mode .. ", anchor=#" .. OB_AnchorIndex .. "):")
  local i
  for i = 1, n do
    local marks = ""
    if i == OB_AnchorIndex then marks = marks .. "[A]" end
    if i == OB_NextIndex then marks = marks .. "[N]" end
    if i == OB_ChaseIndex and OB_Chasing then marks = marks .. "[C]" end
    local cdLeft = SecondsLeft(OB_Queue[i])
    local cdStr = (OB_ModePriority and cdLeft > 0) and (" [CD " .. string.format("%ds", floor(cdLeft + 0.5)) .. "]") or ""
    local f = Frame(); if f and f.AddMessage then f:AddMessage(string.format(" %2d. %s %s%s", i, OB_Queue[i], marks, cdStr), 0.9, 0.9, 0.9) end
  end
end

function OB_Clear_Slash()
  OB_Queue = {}
  OB_NextIndex   = 1
  OB_PendingName = nil
  OB_Chasing     = false
  OB_BaseCount   = 0
  OB_AnchorExp   = nil
  OB_Cooldowns   = {}
  OB_Msg("Queue cleared.")
end

function OB_Next_Slash()
  local n = getn(OB_Queue)
  if n == 0 then OB_Err("Queue empty. Use /obadd <weapon>.") return end
  local name
  if OB_ModePriority then
    if OB_Chasing then name = OB_Queue[OB_ChaseIndex] else name = OB_Queue[OB_AnchorIndex] end
  else
    name = OB_Queue[OB_NextIndex]
  end
  if not OB_PendingName then OB_RequestPostSwingSwap(name) end
  OathBreaker_Pulse()
end

function OB_Ping_Slash()  OB_Msg("ping") end

function OB_Debug_Slash()
  local f = Frame()
  if f and f.AddMessage then
    f:AddMessage(OB_PREFIX .. "DCF=" .. type(DEFAULT_CHAT_FRAME) .. ", CF1=" .. type(ChatFrame1) .. ", Q=" .. type(OB_Queue) .. ", Quiet=" .. tostring(OB_Quiet) .. ", ModePriority=" .. tostring(OB_ModePriority) .. ", CDWin=" .. tostring(OB_CD_WINDOW))
  end
end

local function OB_SetQuiet(on)
  OB_Quiet = (on and true) or false
  if OB_Quiet then OB_Msg("Quiet mode: on") else OB_Msg("Quiet mode: off") end
end

function OB_Quiet_Slash()  OB_SetQuiet(true)  end
function OB_Verbose_Slash() OB_SetQuiet(false) end

local function OB_SetModePriority(on)
  OB_ModePriority = (on and true) or false
  OB_Chasing     = false
  OB_PendingName = nil
  OB_Primed      = false
  OB_AnchorExp   = nil
  -- Keep OB_Cooldowns table, but it only matters in priority mode
  if OB_ModePriority then
    OB_Msg("Mode: PRIORITY (anchor-first). Anchor is queue #" .. OB_AnchorIndex)
  else
    OB_Msg("Mode: ROUND (classic round-robin)")
  end
end

function OB_Mode_Slash(msg)
  local a = Trim(msg or "")
  if a == "priority" then OB_SetModePriority(true); return end
  if a == "round" or a == "rr" then OB_SetModePriority(false); return end
  OB_Err("Usage: /obmode priority | round")
end

function OB_Priority_Slash(msg)
  local a = Trim(msg or "")
  if a == "on" or a == "1" then OB_SetModePriority(true); return end
  if a == "off" or a == "0" then OB_SetModePriority(false); return end
  OB_Err("Usage: /obpriority on|off")
end

function OB_Anchor_Slash(msg)
  local a = NormalizeItemInput(msg)
  local n = getn(OB_Queue)
  if n == 0 then OB_Err("Queue empty. Add weapons first."); return end
  local idx = tonumber(a)
  if idx then
    if idx < 1 or idx > n then OB_Err("Anchor index out of range (1-" .. n .. ")"); return end
    OB_AnchorIndex = idx
    OB_Msg("Anchor set to #" .. idx .. ": " .. OB_Queue[idx])
    return
  end
  local i
  local targetLower = strlower(a)
  for i = 1, n do
    if strlower(OB_Queue[i]) == targetLower then
      OB_AnchorIndex = i
      OB_Msg("Anchor set to #" .. i .. ": " .. OB_Queue[i])
      return
    end
  end
  OB_Err("Anchor not found: " .. a)
end

-- NEW: Set cooldown seconds (priority mode only)
function OB_CD_Slash(msg)
  local a = Trim(msg or "")
  local v = tonumber(a)
  if not v then OB_Err("Usage: /obcd <seconds>"); return end
  if v < 0 then v = 0 end
  if v > 60 then v = 60 end
  OB_CD_WINDOW = v
  OB_Msg("Per-weapon soft cooldown set to " .. v .. "s (priority mode only)")
end

-- NEW: List cooldowns
function OB_CDList_Slash()
  if getn(OB_Queue) == 0 then OB_Msg("Queue empty."); return end
  OB_Msg("Cooldowns (priority mode only):")
  local i
  for i = 1, getn(OB_Queue) do
    local nm = OB_Queue[i]
    local left = SecondsLeft(nm)
    local f = Frame(); if f and f.AddMessage then f:AddMessage(string.format(" %2d. %s  %s", i, nm, (left > 0 and (string.format("%0.1fs left", left)) or "ready")), 0.8, 0.8, 0.8) end
  end
end

-- ===== Slash registration =====
SLASH_OATHBREAKER1 = "/oathbreaker"
SlashCmdList["OATHBREAKER"] = OathBreaker_Pulse

SLASH_OBADD1 = "/obadd"
SlashCmdList["OBADD"] = OB_Add_Slash

SLASH_OBDEL1 = "/obdel"
SlashCmdList["OBDEL"] = OB_Del_Slash

SLASH_OBLIST1 = "/oblist"
SlashCmdList["OBLIST"] = OB_List_Slash

SLASH_OBCLEAR1 = "/obclear"
SlashCmdList["OBCLEAR"] = OB_Clear_Slash

SLASH_OBNEXT1 = "/obnext"
SlashCmdList["OBNEXT"] = OB_Next_Slash

SLASH_OBPING1 = "/obping"
SlashCmdList["OBPING"] = OB_Ping_Slash

SLASH_OBDEBUG1 = "/obdebug"
SlashCmdList["OBDEBUG"] = OB_Debug_Slash

SLASH_OBQUIET1 = "/obquiet"
SlashCmdList["OBQUIET"] = OB_Quiet_Slash

SLASH_OBVERBOSE1 = "/obverbose"
SlashCmdList["OBVERBOSE"] = OB_Verbose_Slash

SLASH_OBMODE1 = "/obmode"
SlashCmdList["OBMODE"] = OB_Mode_Slash

SLASH_OBPRIORITY1 = "/obpriority"
SlashCmdList["OBPRIORITY"] = OB_Priority_Slash

SLASH_OBANCHOR1 = "/obanchor"
SlashCmdList["OBANCHOR"] = OB_Anchor_Slash

SLASH_OBCD1 = "/obcd"
SlashCmdList["OBCD"] = OB_CD_Slash

SLASH_OBCDLIST1 = "/obcdlist"
SlashCmdList["OBCDLIST"] = OB_CDList_Slash

SLASH_OBSWINGGATE1 = "/obswinggate"
SlashCmdList["OBSWINGGATE"] = function(msg)
  local a = Trim(string.lower(msg or ""))
  if a == "on" or a == "1" then
    OB_SwingGate = true
    OB_Msg("Post-swing gating: ON")
  elseif a == "off" or a == "0" then
    OB_SwingGate = false
    OB_Msg("Post-swing gating: OFF")
  else
    OB_Msg("Usage: /obswinggate on|off")
  end
end

-- End of OathBreaker.lua v1.4 (swing-gated)



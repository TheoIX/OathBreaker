--[[
OathBreaker.lua - Turtle WoW 1.12 (Lua 5.0 safe) - v1.1.2
Author: Theodan

Plain-ASCII. ArcaneFlow-style slash registration. Balanced ends verified.

Behavior:
  • Each /oathbreaker press retries a pending swap until it verifies equipped.
  • Only prints when the weapon actually switches (quiet retries by default).
  • /obverbose to see retry output; /obquiet to silence again.

Slash:
  /oathbreaker  /obadd  /obdel  /oblist  /obclear  /obnext  /obping  /obdebug  /obquiet  /obverbose
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
OB_LastExpSet   = {}   -- set[exp]=true when fingerprinting

-- Equip pending state (press-to-press retries)
OB_PendingName  = nil

-- Chat verbosity
OB_Quiet        = true  -- default: only print on successful swaps

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

local function AdvanceIdx()
  OB_NextIndex = OB_NextIndex + 1
  if OB_NextIndex > getn(OB_Queue) then OB_NextIndex = 1 end
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

  -- 3) Bag-scan soft use
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
            -- 4) Hard swap via pickup/put
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

-- ===== Holy Strength detection =====
local function FingerprintHS()
  if not (type(GetPlayerBuff) == "function" and type(GetPlayerBuffTimeLeft) == "function" and type(GetPlayerBuffTexture) == "function") then
    return nil
  end
  local exps = {}
  local i = 0
  while true do
    local idx = GetPlayerBuff(i, "HELPFUL")
    if not idx or idx < 0 then break end
    local tex = GetPlayerBuffTexture(idx)
    if tex and strfind(strlower(tex), HOLY_ICON_SUB, 1, true) then
      local tl = GetPlayerBuffTimeLeft(idx) or 0
      local exp = floor(GetTime() + tl + 0.5)
      tinsert(exps, exp)
    end
    i = i + 1
  end
  if getn(exps) == 0 then return {} end
  return exps
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

local function IsNewHolyStrength()
  local exps = FingerprintHS()
  if exps then
    if not OB_Primed then
      OB_Primed = true
      OB_LastExpSet = {}
      local k
      for k = 1, getn(exps) do OB_LastExpSet[exps[k]] = true end
      OB_LastCount = getn(exps)
      return false
    end
    local foundNew = false
    local j
    for j = 1, getn(exps) do
      local v = exps[j]
      if not OB_LastExpSet[v] then foundNew = true; break end
    end
    OB_LastExpSet = {}
    for j = 1, getn(exps) do OB_LastExpSet[exps[j]] = true end
    OB_LastCount = getn(exps)
    return foundNew
  end
  -- count fallback
  local c = CountHS_ByTooltip()
  if not OB_Primed then OB_Primed = true; OB_LastCount = c; return false end
  local isNew = (c > OB_LastCount)
  OB_LastCount = c
  return isNew
end

-- ===== Main pulse =====
function OathBreaker_Pulse()
  -- 1) If we have a pending swap, keep trying until verified
  if OB_PendingName then
    if IsMainHandEquipped(OB_PendingName) then
      OB_Msg("Equipped: " .. OB_PendingName)
      OB_PendingName = nil
      AdvanceIdx()
      return
    end
    if not OB_Quiet then OB_Msg("Trying to equip: " .. OB_PendingName) end
    local ok = TryEquipOnce(OB_PendingName)
    if ok then
      OB_Msg("Equipped: " .. OB_PendingName)
      OB_PendingName = nil
      AdvanceIdx()
    else
      if not OB_Quiet then OB_Err("Equip failed (locked/casting). Press again: " .. OB_PendingName) end
    end
    return
  end

  -- 2) Otherwise, scan for a NEW Holy Strength proc
  if IsNewHolyStrength() then
    local n = getn(OB_Queue)
    if n == 0 then if not OB_Quiet then OB_Err("Queue empty. Use /obadd <weapon>.") end return end
    local tries = 0
    while tries < n do
      local nextName = OB_Queue[OB_NextIndex]
      if not IsMainHandEquipped(nextName) then
        OB_PendingName = nextName
        if not OB_Quiet then OB_Msg("New Holy Strength! Pending equip: " .. nextName .. " (press again if blocked)") end
        return
      else
        AdvanceIdx()
        tries = tries + 1
      end
    end
    if not OB_Quiet then OB_Msg("All queued weapons already equipped; nothing to swap.") end
  end
end

-- ===== Queue management (globals for SlashCmdList) =====
function OB_Add_Slash(msg)
  local name = NormalizeItemInput(msg)
  if name == "" then OB_Err("Usage: /obadd <weapon or item link>") return end
  tinsert(OB_Queue, name)
  OB_Msg("Added " .. name .. " at position " .. getn(OB_Queue) .. ".")
  if getn(OB_Queue) == 1 then OB_NextIndex = 1 end
end

function OB_Del_Slash(msg)
  local arg = NormalizeItemInput(msg)
  if arg == "" then OB_Err("Usage: /obdel <index|weapon or item link>") return end
  local idx = tonumber(arg)
  if idx and idx >= 1 and idx <= getn(OB_Queue) then
    local removed = table.remove(OB_Queue, idx)
    OB_Msg("Removed position " .. idx .. ": " .. removed)
    if OB_NextIndex > getn(OB_Queue) then OB_NextIndex = 1 end
    return
  end
  local targetLower = strlower(arg)
  local i
  for i = 1, getn(OB_Queue) do
    local nm = OB_Queue[i]
    if strlower(nm) == targetLower then
      table.remove(OB_Queue, i)
      OB_Msg("Removed: " .. nm)
      if OB_NextIndex > getn(OB_Queue) then OB_NextIndex = 1 end
      return
    end
  end
  OB_Err("Not found in queue: " .. arg)
end

function OB_List_Slash()
  if getn(OB_Queue) == 0 then OB_Msg("Queue empty. Use /obadd <weapon>.") return end
  OB_Msg("Queue (next -> #" .. OB_NextIndex .. "):")
  local i
  for i = 1, getn(OB_Queue) do
    local marker = (i == OB_NextIndex) and "-> " or "   "
    local f = Frame(); if f and f.AddMessage then f:AddMessage(marker .. i .. ". " .. OB_Queue[i], 0.9, 0.9, 0.9) end
  end
end

function OB_Clear_Slash()
  OB_Queue = {}
  OB_NextIndex = 1
  OB_PendingName = nil
  OB_Msg("Queue cleared.")
end

function OB_Next_Slash()
  if getn(OB_Queue) == 0 then OB_Err("Queue empty. Use /obadd <weapon>.") return end
  if not OB_PendingName then
    local name = OB_Queue[OB_NextIndex]
    if IsMainHandEquipped(name) then AdvanceIdx(); name = OB_Queue[OB_NextIndex] end
    OB_PendingName = name
  end
  OathBreaker_Pulse()
end

function OB_Ping_Slash()
  OB_Msg("ping")
end

function OB_Debug_Slash()
  local f = Frame()
  if f and f.AddMessage then
    f:AddMessage(OB_PREFIX .. "DCF=" .. type(DEFAULT_CHAT_FRAME) .. ", CF1=" .. type(ChatFrame1) .. ", Q=" .. type(OB_Queue) .. ", Quiet=" .. tostring(OB_Quiet))
  end
end

local function OB_SetQuiet(on)
  OB_Quiet = (on and true) or false
  if OB_Quiet then
    OB_Msg("Quiet mode: on (only prints on successful swaps)")
  else
    OB_Msg("Quiet mode: off (shows retries)")
  end
end

function OB_Quiet_Slash()
  OB_SetQuiet(true)
end

function OB_Verbose_Slash()
  OB_SetQuiet(false)
end

-- ===== Slash registration (ArcaneFlow style) =====
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


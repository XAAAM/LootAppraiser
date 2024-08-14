--- **AceBNComm-1.0** is a rework of AceComm-3.0 for BNComm

local MAJOR, MINOR = "AceBNComm-1.0", 2

local AceBNComm,oldminor = LibStub:NewLibrary(MAJOR, MINOR)

assert(AceBNComm, "Can't load AceBNComm")

if not AceBNComm then return end

local CallbackHandler = LibStub:GetLibrary("CallbackHandler-1.0")
local BNCTL = assert(BNChatThrottleLib, "AceBNComm-1.0 requires BNChatThrottleLib")
-- print("BNCTL: " .. tostring(BNCTL))

-- Lua APIs
local type, next, pairs, tostring = type, next, pairs, tostring
local strsub, strfind = string.sub, string.find
local match = string.match
local tinsert, tconcat = table.insert, table.concat
local error, assert = error, assert

-- WoW APIs
local Ambiguate = Ambiguate

-- Global vars/functions that we don't upvalue since they might get hooked, or upgraded
-- List them here for Mikk's FindGlobals script
-- GLOBALS: LibStub, DEFAULT_CHAT_FRAME, geterrorhandler, RegisterAddonMessagePrefix

AceBNComm.embeds = AceBNComm.embeds or {}

-- for my sanity and yours, let's give the message type bytes some names
local MSG_MULTI_FIRST = "\001"
local MSG_MULTI_NEXT  = "\002"
local MSG_MULTI_LAST  = "\003"
local MSG_ESCAPE = "\004"

-- remove old structures (pre WoW 4.0)
AceBNComm.multipart_origprefixes = nil
AceBNComm.multipart_reassemblers = nil

-- the multipart message spool: indexed by a combination of sender+distribution+
AceBNComm.multipart_spool = AceBNComm.multipart_spool or {} 

--- Register for Addon Traffic on a specified prefix
-- @param prefix A printable character (\032-\255) classification of the message (typically AddonName or AddonNameEvent), max 16 characters
-- @param method Callback to call on message reception: Function reference, or method name (string) to call on self. Defaults to "OnCommReceived"
function AceBNComm:RegisterComm(prefix, method)
	if method == nil then
		method = "OnCommReceived"
	end

	if #prefix > 16 then -- TODO: 15?
		error("AceBNComm:RegisterComm(prefix,method): prefix length is limited to 16 characters")
	end
	--RegisterAddonMessagePrefix(prefix)

	return AceBNComm._RegisterComm(self, prefix, method)	-- created by CallbackHandler
end

local warnedPrefix=false


--- Send a message over the Addon Channel
-- @param prefix A printable character (\032-\255) classification of the message (typically AddonName or AddonNameEvent)
-- @param text Data to send, nils (\000) not allowed. Any length.
-- @param target Destination for some distributions; see SendAddonMessage API
-- @param callbackFn OPTIONAL: callback function to be called as each chunk is sent. receives 3 args: the user supplied arg (see next), the number of bytes sent so far, and the number of bytes total to send.
-- @param callbackArg: OPTIONAL: first arg to the callback function. nil will be passed if not specified.
function AceBNComm:SendCommMessage(prefix, text, target, prio, callbackFn, callbackArg)
	--print("AceBNComm:SendCommMessage: prefix=" .. prefix .. ", target=" .. tostring(target) .. ", text=" .. tostring(text))
	prio = prio or "NORMAL"
	if not( type(prefix)=="string" and
			type(text)=="string" and
			type(target)=="number"
		) then
		error('Usage: SendCommMessage(addon, "prefix", "text"[, "target"[, callbackFn, callbackarg]])', 2)
	end

	local textlen = #text
	local maxtextlen = 4078  -- Yes, the max is 255 even if the dev post said 256. I tested. Char 256+ get silently truncated. /Mikk, 20110327
	local queueName = prefix .. (target or "")

	local ctlCallback = nil
	if callbackFn then
		ctlCallback = function(sent)
			return callbackFn(callbackArg, sent, textlen)
		end
	end
	
	local forceMultipart
	if match(text, "^[\001-\009]") then -- 4.1+: see if the first character is a control character
		-- we need to escape the first character with a \004
		if textlen+1 > maxtextlen then	-- would we go over the size limit?
			forceMultipart = true	-- just make it multipart, no escape problems then
		else
			text = "\004" .. text
		end
	end

	if not forceMultipart and textlen <= maxtextlen then
		-- fits all in one message
		BNCTL:BNSendGameData(prio, target, prefix, text, queueName, ctlCallback, textlen)
	else
		maxtextlen = maxtextlen - 1	-- 1 extra byte for part indicator in prefix(4.0)/start of message(4.1)

		-- first part
		local chunk = strsub(text, 1, maxtextlen)
		BNCTL:BNSendGameData(prio, target, prefix, MSG_MULTI_FIRST..chunk, queueName, ctlCallback, textlen)

		-- continuation
		local pos = 1+maxtextlen

		while pos+maxtextlen <= textlen do
			chunk = strsub(text, pos, pos+maxtextlen-1)
			BNCTL:BNSendGameData(prio, target, prefix, MSG_MULTI_NEXT..chunk, queueName, ctlCallback, textlen)
			pos = pos + maxtextlen
		end

		-- final part
		chunk = strsub(text, pos)
		BNCTL:BNSendGameData(prio, target, prefix, MSG_MULTI_LAST..chunk, queueName, ctlCallback, textlen)
	end
end


----------------------------------------
-- Message receiving
----------------------------------------

do
	local compost = setmetatable({}, {__mode = "k"})
	local function new()
		local t = next(compost)
		if t then 
			compost[t]=nil
			for i=#t,3,-1 do	-- faster than pairs loop. don't even nil out 1/2 since they'll be overwritten
				t[i]=nil
			end
			return t
		end
		
		return {}
	end
	
	local function lostdatawarning(prefix,sender,where)
		DEFAULT_CHAT_FRAME:AddMessage(MAJOR..": Warning: lost network data regarding '"..tostring(prefix).."' from '"..tostring(sender).."' (in "..where..")")
	end

	function AceBNComm:OnReceiveMultipartFirst(prefix, message, distribution, sender)
		local key = prefix.."\t"..distribution.."\t"..sender	-- a unique stream is defined by the prefix + distribution + sender
		local spool = AceBNComm.multipart_spool
		
		--[[
		if spool[key] then 
			lostdatawarning(prefix,sender,"First")
			-- continue and overwrite
		end
		--]]
		
		spool[key] = message  -- plain string for now
	end

	function AceBNComm:OnReceiveMultipartNext(prefix, message, distribution, sender)
		local key = prefix.."\t"..distribution.."\t"..sender	-- a unique stream is defined by the prefix + distribution + sender
		local spool = AceBNComm.multipart_spool
		local olddata = spool[key]
		
		if not olddata then
			--lostdatawarning(prefix,sender,"Next")
			return
		end

		if type(olddata)~="table" then
			-- ... but what we have is not a table. So make it one. (Pull a composted one if available)
			local t = new()
			t[1] = olddata    -- add old data as first string
			t[2] = message    -- and new message as second string
			spool[key] = t    -- and put the table in the spool instead of the old string
		else
			tinsert(olddata, message)
		end
	end

	function AceBNComm:OnReceiveMultipartLast(prefix, message, distribution, sender)
		local key = prefix.."\t"..distribution.."\t"..sender	-- a unique stream is defined by the prefix + distribution + sender
		local spool = AceBNComm.multipart_spool
		local olddata = spool[key]
		
		if not olddata then
			--lostdatawarning(prefix,sender,"End")
			return
		end

		spool[key] = nil
		
		if type(olddata) == "table" then
			-- if we've received a "next", the spooled data will be a table for rapid & garbage-free tconcat
			tinsert(olddata, message)
			AceBNComm.callbacks:Fire(prefix, tconcat(olddata, ""), distribution, sender)
			compost[olddata] = true
		else
			-- if we've only received a "first", the spooled data will still only be a string
			AceBNComm.callbacks:Fire(prefix, olddata..message, distribution, sender)
		end
	end
end






----------------------------------------
-- Embed CallbackHandler
----------------------------------------

if not AceBNComm.callbacks then
	AceBNComm.callbacks = CallbackHandler:New(AceBNComm,
						"_RegisterComm",
						"UnregisterComm",
						"UnregisterAllComm")
end

AceBNComm.callbacks.OnUsed = nil
AceBNComm.callbacks.OnUnused = nil

local function OnEvent(self, event, prefix, message, distribution, sender)
	if event == "BN_CHAT_MSG_ADDON" then
		sender = Ambiguate(sender, "none")
		local control, rest = match(message, "^([\001-\009])(.*)")
		if control then
			if control==MSG_MULTI_FIRST then
				AceBNComm:OnReceiveMultipartFirst(prefix, rest, distribution, sender)
			elseif control==MSG_MULTI_NEXT then
				AceBNComm:OnReceiveMultipartNext(prefix, rest, distribution, sender)
			elseif control==MSG_MULTI_LAST then
				AceBNComm:OnReceiveMultipartLast(prefix, rest, distribution, sender)
			elseif control==MSG_ESCAPE then
				AceBNComm.callbacks:Fire(prefix, rest, distribution, sender)
			else
				-- unknown control character, ignore SILENTLY (dont warn unnecessarily about future extensions!)
			end
		else
			-- single part: fire it off immediately and let CallbackHandler decide if it's registered or not
			AceBNComm.callbacks:Fire(prefix, message, distribution, sender)
		end
	else
		assert(false, "Received "..tostring(event).." event?!")
	end
end

AceBNComm.frame = AceBNComm.frame or CreateFrame("Frame", "AceBNComm30Frame")
AceBNComm.frame:SetScript("OnEvent", OnEvent)
AceBNComm.frame:UnregisterAllEvents()
AceBNComm.frame:RegisterEvent("BN_CHAT_MSG_ADDON")


----------------------------------------
-- Base library stuff
----------------------------------------

local mixins = {
	"RegisterComm",
	"UnregisterComm",
	"UnregisterAllComm",
	"SendCommMessage",
}

-- Embeds AceBNComm-3.0 into the target object making the functions from the mixins list available on target:..
-- @param target target object to embed AceBNComm-3.0 in
function AceBNComm:Embed(target)
	for k, v in pairs(mixins) do
		target[v] = self[v]
	end
	self.embeds[target] = true
	return target
end

function AceBNComm:OnEmbedDisable(target)
	target:UnregisterAllComm()
end

-- Update embeds
for target, v in pairs(AceBNComm.embeds) do
	AceBNComm:Embed(target)
end

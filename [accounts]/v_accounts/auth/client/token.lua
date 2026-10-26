-- auth client: the remember-me token and the client API used by the ui module /
-- v_mainmenu. The token is "<account name>=<hash>" from the server
-- (v_accounts:rememberToken), kept in this resource's private userdata.xml; the
-- password itself is never stored.

local FILE = "auth/userdata.xml"
local token = ""

local function load()
    local xml = xmlLoadFile(FILE)
    if not xml then return end
    local node = xmlFindChild(xml, "token", 0)
    token = (node and xmlNodeGetValue(node)) or ""
    xmlUnloadFile(xml)
end

local function saveToken(value)
    token = tostring(value or "")
    local xml = xmlLoadFile(FILE) or xmlCreateFile(FILE, "userdata")
    if not xml then return end
    local node = xmlFindChild(xml, "token", 0) or xmlCreateChild(xml, "token")
    xmlNodeSetValue(node, token)
    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

load()

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

-- Account name of the saved remember-me token, or false.
function getSavedAccountName()
    return token:match("^([^=]+)=%x+$") or false
end

function forgetSavedLogin()
    saveToken("")
end

-- remember = false also forgets a saved token right away
function login(username, password, remember)
    if remember ~= true then saveToken("") end
    triggerServerEvent("v_accounts:login", localPlayer, tostring(username or ""), tostring(password or ""), remember == true)
end

function loginWithToken()
    if token == "" then
        triggerEvent("v_accounts:onClientTokenInvalid", localPlayer)
        return false
    end
    triggerServerEvent("v_accounts:loginToken", localPlayer, token)
    return true
end

function register(username, password, email)
    triggerServerEvent("v_accounts:register", localPlayer, tostring(username or ""), tostring(password or ""), tostring(email or ""))
end

function requestPasswordReset(email)
    triggerServerEvent("v_accounts:resetRequest", localPlayer, tostring(email or ""))
end

-- step 2 with a code the player already has (mailed by an admin)
function usePasswordResetCode(email)
    triggerServerEvent("v_accounts:resetHaveCode", localPlayer, tostring(email or ""))
end

function confirmPasswordReset(code, newPassword)
    triggerServerEvent("v_accounts:resetConfirm", localPlayer, tostring(code or ""), tostring(newPassword or ""))
end

function requestEmail()
    triggerServerEvent("v_accounts:requestEmail", localPlayer)
end

-- email = "" removes it; currentPassword is needed when the account already has one
function setEmail(email, currentPassword)
    triggerServerEvent("v_accounts:setEmail", localPlayer, tostring(email or ""), tostring(currentPassword or ""))
end

--------------------------------------------------------------------------------
-- server -> client
--------------------------------------------------------------------------------

addEvent("v_accounts:onClientAuthError", true)
addEvent("v_accounts:onClientLoggedIn", true)
addEvent("v_accounts:onClientResetState", true)
addEvent("v_accounts:onClientEmail", true)

-- The server verified a remembered password login: keep only the token.
addEvent("v_accounts:rememberToken", true)
addEventHandler("v_accounts:rememberToken", localPlayer, function(value)
    if type(value) == "string" then saveToken(value) end
end)

-- The saved token was refused (password changed, other machine, ...): forget it.
addEvent("v_accounts:onClientTokenInvalid", true)
addEventHandler("v_accounts:onClientTokenInvalid", localPlayer, function()
    saveToken("")
end)

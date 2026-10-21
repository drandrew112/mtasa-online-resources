-- acc_auth client: the remember-me token and the client API used by acc_ui /
-- acc_menu. The token is "<account name>=<hash>" from the server
-- (acc_auth:rememberToken), kept in this resource's private userdata.xml; the
-- password itself is never stored.

local FILE = "userdata.xml"
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
    triggerServerEvent("acc_auth:login", localPlayer, tostring(username or ""), tostring(password or ""), remember == true)
end

function loginWithToken()
    if token == "" then
        triggerEvent("acc_auth:onClientTokenInvalid", localPlayer)
        return false
    end
    triggerServerEvent("acc_auth:loginToken", localPlayer, token)
    return true
end

function register(username, password, email)
    triggerServerEvent("acc_auth:register", localPlayer, tostring(username or ""), tostring(password or ""), tostring(email or ""))
end

function requestPasswordReset(email)
    triggerServerEvent("acc_auth:resetRequest", localPlayer, tostring(email or ""))
end

function confirmPasswordReset(code, newPassword)
    triggerServerEvent("acc_auth:resetConfirm", localPlayer, tostring(code or ""), tostring(newPassword or ""))
end

function requestEmail()
    triggerServerEvent("acc_auth:requestEmail", localPlayer)
end

-- email = "" removes it; currentPassword is needed when the account already has one
function setEmail(email, currentPassword)
    triggerServerEvent("acc_auth:setEmail", localPlayer, tostring(email or ""), tostring(currentPassword or ""))
end

--------------------------------------------------------------------------------
-- server -> client
--------------------------------------------------------------------------------

addEvent("acc_auth:onClientAuthError", true)
addEvent("acc_auth:onClientLoggedIn", true)
addEvent("acc_auth:onClientResetState", true)
addEvent("acc_auth:onClientEmail", true)

-- The server verified a remembered password login: keep only the token.
addEvent("acc_auth:rememberToken", true)
addEventHandler("acc_auth:rememberToken", localPlayer, function(value)
    if type(value) == "string" then saveToken(value) end
end)

-- The saved token was refused (password changed, other machine, ...): forget it.
addEvent("acc_auth:onClientTokenInvalid", true)
addEventHandler("acc_auth:onClientTokenInvalid", localPlayer, function()
    saveToken("")
end)

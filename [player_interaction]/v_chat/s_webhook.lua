local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1557197845847736322/kdEdqL3XbB6qNjLiDUAWLSVfyVpO9M9fFZB9m2ZPvC7KfwU8pytlGAeQszjXsSUu3rDH"

addEvent("chat:discord:sendWebhook", true)
addEventHandler("chat:discord:sendWebhook", root, function(message)
    if type(message) ~= "string" or message == "" then
        return
    end

    local data = toJSON({
        content = message
    }, true)

    -- MTA a table-t tömbként serializálhatja:
    -- [{"content":"..."}]
    -- Discord viszont ezt várja:
    -- {"content":"..."}
    data = string.sub(data, 2, -2)

    fetchRemote(DISCORD_WEBHOOK, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json"
        },
        postData = data
    }, function(responseData, responseInfo)
        if not responseInfo.success then
            outputDebugString(
                "[Discord Webhook] Error: " ..
                tostring(responseInfo.statusCode) ..
                " | Response: " ..
                tostring(responseData),
                1
            )
            return
        end

        outputDebugString(
            "[Discord Webhook] Sent successfully.",
            3
        )
    end)
end)
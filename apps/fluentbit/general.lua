function transform(tag, timestamp, record)
    if record["version"] ~= nil then -- Processed successfully in krakend.access.lua
        return 0, timestamp, record
    end

    if json_formatted(record["message"]) then
        if string.find(record["message"], "timestamp") then
            return 0, timestamp, record
        elseif string.gsub(record["message"], " ", "") == "{}" then
            return 1, nil, {
                ["timestamp"] = record["timestamp"]
            }
        else
            return 1, nil, {
                ["message"] = string.gsub(record["message"], "{", '{"timestamp":"' .. record["timestamp"] .. '",', 1)
            }
        end
    end

    return 1, nil, {
        ["version"] = "1.0",
        ["timestamp"] = record["timestamp"],
        ["level"] = "INFO",
        ["metadata"] = {
            ["type"] = "general",
        },
        ["message"] = {
            ["str"] = record["message"]
        }
    }
end

function json_formatted(message)
    return message ~= nil
        and string.sub(message, 1, 1) == "{"
        and string.sub(message, -1) == "}"
end

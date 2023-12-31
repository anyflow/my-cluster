function transform(tag, timestamp, record)
    if record["statusCode"] == nil then -- Leave if the record is not access log.
        return 0, timestamp, record
    end

    timestamp = record["timestamp"]

    local responseTimeMs = tonumber(record["duration"])
    if record["durationUnit"] ~= nil and record["duration"] ~= nil then
        if record["durationUnit"] == "s" then
            responseTimeMs = responseTimeMs * 1000
        elseif record["durationUnit"] == "µs" then
            responseTimeMs = responseTimeMs / 1000
        end
    end

    return 1, nil, {
        ["version"] = "1.0",
        ["timestamp"] = timestamp,
        ["level"] = "INFO",
        ["metadata"] = {
            ["type"] = "httpResponse",
            ["operationId"] = record["path"] .. "|" .. record["method"],
            ["clientIp"] = record["clientIp"]
        },
        ["message"] = {
            ["statusCode"] = record["statusCode"],
            ["responseTimeMs"] = responseTimeMs,
            ["path"] = record["path"],
            ["method"] = record["method"]
        }
    }
end

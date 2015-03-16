local JSON     = require('json')
local timer    = require('timer')
local http     = require('http')
local https    = require('https')
local boundary = require('boundary')
local io       = require('io')
local _url     = require('_url')
require('_strings')


local __pgk        = "BOUNDARY NGINX"
local _previous    = {}
local url          = "http://127.0.0.1/nginx_status"
local pollInterval = 1000
local strictSSL    = true
local source, username, password


if (boundary.param ~= nil) then
  pollInterval       = boundary.param.pollInterval or pollInterval
  url                = boundary.param.url or url
  username           = boundary.param.username
  password           = boundary.param.password
  strictSSL          = boundary.param.strictSSL == true
  source             = (type(boundary.param.source) == 'string' and boundary.param.source:gsub('%s+', '') ~= '' and boundary.param.source) or
   io.popen("uname -n"):read('*line')
end


function berror(err)
  if err then print(string.format("%s ERROR: %s", __pgk, tostring(err))) return err end
end

--- do a http(s) request
local doreq = function(url, cb)
    local u = _url.parse(url)
    u.protocol = u.scheme
    -- reject self signed certs
    u.rejectUnauthorized = strictSSL
    if username and password then
      u.headers = {Authorization = "Basic " .. (string.base64(username..":"..password))}
    end
    local output = ""
    local onSuccess = function(res)
      res:on("error", function(err)
        cb("Error while receiving a response: " .. tostring(err), nil)
      end)
      res:on("data", function (chunk)
        output = output .. chunk
      end)
      res:on("end", function()
        if res.statusCode == 401 then return cb("Authentication required, provide user and password", nil) end
        res:destroy()
        cb(nil, output)
      end)
    end
    local req = (u.scheme == "https") and https.request(u, onSuccess) or http.request(u, onSuccess)
    req:on("error", function(err)
      cb("Error while sending a request: " .. tostring(err), nil)
    end)
    req:done()
end


function split(str, delim)
   local res = {}
   local pattern = string.format("([^%s]+)%s()", delim, delim)
   while (true) do
      line, pos = str:match(pattern, pos)
      if line == nil then break end
      table.insert(res, line)
   end
   return res
end


function parse(str)
  return tonumber(str)
end

function diff(a, b)
    if a == nil or b == nil then return 0 end
    return math.max(a - b, 0)
end

function parseStatsText(body)
    --[[
    See http://nginx.org/en/docs/http/ngx_http_stub_status_module.html for body format.
    Sample response:
    Active connections: 1
    server accepts handled requests
     112 112 121
    Reading: 0 Writing: 1 Waiting: 0
    --]]
    local stats = {}
    for i, v in ipairs(split(body, "\n")) do
      if v:find("Active connections:", 1, true) then
        local active, connections = v:gmatch('(%w+):%s*(%d+)')()
        stats[active:lower()] = parse(connections)

      elseif v:match("%s*(%d+)%s+(%d+)%s+(%d+)%s*$") then
        accepts, handled, requests = v:gmatch("%s*(%d+)%s+(%d+)%s+(%d+)%s*$")()
        stats.accepts    = parse(accepts)
        stats.handled    = parse(handled)
        stats.requests   = parse(requests)
        stats.nothandled = stats.accepts - stats.handled

      elseif v:match("(%w+):%s*(%d+)") then
        while true do
          k, va = v:gmatch("(%w+):%s*(%d+)")()
          if not k then break end
          stats[k:lower()] = parse(va)
          v = v:gsub(k, "")
        end
      end
    end
    return stats
end

-- accumulate a value and return the difference from the previous value
function accumulate(key, newValue)
    local oldValue = _previous[key] or newValue
    local difference = diff(newValue, oldValue)
    _previous[key] = newValue
    return difference
end

-- get the natural difference between a and b
function diff(a, b)
  if not a or not b then return 0 end
  return math.max(a - b, 0)
end


function parseStatsJson(body)
    j = nil
    pcall(function () j = json.parse(body) end)
    return j
end


function printEnterpriseStats(stats)
    local handled               = stats['connections']['accepted'] - stats['connections']['dropped']
    local requests              = stats['requests']['total']
    local requestsPerConnection = (requests > 0 and handled) and requests / handled or 0

    print(string.format('NGINX_ACTIVE_CONNECTIONS %d %s', stats['connections']['active'] + stats['connections']['idle'], source))
    print(string.format('NGINX_WAITING %d %s', stats['connections']['idle'], source))
    print(string.format('NGINX_HANDLED %d %s', accumulate('NGINX_HANDLED', handled), source))
    print(string.format('NGINX_NOT_HANDLED %d %s', stats['connections']['dropped'], source))
    print(string.format('NGINX_REQUESTS %d %s', accumulate('NGINX_REQUESTS', requests), source))
    print(string.format('NGINX_REQUESTS_PER_CONNECTION %d %s', requestsPerConnection, source))

    -- enterprise customers have 'per zone' statistics
    for i, zone_name in ipairs(stats.server_zones) do
        local zone = stats.server_zones[zone_name]
        local src = source .. zone_name
        print(string.format('NGINX_REQUESTS %d %s', accumulate('NGINX_REQUESTS_' .. zone_name, zone['requests']), src))
        print(string.format('NGINX_RESPONSES %d %s', accumulate('NGINX_RESPONSES_' .. zone_name, zone['responses']['total']), src))
        print(string.format('NGINX_TRAFFIC_SENT %d %s', accumulate('NGINX_TRAFFIC_SENT_' .. zone_name, zone['sent']), src))
        print(string.format('NGINX_TRAFFIC_RECEIVED %d %s', accumulate('NGINX_TRAFFIC_RECEIVED_' .. zone_name, zone['received']), src))
    end

end

function printStats(stats)
    local handled               = _previous['handled'] and diff(stats.handled, _previous.handled) or 0
    local requests              = _previous['requests'] and diff(stats.requests, _previous.requests) or 0
    local requestsPerConnection = (requests > 0 and handled) and requests / handled or 0

    _previous = stats

    print(string.format('NGINX_ACTIVE_CONNECTIONS %d %s', stats.connections, source))
    print(string.format('NGINX_READING %d %s', stats.reading, source))
    print(string.format('NGINX_WRITING %d %s', stats.writing, source))
    print(string.format('NGINX_WAITING %d %s', stats.waiting, source))
    print(string.format('NGINX_HANDLED %d %s', handled, source))
    print(string.format('NGINX_NOT_HANDLED %d %s', stats.nothandled, source))
    print(string.format('NGINX_REQUESTS %d %s', requests, source))
    print(string.format('NGINX_REQUESTS_PER_CONNECTION %d %s', requestsPerConnection, source))

end



print("_bevent:NGINX plugin up : version 1.0|t:info|tags:nginx,lua, plugin")

timer.setInterval(pollInterval, function ()

  doreq(url, function(err, body)
      if berror(err) then return end
      local stats = parseStatsJson(body)
      if stats then printEnterpriseStats(stats)
      else
        stats = parseStatsText(body)
        printStats(stats)
      end

  end)

end)

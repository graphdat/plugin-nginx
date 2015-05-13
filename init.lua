local framework = require('framework')
local json = require('json')
local url = require('url')
local table = require('table')
local Plugin  = framework.Plugin
local WebRequestDataSource = framework.WebRequestDataSource
local Accumulator = framework.Accumulator
local auth = framework.util.auth
local gsplit = framework.string.gsplit
local pack = framework.util.pack

local params = framework.params
params.name = 'Boundary NGINX Plugin'
params.version = '2.0' 

local options = url.parse(params.url)
options.auth = auth(params.username, params.password) 
options.wait_for_end = true
local ds = WebRequestDataSource:new(options)
local acc = Accumulator:new()
local plugin = Plugin:new(params, ds)

local function parseText(body)
    --[[
    See http://nginx.org/en/docs/http/ngx_http_stub_status_module.html for body format.
    Sample response:
    Active connections: 1
    server accepts handled requests
     112 112 121
    Reading: 0 Writing: 1 Waiting: 0
    --]]
    local stats = {}
    for v in gsplit(body, "\n") do
      if v:find("Active connections:", 1, true) then
        local metric, connections = v:match('(%w+):%s*(%d+)')
        stats[metric:lower()] = tonumber(connections)

      elseif v:match("%s*(%d+)%s+(%d+)%s+(%d+)%s*$") then
        local accepts, handled, requests = v:match("%s*(%d+)%s+(%d+)%s+(%d+)%s*$")
        stats.accepts    = tonumber(accepts)
        stats.handled    = tonumber(handled)
        stats.requests   = tonumber(requests)
        stats.not_handled = stats.accepts - stats.handled

      elseif v:match("(%w+):%s*(%d+)") then
        for metric, value in v:gmatch("(%w+):%s*(%d+)") do
          stats[metric:lower()] = tonumber(value)
        end
      end
    end
    return stats
end

local function parseJson(body)
    local parsed
    pcall(function () parsed = json.parse(body) end)
    return parsed 
end

function plugin:onParseValues(data)
  local metrics = {}

  local stats = parseJson(data)
  if stats then
    local handled = stats['connections']['accepted'] - stats['connections']['dropped']
    local requests = stats['requests']['total']
    local reqs_per_connection = (handled > 0) and requests / handled or 0

    metrics['NGINX_ACTIVE_CONNECTIONS'] = stats['connections']['active'] + stats['connections']['idle']
    metrics['NGINX_WAITING'] = stats['connections']['idle']
    metrics['NGINX_HANDLED'] = acc:accumulate('handled', handled)
    metrics['NGINX_NOT_HANDLED'] = stats['connections']['dropped']
    metrics['NGINX_REQUESTS'] = acc:accumulate('requests', requests)
    metrics['NGINX_REQUESTS_PER_CONNECTION'] = reqs_per_connection

    -- Enterprise customers have 'per zone' statistics
    for i, zone_name in ipairs(stats.server_zones) do
        local zone = stats.server_zones[zone_name]
        local src = self.source '.' .. zone_name
        table.insert(metrics, pack('NGINX_REQUESTS', acc:accumulate('requests_' .. zone_name, zone['requests']), nil, src))
        table.insert(metrics, pack('NGINX_RESPONSES', acc:accumulate('responses_' .. zone_name, zone['responses']['total']), nil, src))
        table.insert(metrics, pack('NGINX_TRAFFIC_SENT', acc:accumulate('traffic_sent_' .. zone_name, zone['sent']), nil, src))
        table.insert(metrics, pack('NGINX_TRAFFIC_RECEIVED', acc:accumulate('traffic_received_' .. zone_name, zone['received']), nil, src))
    end
  else 
    stats = parseText(data)
    local handled = acc:accumulate('handled', stats.handled)
    local requests = acc:accumulate('requests', stats.requests)
    local reqs_per_connection = (handled > 0) and requests / handled or 0

    metrics['NGINX_ACTIVE_CONNECTIONS'] = stats.connections
    metrics['NGINX_READING'] = stats.reading
    metrics['NGINX_WRITING'] = stats.writing
    metrics['NGINX_WAITING'] = stats.waiting
    metrics['NGINX_HANDLED'] = handled
    metrics['NGINX_NOT_HANDLED'] = stats.not_handled
    metrics['NGINX_REQUESTS'] = requests
    metrics['NGINX_REQUESTS_PER_CONNECTION'] = reqs_per_connection
  end

  return metrics 
end

plugin:run()

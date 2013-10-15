var _param = require('./param.json');
var _os = require('os');
var _http = require('http');
var _https = require('https');
var _request = require('request');

// how often do we call nginx to get the data
var _pollInterval = _param.pollInterval || 1000;

// remember the previous poll so we can provide proper counts
var _previousHandled = 0;
var _previousRequests = 0;

// nginx's http options
var _url = _param.url || 'http://127.0.0.1/nginx_status';

var _httpOptions;
if (_param.username)
    _httpOptions = { user: _param.username, pass: _param.password, sendImmediately: true };

// call nginx and parse the stats
function getStats(cb)
{
    // call nginx to get the stats page
    _request.get(_url, _httpOptions, function(err, resp, body)
    {
        if (err)
            return cb(err);
        if (resp.statusCode !== 200)
            return cb(new Error('Nginx returned with an error'));
        if (!body)
            return cb(new Error('Nginx statistics return empty'));

        // parse the output to get each result
        var stats = {};
        body.split('\n').forEach(function(line)
        {
            if (line.indexOf('Active connections:') === 0)
            {
                var active = line.match(/(\w+):\s*(\d+)/);
                stats[active[1].toLowerCase()] = active[2];
            }
            else if (line.match(/\s*(\d+)\s+(\d+)\s+(\d+)\s*$/))
            {
                var match = line.match(/\s*(\d+)\s+(\d+)\s+(\d+)\s*$/);
                stats.accepts = match[1];
                stats.handled = match[2];
                stats.requests = match[3];
                stats.nothandled = stats.accepts - stats.handled;
            }
            else if (line.match(/(\w+):\s*(\d+)/))
            {
                while(true)
                {
                    var kvp = line.match(/(\w+):\s*(\d+)/);
                    if (!kvp)
                        break;

                    stats[kvp[1].toLowerCase()] = kvp[2];
                    line = line.replace(kvp[0], '');
                }
            }
        });

        return cb(null, stats);
    });
}

// get the stats, format the output and send to stdout
function poll(cb)
{
    getStats(function(err, stats)
    {
        if (err)
            return console.error(err);

        var currentHandled = stats.handled;
        var currentRequests = stats.requests;

        var connections = Math.max(currentHandled - _previousHandled, 0);
        var requests = Math.max(currentRequests - _previousRequests, 0);
        var requestsPerConnection = requests/connections;

        _previousHandled = currentHandled;
        _previousRequests = currentRequests;

        // Report
        console.log('NGINX_ACTIVE_CONNECTIONS %d %s', stats.connections, _param.source);
        console.log('NGINX_READING %d %s', stats.reading, _param.source);
        console.log('NGINX_WRITING %d %s', stats.writing, _param.source);
        console.log('NGINX_WAITING %d %s', stats.waiting, _param.source);
        console.log('NGINX_HANDLED %d %s', stats.handled, _param.source);
        console.log('NGINX_NOT_HANDLED %d %s', stats.nothandled, _param.source);
        console.log('NGINX_REQUESTS %d %s', requests, _param.source);
        console.log('NGINX_REQUESTS_PER_CONNECTION %d %s', requestsPerConnection, _param.source);
    });

    setTimeout(poll, _pollInterval);
}

poll();

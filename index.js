var _param = require('./param.json');
var _os = require('os');
var _http = require('http');
var _https = require('https');
var _request = require('request');

var DEFAULT_POLL_INTERVAL = 1000;
var DEFAULT_SOURCE = _os.hostname();
var DEFAULT_URL = 'http://127.0.0.1/nginx_status';

// how often do we call nginx to get the data
var _pollInterval = _param.pollInterval || DEFAULT_POLL_INTERVAL;

// what is the hostname of the nginx server
var _source = _param.source || DEFAULT_SOURCE;

// remember the previous poll so we can provide proper counts
var _previous = {};

// nginx's http options
var _url = _param.url || DEFAULT_URL;

// if we have a name and password, then add an auth header
var _httpOptions;
if (_param.username)
    _httpOptions = { user: _param.username, pass: _param.password, sendImmediately: true };

// get the natural difference between a and b
function diff(a, b)
{
    return Math.max(a - b, 0);
}

// validate the input, return 0 if its not an integer
function parse(x)
{
    var y = parseInt(x, 10);
    return (isNaN(y) ? 0 : y);
}

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
                stats[active[1].toLowerCase()] = parse(active[2]);
            }
            else if (line.match(/\s*(\d+)\s+(\d+)\s+(\d+)\s*$/))
            {
                var match = line.match(/\s*(\d+)\s+(\d+)\s+(\d+)\s*$/);
                stats.accepts = parse(match[1]);
                stats.handled = parse(match[2]);
                stats.requests = parse(match[3]);
                stats.nothandled = stats.accepts - stats.handled;
            }
            else if (line.match(/(\w+):\s*(\d+)/))
            {
                while(true)
                {
                    var kvp = line.match(/(\w+):\s*(\d+)/);
                    if (!kvp)
                        break;

                    stats[kvp[1].toLowerCase()] = parse(kvp[2]);
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
    getStats(function(err, current)
    {
        if (err)
            return console.error(err);

        var handled = diff(current.handled, _previous.handled || 0);
        var requests = diff(current.requests, _previous.requests || 0);
        var requestsPerConnection = (requests > 0 && handled !== 0) ? requests/handled : 0;

        _previous = current;

        // Report
        console.log('NGINX_ACTIVE_CONNECTIONS %d %s', current.connections, _source);
        console.log('NGINX_READING %d %s', current.reading, _source);
        console.log('NGINX_WRITING %d %s', current.writing, _source);
        console.log('NGINX_WAITING %d %s', current.waiting, _source);
        console.log('NGINX_HANDLED %d %s', handled, _source);
        console.log('NGINX_NOT_HANDLED %d %s', current.nothandled, _source);
        console.log('NGINX_REQUESTS %d %s', requests, _source);
        console.log('NGINX_REQUESTS_PER_CONNECTION %d %s', requestsPerConnection, _source);
    });

    setTimeout(poll, _pollInterval);
}

poll();

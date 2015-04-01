# Boundary Nginx Plugin

A Boundary plugin that collects metrics from an Nginx F/OSS instance. This plugin is not intended for the Nginx Plus edition as other metrics are relevant and available there.

## Prerequisites

### Supported OS

|     OS    | Linux | Windows | SmartOS | OS X |
|:----------|:-----:|:-------:|:-------:|:----:|
| Supported |   v   |    v    |    v    |  v   |

#### Boundary Meter Versions V4.0 Or Greater REQUIRED

To get the new meter:

    curl -fsS \
        -d "{\"token\":\"<your API token here>\"}" \
        -H "Content-Type: application/json" \
        "https://meter.boundary.com/setup_meter" > setup_meter.sh
    chmod +x setup_meter.sh
    ./setup_meter.sh


#### For Boundary Meter less than V4.0

|  Runtime | node.js | Python | Java |
|:---------|:-------:|:------:|:----:|
| Required |    +    |        |      |

- [How to install node.js?](https://help.boundary.com/hc/articles/202360701)

### Plugin Setup

To collect statistics from nginx, it needs to built with the [nginx HttpStubStatusModule](http://nginx.org/en/docs/http/ngx_http_stub_status_module.html). If you used a package manager to install Nginx, it should be compiled by default, if you built Nginx yourself, you may need to recompile it.

#### Verify That `nginx` Includes `HttpStubStatusModule`

1. To check if your nginx has been build with the [nginx HttpStubStatusModule](http://nginx.org/en/docs/http/ngx_http_stub_status_module.html) run the following command, which will display the modules that are compiled in your version of `nginx`:
     ```bash
  $ nginx -V
    ```
2. If the string `--with-http_stub_status_module` is in the output then the installed `nginx` includes the `HttpStubStatusModule`. If the string is not there, you will need to install a package that includes the module or compile a version that includes it. Information on installing and/or compiling `nginx` can found here: [http://nginx.org/en/docs/install.html](http://nginx.org/en/docs/install.html)

#### `HttpStubStatusModule` Configuration

`nginx` requires configuration to provide URL path which will present the `nginx` statistics.

1. Edit your default `/etc/nginx/conf.d/virtual.conf` file (or whatever `.conf` file you are using) and add the following configuration in your `server {}` block:

     ```
  location /nginx_status {
    # activate stub_status module
    stub_status on;

    # do not log graphdat polling the endpoint
    access_log off;

    # restrict access to local only
    allow 127.0.0.1;
    deny all;

    # optional, should be JSON by default
          status_format json;
  }
     ```
2. Ensure that a listen address is configured in /etc/nginx/conf.d/virtual.conf under the server {} block as well. An complete example that configures the `HttpStubStatusModule` is shown here:

     ```
     server {
       listen       8000;
       location /nginx_status {
       # activate stub_status module
       stub_status on;

       # do not log graphdat polling the endpoint
       access_log off;

       # restrict access to local only
       allow 127.0.0.1;
       deny all;
       }
    }
    ```
3. (Only relevant for Nginx Plus) To enable collecting metrics per virtual server, you need to enable zones. See Nginx documentation for more details about [status_zone](http://nginx.org/en/docs/http/ngx_http_status_module.html#status_zone) directive. Several virtual servers may share the same zone.

    ```
    status_zone <your-zone-goes-here>;
    ```


4. Once you make the update, reload your nginx configuration:
    ```bash
     $ sudo service nginx reload
    ```

#### Verify `HttpStubStatusModule` is Collecting Statistics

1. Run the following command, which shows the expected output:
    ```bash
    $ curl http://localhost:8000/nginx_status
    Active connections: 1
    server accepts handled requests
    5 5 5
    Reading: 0 Writing: 1 Waiting: 0
    ```


### Plugin Configuration Fields

#### For All Versions

|Field Name    |Description                                                                                           |
|:-------------|:-----------------------------------------------------------------------------------------------------|
|Source        |The Source to display in the legend for the nginx data.  It will default to the hostname of the server|
|Statistics URL|The URL endpoint of where the nginx statistics are hosted.                                            |
|Strict SSL    |Use Strict SSL checking when HTTPS is enabled, enabled by default                                     |
|Username      |If the endpoint is password protected, what username should graphdat use when calling it.             |
|Password      |If the endpoint is password protected, what password should graphdat use when calling it.             |


### Metrics Collected

#### For All Versions

|Metric Name          |Description                       |
|:--------------------|:---------------------------------|
|Nginx Active Connections     |Active connections to nginx                                                                   |
|Nginx Reads                  |Connections with Nginx reading request headers                                                |
|Nginx Writes                 |Connections with Nginx reading request body, processing request or writing response to client.|
|Nginx Waiting                |Keep-alive connections with Nginx in a wait state                                             |
|Nginx Connections Handled    |Connections handled by nginx                                                                  |
|Nginx Connections Not Handled|Connections accepted, but not handled                                                         |
|Nginx Requests               |Requests to nginx                                                                             |
|Nginx Requests per Connection|Requests per handled connections for nginx                                                    |

### References

None

http = require 'http'
url = require 'url'
und = require 'underscore'
log = require 'winston'


allowMethods = process.env.ALLOW_METHODS || ['HEAD', 'GET','POST','PUT', 'DELETE', 'TRACE', 'OPTIONS', 'PATCH'].join ', '
allowHeaders = process.env.ALLOW_HEADERS || ['content-type','x-requested-with', 'accept', 'accept-language', 'accept-range', 'authorization'].join ', '

proxy = new (require 'http-proxy').RoutingProxy();
proxy.on 'error', (err) ->
  log.error "Error: #{err}"
proxy.on 'proxyError', (err) ->
  log.error "Proxy error: #{err}"

validHostname = (host) ->

  [host, port, extra...] = host.split ':'

  return false if extra.length > 0 # Multiple colons

  return true if host == 'localhost'

  return false if host.length > 255             # Max length
  return false if host.match(/^-/)              # Can't start with hyphen
  return false if host.match(/-$/)              # Can't end with hyphen
  return false if host.match(/[^a-z0-9\.-]/i)   # Can't have non alpha-numeric or dash characters (dot for hostnames)
  return false unless host.match( /\./)         # Must be specified beyond top level name

  return true

exports = module.exports = (options = {}) ->
  allowMethods = options.allowMethods || ['HEAD', 'GET','POST','PUT', 'DELETE', 'TRACE', 'OPTIONS', 'PATCH'].join ', '
  allowHeaders = options.allowHeaders || ['content-type','x-requested-with', 'accept', 'accept-language', 'accept-range', 'authorization'].join ', '


  return (req,res,next) ->

    if req.method == 'OPTIONS'
      # TODO - proxy options request to remote server
      res.setHeader 'access-control-max-age', 86400
      res.setHeader 'access-control-allow-credentials', 'true'
      res.setHeader 'access-control-allow-methods', allowMethods
      res.setHeader 'access-control-allow-headers', req['access-control-request-headers'] || allowHeaders

      res.write ''
      res.end()
      return

    protocols = ['http','https']

    # 1 to avoid the initial empty element
    pathParts = url.parse(req.url).path.split('/')[1..]

    if pathParts[0] in protocols
      protocol = pathParts.shift()
    else
      protocol = 'http'

    host = pathParts.shift()

    if !host or !validHostname(host)
      res.writeHead 400
      res.end()
      return


    toRequestUrl = url.parse( protocol + '://' + host + '/' + pathParts.join '/' )


    origWriteHead = res.writeHead
    res.writeHead = (statusCode, reasonPhrase, headers) ->

      headers = reasonPhrase if !headers?

      if req.headers.origin
        @setHeader 'access-control-allow-origin', req.headers.origin
      else
        @setHeader 'access-control-allow-origin', '*'

      @setHeader 'access-control-allow-credentials', 'true'
      @setHeader 'access-control-expose-headers', und.keys(headers)
      origWriteHead.apply this, arguments


    req.url = toRequestUrl.pathname


    console.log
      host: toRequestUrl.hostname
      port: toRequestUrl.port || 80
      https: toRequestUrl.protocol == 'https:'
      native: toRequestUrl.protocol

    proxy.proxyRequest(req, res, {
      host: toRequestUrl.hostname
      port: toRequestUrl.port || if (toRequestUrl.protocol == 'https:') then 443 else 80
      target: if (toRequestUrl.protocol == 'https:') 
          { https: true }
        else
          {}
      changeOrigin: true
    });

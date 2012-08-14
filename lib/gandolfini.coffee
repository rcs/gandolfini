http = require 'http'
url = require 'url'
und = require 'underscore'
winston = require 'winston'

logger = new (winston.Logger)(
  transports:[
    new (winston.transports.Console)(
      colorize: true
      timestamp: true
    )
  ]
)


logProxy = (original,proxyReq) ->
  ip = original.socket.remoteAddress || '-'
  ref = original.headers.referer || '-'
  origin = original.headers.origin || '-'

  logger.info "#{ip} \"#{ref}\" \"#{origin}\"  -> #{proxyReq.hostname}:#{proxyReq.port}/#{proxyReq.path}"



allowMethods = process.env.ALLOW_METHODS || ['HEAD', 'GET','POST','PUT', 'DELETE', 'TRACE', 'OPTIONS', 'PATCH'].join ', '
allowHeaders = process.env.ALLOW_HEADERS || ['content-type','x-requested-with', 'accept', 'accept-language', 'accept-range', 'authorization'].join ', '

proxy = new (require 'http-proxy').RoutingProxy();
proxy.on 'error', (err) ->
  logger.error "Error: #{err}"
proxy.on 'proxyError', (err) ->
  logger.error "Proxy error: #{err}"

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


    toRequestUrl = url.parse( protocol + '://' + host + '/' + pathParts.join '/' )
    req.url = toRequestUrl.path
    toRequestUrl.port ?= if (toRequestUrl.protocol == 'https:') then 443 else 80

    logProxy(req,toRequestUrl)

    proxy.proxyRequest(req, res, {
      host: toRequestUrl.hostname
      port: toRequestUrl.port
      target: if (toRequestUrl.protocol == 'https:') 
          { https: true }
        else
          {}
      changeOrigin: true
    });

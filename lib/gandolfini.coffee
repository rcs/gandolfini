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


# Internal: Log the origin, target of the proxy request
#
# original  - The originating request
# proxyReq  - The processed toRequest URL
#
# Returns nothing
logProxy = (original,proxyReq) ->
  ip = original.socket.remoteAddress || '-'
  ref = original.headers.referer || '-'
  origin = original.headers.origin || '-'

  logger.info "#{ip} \"#{ref}\" \"#{origin}\"  -> #{proxyReq.hostname}:#{proxyReq.port}/#{proxyReq.path}"



# Create the http-proxy we'll use for pushing requests
proxy = new (require 'http-proxy').RoutingProxy();
proxy.on 'error', (err) ->
  logger.error "Error: #{err}"
proxy.on 'proxyError', (err) ->
  logger.error "Proxy error: #{err}"

# Internal - Do some sanity checking on the host names we get
#
# host - The host to check for validity, possibly containing the ":port" specifier
#
# Returns true if valid, false if not
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


# Public - Configure the middleware
#
# options -
#   allowMethods - An array of methods to say we allow for pre-flight.  (Default: most HTTP verbs)
#   allowHeaders - An array of header values to say we allow for pre-flight (Default: content-type, x-requested-with, accept, accept-language, accept-range, authorization)
#
# Returns the middleware
exports = module.exports = (options = {}) ->
  allowMethods = options.allowMethods || ['HEAD', 'GET','POST','PUT', 'DELETE', 'TRACE', 'OPTIONS', 'PATCH'].join ', '
  allowHeaders = options.allowHeaders || ['content-type','x-requested-with', 'accept', 'accept-language', 'accept-range', 'authorization'].join ', '



  # Public - the middleware
  #
  # Responds to OPTIONS pre-flight request with CORS headers set
  #
  # Other methods proxy the requests to the URL specified in the req.path, with optional protocol
  # CORS headers are set on the responses.
  #
  # ex.
  #   '/example.com'                  -> http://example.com
  #   '/https/example.com'            -> https://example.com
  #   '/example.com:8080/a/b/c?query' -> http://example.com/a/b/c?query
  #
  return (req,res,next) ->

    # Write the pre-flight response
    if req.method == 'OPTIONS'
      # TODO - proxy options request to remote server
      res.setHeader 'access-control-max-age', 86400
      res.setHeader 'access-control-allow-credentials', 'true'
      res.setHeader 'access-control-allow-methods', allowMethods
      res.setHeader 'access-control-allow-headers', req['access-control-request-headers'] || allowHeaders

      res.write ''
      res.end()
      return


    # Things we recognize as protocols
    protocols = ['http','https']

    # 1 to avoid the initial empty element
    pathParts = url.parse(req.url).path.split('/')[1..]

    # If the first part of the path is something we recognize as a protocol use
    # that, otherwise default to http
    if pathParts[0] in protocols
      protocol = pathParts.shift()
    else
      protocol = 'http'

    host = pathParts.shift()

    # If we can't find a valid host, respond status 400
    if !host or !validHostname(host)
      res.writeHead 400
      res.end()
      return


    # Internal - Write the CORS headers on proxied responses
    # Modifes response inline
    #
    # Returns nothing

    # Save original writeHead for overriden use
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


    # Create a the proxy target url from parts
    toRequestUrl = url.parse( protocol + '://' + host + '/' + pathParts.join '/' )
    # Set request url to target url
    req.url = toRequestUrl.path

    # Set the port
    toRequestUrl.port ?= if (toRequestUrl.protocol == 'https:') then 443 else 80

    # Log our intentions
    logProxy(req,toRequestUrl)


    # Send the modified request to the proxy channel, setting target to our
    # parsed fragments
    proxy.proxyRequest(req, res, {
      host: toRequestUrl.hostname
      port: toRequestUrl.port
      target: if (toRequestUrl.protocol == 'https:') 
          { https: true }
        else
          {}
      changeOrigin: true
    });

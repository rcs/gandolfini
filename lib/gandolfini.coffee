URL = require 'url'
und = require 'underscore'
querystring = require 'querystring'
Path = require 'path'


# Internal: proxy singleton
#
# Returns a RoutingProxy
proxyChannel = do ->
  proxy = undefined
  ->
    proxy ||= new (require 'http-proxy').RoutingProxy();


# Public: Give a very allowing response to a CORS pre-flight OPTIONS request
#
# req     - The original request
# res     - The original response
# options (optional)
#         allowHeaders     - Allow-Headers to return (default: The request's Access-Control-Request-Headers)
#         allowCredentials - Allow-Credentials to return (default: 'true')
#         allowMethods     - Allow-Methods to return (default: The request's Access-Control-Request-Method
#         maxAge           - Access-Control-Maxe-Age to return (default: 86400)
#
# Ex.
#   if req.method == 'OPTIONS'
#     wildCors(req,res)
wildCors = (req,res,options = {}) ->
  options = und.defaults options,
    allowHeaders: req['access-control-request-headers']
    allowMethods: req['access-control-request-method']
    allowCredentials: 'true'
    maxAge: 86400

  res.setHeader 'access-control-max-age', options.maxAge
  res.setHeader 'access-control-allow-credentials', options.allowCredentials
  res.setHeader 'access-control-allow-methods', options.allowMethods
  res.setHeader 'access-control-allow-headers', options.allowHeaders

  res.write ''
  res.end()
  return

# Public: wrapper function for res.writeHead, adding CORS headers
#
# options (optional)
#         exposeHeaders    -  Value for Access-Control-Expose-Headers (default: all the headers on the response)
#         allowOrigin      - Value for Access-Control-Allow-Origin (default: '*')
#         allowCredentials - Value for Access-Control-Allow-Credentials (default: 'true')
#
# Returns a function that takes the original writeHead as the first argument, and accepts writeHead's parameters
#
# Ex.
#  res.writeHead = und.wrap res.writeHead, writeCorsHeadFunc(options)
writeCorsHeadFunc = (options) ->
  options = und.defaults options,
    allowOrigin: '*'
    allowCredentials: 'true'

  (original, statusCode, headers, reasonPhrase) ->
    # Add CORS headers
    @setHeader 'access-control-allow-origin', options.allowOrigin
    @setHeader 'access-control-allow-credentials', options.allowCredentials
    @setHeader 'access-control-expose-headers', options.exposeHeaders || und.keys(headers).join ','
    original.call this, statusCode, headers, reasonPhrase

# Public: Proxy a request to a target url
#
# req     - The original request
# res     - The original response
# url     - The URL to proxy to
# options - Passed to writeCorsHeadFunc (optional) 
#
# Returns nothing
#
# Ex.
#   bounceToUrl(req,res,'http://www.google.com')
bounceToUrl = (req, res, url, options = {}) ->
  options = und.defaults options,
    allowCredentials: 'true'
    allowOrigin: '*'
    headers: {}
    # exposeHeaders can be passed through to writeCorsHeadFunc

  # Make the target URL something useful
  parsed = URL.parse url

  # Set request URL to the target URL's path
  req.url = parsed.path

  # Add requested headers
  for own header, value of options.headers
    req.headers[header] = value

  # Override writeHead to add CORS headers to response
  res.writeHead = und.wrap res.writeHead, writeCorsHeadFunc(options)

  # Send the modified request to the proxy channel, setting target to our parsed fragments
  proxyChannel().proxyRequest(req, res, {
    host: parsed.hostname
    port: parsed.port || if (parsed.protocol.match /^https/ ) then 443 else 80
    target: if (parsed.protocol == 'https:')
        { https: true }
      else
        {}
    # Changes the Host: header on outgoing request to match the target
    changeOrigin: true
  });

# Public: Return a url path with a prefix
#
# Supports passing a protocol as the first part of the path past the prefix
#
# Ex.
#   urlFromPrefix('/proxy','/proxy/www.google.com') # -> 'www.google.com'
#   urlFromPrefix('/proxy','/proxy/https/www.google.com') # -> 'https://www.google.com'
urlFromPrefixed = (prefix,path) ->
  finalUrl = {}

  [targetPath, query] = Path.relative(prefix, path).split '?'
  pathParts = targetPath.split('/')

  finalUrl.protocol = if pathParts[0] in ['http','https']
    pathParts.shift()
  else
    'http'

  finalUrl.host =  pathParts.shift()

  finalUrl.pathname = pathParts.join '/'

  if query
    finalUrl.search = '?' + query 

  URL.parse URL.format finalUrl

# Public: Handle proxying urls 
#
# req          - the original request
# res          - the original response
# options -
#         pathPrefix   - the path prefix to proxy requests from (default: "/")
#         headerReplacements - An Object mapping query parameters to headers to add to the outgoing request
#
# Ex.
#   bouncingProxy(req,res,"/proxy",{"_gr": "referer"})
bouncingProxy = (req,res,options) ->
  options = und.defaults options,
    pathPrefix: "/"
    headerReplacements:
      _gr: 'referer'
      _gct: 'content-type'
      _ga: 'accept'

  targetUrl = URL.parse urlFromPrefixed( options.pathPrefix, req.url)

  targetUrl.query = do (query = querystring.parse(targetUrl.query)) ->
    for queryParam, header of options.headerReplacements when query[queryParam]
      req.headers[header] = query[queryParam]
      delete query[queryParam]

    query

  bounceToUrl(req,res,URL.format(targetUrl))

module.exports = 
  full: (options) ->
    (req,res) ->
      if req.method == 'OPTIONS'
        wildCors(req,res)
      else
        bouncingProxy(req,res,options)

  wildCors: wildCors
  writeCorsHeadFunc: writeCorsHeadFunc
  bounceToUrl: bounceToUrl
  urlFromPrefixed: urlFromPrefixed
  bouncingProxy: bouncingProxy

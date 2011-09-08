'express,oauth,sys,winston'
  # .split(',').forEach (lib) -> eval "console.log('#{lib}');"
  .split(',').forEach (lib) -> eval "#{lib} = require('#{lib}')"

T =

  ##############################################################################
  # ACTIONS
  ##############################################################################

  login: (req, res) ->
    T.consumer.getOAuthRequestToken (error, oauthToken, oauthTokenSecret, results) ->
      if error
        T.log.info "login error #{error}"
        return T.sendError req, res, "Error getting OAuth request token : " + sys.inspect(error), 500
      else
        req.session ||= {}
        req.session.oauthRequestToken = oauthToken
        req.session.oauthRequestTokenSecret = oauthTokenSecret
        return res.redirect "https://twitter.com/oauth/authorize?oauth_token=#{req.session.oauthRequestToken}"

  logout: (req, res) ->
    T.log.info "#{req.session.twitter.name} logged out"
    delete req.session.twitter
    res.redirect T.options.afterLogout

  callback: (req,res) ->
    T.consumer.getOAuthAccessToken req.session.oauthRequestToken,
      req.session.oauthRequestTokenSecret, req.query.oauth_verifier,
      (err, oauthAccessToken, oauthAccessTokenSecret, results) ->

        if err
          T.sendError req, res, "Error getting OAuth access token : #{sys.inspect(err)}" +
            "[#{oauthAccessToken}] [#{oauthAccessTokenSecret}] [#{sys.inspect(results)}]" 

        console.log "results", results, typeof(results)
        req.session.twitter =
          accessToken: oauthAccessToken
          accessTokenSecret: oauthAccessTokenSecret
          name: results.screen_name
        res.redirect T.options.afterLogin
        console.log "Redirected to #{T.options.afterLogin}"

  ##############################################################################
  # UTILS/HELPERS
  ##############################################################################

  sendError: (req,res,err) ->
      if err
        T.log.info "Login error #{err}"
        if process.env['NODE_ENV']=='development'
          res.send "Login error: #{err}", 500
        else
          res.send '<h1>Sorry, a login error occurred</h1>', 500
      else
        res.redirect '/' # todo

  debug: (req,res) ->
    return res.send('',404) unless process.env['NODE_ENV']=='development'
    m='<p><a href="/sessions/login">Login</a> <a href="/sessions/logout">Logout</a></p><h1>Session</h1>'
    if req.session
      m+="<details><summary>exists</summary><pre>#{sys.inspect(req.session)}</pre></details>"
    else
      m='<p>No session. Make sure you included cookieDecoder and session middleware BEFORE twitter.</p>'
    res.send m

  emptyLogger:
    debug: () -> null
    info:  () -> null

  ##############################################################################
  # PUBLIC INTERFACE
  ##############################################################################

  middleware: (_options) ->

    T.options = _options  || {}
    T.options.afterLogin  ||= '/'
    T.options.afterLogout ||= '/'
    T.log = if T.options.logging then winston else T.emptyLogger

    T.consumer = new oauth.OAuth(
      "https://twitter.com/oauth/request_token", "https://twitter.com/oauth/access_token",
      T.options.consumerKey, T.options.consumerSecret
      "1.0A", "#{T.options.baseURL}/sessions/callback", "HMAC-SHA1")

    return (req, res, next) ->
      if req.url=='/sessions/login' then action=T.login
      else if req.url=='/sessions/logout' then action=T.logout
      else if req.url=='/sessions/debug' then action=T.debug
      else if req.url.match(/^\/sessions\/callback/) then action=T.callback
      if action then action req,res else next()

  get: (apiPath, req, callback) ->
    callback 'no twitter session' unless req.session.twitter?
    T.consumer.get apiPath, req.session.twitter.accessToken, req.session.twitter.accessTokenSecret,
    (err, data, response) ->
      callback err, data, response

  post: (apiPath, req, body, callback) ->
    callback 'no twitter session' unless req.session.twitter?
    T.consumer.post apiPath, req.session.twitter.accessToken, req.session.twitter.accessTokenSecret, content
    (err, data, response) ->
      callback err, data, response
  
module.exports =
  middleware: T.middleware
  get: T.get
  post: T.post

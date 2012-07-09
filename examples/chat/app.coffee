###
  Moon.js Chat Example
###

# ugly message store
global.messages = []

module.exports = (app) ->

  # load config
  app.loadConfig "config.yaml"

  # set up routes
  app.routes "routes.coffee"

  # start app
  do app.start

  # only do the following if a worker
  if !app.options.cluster || app.cluster.isWorker

    # add bundles to asset manager
    app.assets.add
      # javascript bundles
      js: base: [
        "./assets/scripts/moon.js" # Load first
        "./assets/scripts/*"
      ]
      # css bundles
      css: base: [
        "./assets/styles/normalize.css", # Load first
        "./assets/styles/*"
      ]
      # client-side template bundles
      jst: base: "./views/client/chat-message.jade"

    # auth
    ###
    everyauth.github
      .entryPath("/auth/github")
      .appId("5697ce8265bd9e96df17")
      .appSecret("6f27d255afe257ed6468e568bb83658c75f39fb5")
      .findOrCreateUser((session, accessToken, accessTokenExtra, githubUserMetadata) ->
        # find or create user logic goes here
      )
      .redirectPath('/')

    app.server.use everyauth.middleware()
    ###

    # listen for new socket connections
    app.server.sockets.on "connection", (socket) ->
      socket.on "chat", (data) ->
        data.id = global.messages.length + 1
        global.messages.push data
        socket.broadcast.emit "chat", data
        socket.emit "chatRecieved", data.id

      # trim messages to 100
      global.messages = global.messages.reverse().splice(0, 100).reverse()
      # emit history
      socket.emit "chatHistory", messages

  return app
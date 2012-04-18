module.exports = (app) ->

  # load config
  app.loadConfig "config.yaml"
  # set up routes
  app.routes require "./routes"
  # start app
  app.start()

  messages = []
  if (!app.options.cluster || app.cluster.isWorker)
    app.server.sockets.on "connection", (socket) ->

      all = @sockets
      socket.on "chat", (data) ->
        messages.push data
        all.emit "chat", data

      # Trim messages to 100
      messages = messages.reverse().splice(0, 100).reverse()
      # emit history
      socket.emit "chatHistory", messages
  
  return app
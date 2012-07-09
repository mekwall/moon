$ ->
  window.msgs = []
  # Create view from pre-compiled template
  view = new Moon.View "chat-message", 
    moon.render "chat-message", 
    { time: new Date(), nick: " ", message: " " }

  addMessage = (data, instant) ->
    #$(moon.render("chat-message", data)).hide().attr("data-id", data.id).appendTo(messages)[(if instant then "show" else "slideDown")]()
    v = do view.clone
    v.container.hide().attr("data-id", data.id)
    v.appendTo messages
    v.time = new Date(data.time)
    v.message = data.message
    v.nick = data.nick
    do v.container.show
    window.msgs.push v
    v
    
  socket = window.socket
  messages = $("#messages")
  form = $("form")
  nick = $("input[name='nick']", form)
  message = $("input[name='message']", form)
  button = $("button", form)
  allInputs = nick.add(message).add(button)
  socket.on "chat", (data) ->
    addMessage data  if data.message

  socket.on "chatHistory", (data) ->
    html = ""
    $.each data, (i, data) ->
      addMessage data, true
    do $(window).resize

  $("form").submit (e) ->
    e.preventDefault()
    data =
      time: new Date()
      nick: nick.val() or "jdoe"
      message: message.val()

    return unless data.message

    nm = addMessage(data)
    socket.once "chatRecieved", (id) ->
      if id isnt false
        nm.container.attr "data-id", id
      else
        nm.container.remove()
        alert "Something went wrong. Your message was dropped."
      allInputs.prop "disabled", false
      $(window).resize()

    allInputs.prop "disabled", true
    socket.emit "chat", data
    message.val("").focus()

  $(".scrollable").scrollBars()
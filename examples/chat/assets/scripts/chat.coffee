$ ->
  addMessage = (data, instant) ->
    data.time = new Date(data.time)
    $(moon.render("chat-message", data)).hide().attr("data-id", data.id).appendTo(messages)[(if instant then "show" else "slideDown")]()
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

  $("form").submit (e) ->
    e.preventDefault()
    data =
      time: new Date()
      nick: nick.val() or "jdoe"
      message: message.val()

    nm = addMessage(data)
    socket.once "chatRecieved", (id) ->
      if id isnt false
        nm.attr "data-id", id
      else
        nm.remove()
        alert "Something went wrong. Your message was dropped."
      allInputs.prop "disabled", false

    allInputs.prop "disabled", true
    socket.emit "chat", data
    message.val("").focus()
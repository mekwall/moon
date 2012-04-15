###
qob
###

module.exports =

  ###
  Zero padding
  @param digits
  @param n
  ###
  zeroPad: (digits, n) ->
    n = n.toString()
    n = "0" + n while n.length < digits
    n

  ###
  Time string
  @param dt
  ###
  timeString: (dt) ->
    if (dt)
      dt = new Date(dt)
    else
      dt = new Date()
    @zeroPad(2, dt.getHours()) + ":" + @zeroPad(2, dt.getSeconds())
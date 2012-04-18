###
qob
###

module.exports =

  ###
  Zero padding
  ###
  zeroPad: (digits, n) ->
    n = n.toString()
    n = "0" + n while n.length < digits
    n

  ###
  Time string
  ###
  timeString: (dt, seconds=false) ->
    if (dt)
      dt = new Date(dt)
    else
      dt = new Date()
    ts = @zeroPad(2, dt.getHours()) + ":" + @zeroPad(2, dt.getMinutes())
    if seconds
      ts += ":" + @zeroPad(2, dt.getSeconds())
    ts

  ###
    Add chained attribute accessor
  ###
  addChaining: (obj, propertyAttr, attr) ->
    obj[attr] = (newValues...) ->
      if newValues.length == 0
        obj[propertyAttr][attr]
      else
        obj[propertyAttr][attr] = newValues[0]
        obj

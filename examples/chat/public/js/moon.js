function zeroPad (digits, n) {
  n = n.toString();
  while (n.length < digits)
    n = '0'+n;
  return n;
}

$(function(){
  var socket = window.socket = io.connect('', {
    resource: './sio'
  });

  socket.on('_moon', function(msg){
    if (msg.event) {
      switch (msg.event) {
        case "error":
          console.error("Error in: " + msg.data.file);
          throw Object.create(Error, msg.data.error);
        break;
        case "change":

          switch (msg.data.action) {
            case "reload":
              window.location.reload();
            break;
            case "reloadSingle":
              var file = msg.data.file,
                  url = file.replace("public", ""),
                  ext = file.split(".").pop().toLowerCase();
              switch (ext) {
                case "css":
                case "styl":
                  url = url.replace("styl", "css");
                  var curr= $("link[href='"+url+"']"),
                    rep = $('<link rel="stylesheet">').attr("href", url);
                  if (curr.length)
                    rep.insertAfter(curr).load(function(){
                      curr.remove();
                    });
                  else
                    rep.appendTo("head");
                break;

                case "png":
                case "jpg":
                case "gif":
                  var curr = $("img[src='"+url+"']");
                  curr.map(function(){
                    this.src = url;
                  });
                break;
              }

            break;
            case "update":

            break;
          }
        break;
      }
    }
  });
});
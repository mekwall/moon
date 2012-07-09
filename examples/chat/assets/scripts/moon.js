(function(window, $, undefined){
    if (!window.Moon) window.Moon = {};
    var pl = $("<div>");
    View = function (name, template) {
        var self = this;
        self.name = name;
        self.original = template;
        self.container = $(template);
        self._refs = {};
        var vars = self.container[0].nodeName === "MOON" ? 
          self.container : self.container.find("moon");

        vars.each(function(){
          var $this = $(this);
          var name = $this.data("var");
          var editable = $this.data("editable") ? true : false;
          var contents = $this.contents();
          var obj = $({
              name: name,
              initial: $this.clone().contents(),
              editable: editable,
              modifier: $this.data("modifier"),
              ref: contents,
              val: contents.html()
          });
            
          obj.toString = function() {
              return this[0].ref.html();
          };
           
          obj.on("update", function(e, val, noupdate) {
              if (!noupdate) {
                  if (val === "") { val = this.initial.clone(); }
                  if (this.modifier) {
                      val = View.Modifier[this.modifier](val);
                  }
                  pl.html(val);
                  var contents = pl.contents();
                  if (contents) {
                      this.ref.replaceWith(contents);
                      this.ref = contents;
                  }
              }
          });
          
          self._refs[name] = obj;    
          $this.replaceWith(contents);
            
          if (editable) {
              var span = $('<span contenteditable="true"></span>').on("keyup", function(){
                  obj.trigger("update", [$(this).html(), true]);
              });
              contents.wrap(span);
          }

          Object.defineProperty(self, name, {
              get: function() {
                  return self._refs[name];
              },
              set: function(val) {
                  self._refs[name].trigger("update", [val]);
              }
          });
        });

        self.container.find("[data-var], [data-attr], [data-target], [data-modifier]").each(function(){
          $(this)
            .removeAttr("data-var")
            .removeAttr("data-attr")
            .removeAttr("data-target")
            .removeAttr("data-modifier");
        });

        return self;
    }
        
    $.extend(View.prototype, {
        update: function(values) {
            for (key in values) {
              this._refs[key].trigger("update", values[key]);         
            }
        },
        appendTo: function(selector) {
            $(selector).append(this.container);
        },
        clone: function() {
            return new View(this.name, this.original);
        }            
    });

    View.Modifier = {
        time: function(val) {
          var date = new Date(val);
          var hours = date.getHours().toString();
          var minutes = date.getMinutes().toString();
          if (hours.length < 2) hours = "0" + hours;
          if (minutes.length < 2) minutes = "0" + minutes;
          return hours+":"+minutes;
        },
        date: function(val) {
          var date = new Date(val);
          return date.getUTCDate() + "/" + (date.getUTCMonth()+1);
        },
        ucwords: function(val) {
          if (typeof val !== "object") {
              val = val.split(" ").map(function(o,i){
                  var letters = o.split("");
                  return letters[0].toUpperCase() + letters.slice(1).join("");
              }).join(" ");
          }
          return val;
        }
    };
    window.Moon.View = View;
}(window, window.jQuery));

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
                  console.log(msg.data.changes);
                  url = url.replace(".styl", ".css");
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

_ = require 'underscore'
_.str = require 'underscore.string'
_.mixin _.str.exports()

clonePath = (path) ->
  newPos: path.newPos
  components: path.components.slice(0)

removeEmpty = (array) ->
  ret = []
  i = 0

  while i < array.length
    ret.push array[i]  if array[i]
    i++
  ret

class Diff
  
  constructor: (@ignoreWhitespace) ->
    this

  diff: (oldString, newString) ->
    # Handle the identity case (this is due to unrolling editLength == 0)
    return [ value: newString ] if newString is oldString

    unless newString
      return [
        value: oldString
        removed: true
      ]

    unless oldString
      return [
        value: newString
        added: true
      ]

    newString = @tokenize(newString)
    oldString = @tokenize(oldString)

    newLen = newString.length
    oldLen = oldString.length
    maxEditLength = newLen + oldLen
    bestPath = [ newPos: -1, components: [] ]

    # Seed editLength = 0
    oldPos = @extractCommon(bestPath[0], newString, oldString, 0)
    return bestPath[0].components  if bestPath[0].newPos + 1 >= newLen and oldPos + 1 >= oldLen
    editLength = 1

    while editLength <= maxEditLength
      diagonalPath = -1 * editLength
      while diagonalPath <= editLength
        basePath = undefined
        addPath = bestPath[diagonalPath - 1]
        removePath = bestPath[diagonalPath + 1]
        oldPos = (if removePath then removePath.newPos else 0) - diagonalPath
        bestPath[diagonalPath - 1] = `undefined` if addPath
        canAdd = addPath and addPath.newPos + 1 < newLen
        canRemove = removePath and 0 <= oldPos and oldPos < oldLen

        if not canAdd and not canRemove
          bestPath[diagonalPath] = `undefined`
        else
          if not canAdd or (canRemove and addPath.newPos < removePath.newPos)
            basePath = clonePath(removePath)
            @pushComponent basePath.components, oldString[oldPos], `undefined`, true
          else
            basePath = clonePath(addPath)
            basePath.newPos++
            @pushComponent basePath.components, newString[basePath.newPos], true, `undefined`

          oldPos = @extractCommon(basePath, newString, oldString, diagonalPath)
          if basePath.newPos + 1 >= newLen and oldPos + 1 >= oldLen
            return basePath.components
          else
            bestPath[diagonalPath] = basePath

        diagonalPath += 2
      editLength++

  pushComponent: (components, value, added, removed) ->
    last = components[components.length - 1]
    if last and last.added is added and last.removed is removed
      components[components.length - 1] =
        value: @join(last.value, value)
        added: added
        removed: removed
    else
      components.push
        value: value
        added: added
        removed: removed

  extractCommon: (basePath, newString, oldString, diagonalPath) ->
    newLen = newString.length
    oldLen = oldString.length
    newPos = basePath.newPos
    oldPos = newPos - diagonalPath
    while newPos + 1 < newLen and oldPos + 1 < oldLen and @equals(newString[newPos + 1], oldString[oldPos + 1])
      newPos++
      oldPos++
      @pushComponent basePath.components, newString[newPos], `undefined`, `undefined`
    basePath.newPos = newPos
    oldPos

  equals: (left, right) ->
    reWhitespace = /\S/
    if @ignoreWhitespace and not reWhitespace.test(left) and not reWhitespace.test(right)
      true
    else
      left is right

  join: (left, right) ->
    left + right

  tokenize: (value) ->
    value

class CharDiff extends Diff

class WordDiff extends Diff

  constructor: (@ignoreWhitespace = true) ->

  tokenize: (value) ->
    removeEmpty value.split(/(\s+|\b)/g)

class CssDiff extends Diff

  constructor: (@ignoreWhitespace = true) ->

  tokenize: (value) ->
    removeEmpty value.split(/([^{]+\s*\{\s*[^}]+)\s*}/g)

class LineDiff extends Diff

  tokenize: (value) ->
    values = value.split(/\n/g)
    ret = []
    i = 0

    while i < values.length - 1
      ret.push values[i] + "\n"
      i++
    ret.push values[values.length - 1]  if values.length
    ret

module.exports = 

  diff: (oldStr, newStr) ->
    new Diff().diff oldStr newStr

  diffChars: (oldStr, newStr) ->
    new CharDiff().diff oldStr, newStr

  diffWords: (oldStr, newStr) ->
    new WordDiff().diff oldStr, newStr

  diffLines: (oldStr, newStr) ->
    new LineDiff().diff oldStr, newStr

  diffCss: (oldStr, newStr) ->
    new CssDiff().diff oldStr, newStr

  diffHtml: (oldStr, newStr) ->
    new HtmlDiff().diff oldStr, newStr

  createPatch: (fileName, oldStr, newStr, oldHeader, newHeader) ->
    ret = []
    ret.push "Index: " + fileName
    ret.push "==================================================================="
    ret.push "--- " + fileName + "\t" + oldHeader
    ret.push "+++ " + fileName + "\t" + newHeader
    diff = new LineDiff().diff(oldStr, newStr)
    diff.push
      value: ""
      lines: []

    oldRangeStart = 0
    newRangeStart = 0
    curRange = []
    oldLine = 1
    newLine = 1
    i = 0

    while i < diff.length
      current = diff[i]
      lines = current.lines or current.value.replace(/\n$/, "").split("\n")
      current.lines = lines
      if current.added or current.removed
        unless oldRangeStart
          prev = diff[i - 1]
          oldRangeStart = oldLine
          newRangeStart = newLine
          if prev
            curRange.push.apply curRange, prev.lines.slice(-4).map((entry) ->
              " " + entry
            )
            oldRangeStart -= 4
            newRangeStart -= 4
        curRange.push.apply curRange, lines.map((entry) ->
          (if current.added then "+" else "-") + entry
        )
        if current.added
          newLine += lines.length
        else
          oldLine += lines.length
      else
        if oldRangeStart
          if lines.length <= 8 and i < diff.length - 1
            curRange.push.apply curRange, lines.map((entry) ->
              " " + entry
            )
          else
            contextSize = Math.min(lines.length, 4)
            ret.push "@@ -" + oldRangeStart + "," + (oldLine - oldRangeStart + contextSize) + " +" + newRangeStart + "," + (newLine - newRangeStart + contextSize) + " @@"
            ret.push.apply ret, curRange
            ret.push.apply ret, lines.slice(0, contextSize).map((entry) ->
              " " + entry
            )
            oldRangeStart = 0
            newRangeStart = 0
            curRange = []
        oldLine += lines.length
        newLine += lines.length
      i++
    ret.push "\\ No newline at end of file\n"  if diff.length > 1 and not /\n$/.test(diff[diff.length - 2].value)
    ret.join "\n"

  convertChangesToXML: (changes) ->
    ret = []
    i = 0

    while i < changes.length
      change = changes[i]
      if change.added
        ret.push "<ins>"
      else ret.push "<del>"  if change.removed
      ret.push _(change.value).escapeHTML()
      if change.added
        ret.push "</ins>"
      else ret.push "</del>"  if change.removed
      i++
    ret.join ""
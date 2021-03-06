Command = require '../command'
Range = require '../range'
Compiler = require '../compiler'
pygmentize = require 'pygmentize-bundled'
deasync = require 'deasync'

class Xecute extends Command

  name: ''

  last_error: null

  args: new Range(1, Infinity)

  constructor: ->
    super(arguments...)
    isCoffee = @app.isStandAlone or @find_file().type() is 'coffee'
    @compiler = new Compiler({@scope, isCoffee})
    @prompt.mode = @compiler.mode()
    @code = ''
    @indent = ''

  execute: (input, chain) ->
    return @switch_mode(chain) if input[0] == 'mode'
    res = @execute_code input.join(' ')
    res?.then?(-> chain.next()) or chain.next()

  colorizeLastLine: (prompt, code, lang) ->
    done = false
    pygmentize {lang, format: "terminal"}, code, (_, res) =>
      done = true
      process.stdout.moveCursor(0, -1)
      console.log prompt + res.toString().trim()
    deasync.runLoopOnce() until done

  eval_code: (code, language) ->
    @prompt.indent = @indent
    res = @compiler.execute(@code + @indent + code, language)
    next = (res) =>
      @output.prettySend res
      @code = @indent = ''
    res?.then?(next).catch(next) or next(res)

  execute_code: (code, language = @compiler.mode()) ->
    try
      if language isnt 'coffee'
        return @output.prettySend @compiler.execute(code, language)

      shouldDecreaseIndent = code.match(/^\s*(\}|\]|else|catch|finally|else\s+if\s+\S.*)$/)?

      prompt = @prompt.cli._prompt
      if code and shouldDecreaseIndent
        @indent = @indent.slice(0, -2)
        prompt = prompt.slice(0, -2)
        code += '  '

      if process.env.PRYINPUTCOLOR?
        @colorizeLastLine(prompt, code, language) if code
      else
        process.stdout.moveCursor(0, -1)
        console.log prompt + code

      shouldIncreaseIndent = code.match(///^\s*(.*class\s
        |[a-zA-Z\$_](\w|\$|:|\.)*\s*(?=\:(\s*\(.*\))?\s*((=|-)&gt;\s*$)) # function that is not one line
        |[a-zA-Z\$_](\w|\$|\.)*\s*(:|=)\s*((if|while)(?!.*?then)|for|$) # assignment using multiline if/while/for
        |(if|while|unless)\b(?!.*?then)|(for|switch|when|loop)\b
        |(else|try|finally|catch\s+\S.*|else\s+if\s+\S.*)\s*$
        |.*[-=]&gt;$
        |.*[\{\[]$)
        |\-\>\s*$///)?

      hasTrailingBackslash = code.trim().slice(-1) is '\\'
      if shouldIncreaseIndent or hasTrailingBackslash
        @code += @indent + (if hasTrailingBackslash then code.slice(0, -1) else code) + "\n"
        @indent += '  '
      else
        if @indent
          if code
            @code += @indent + code + "\n"
          else
            @prompt.count--
            @indent = @indent.slice(0, -2)
            if @indent
              process.stdout.moveCursor(0, -1)
            else
              return @eval_code(code)
        else
          return @eval_code(code)

      @prompt.indent = @indent

    catch err
      @prompt.indent = @code = @indent = ''
      @last_error = err
      @output.send err

  switch_mode: (chain) ->
    @compiler.toggle_mode()
    @prompt.mode = @compiler.mode()
    @output.send "Switched mode to '#{@compiler.mode()}'."
    chain.next()

  # Should always fallback to this
  match: (input, chain) ->
    [input, input]

module.exports = Xecute

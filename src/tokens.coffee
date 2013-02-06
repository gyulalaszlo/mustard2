# Call tokens:
# ['CALL', name, ['PARAMETERS'], ['CONTENTS']]
#
# String tokens:
# ['STRING', <string>]


Tokens =
  Call:
    get_contents: (t)-> t[3][1..]
    set_contents: (t, contents) -> t[3] = ['CONTENTS', contents...]

  # Returns true if the tokens can be evaluated compile time.
  is_compile_time: (tokens)->
    return false unless tokens
    for t in tokens
      return false if t.type != 'STRING'
    true

  compile_time_eval: (tokens)->
    o = []
    for t in tokens
      o.push t.contents
    o.join ''



module.exports = Tokens

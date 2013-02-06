

# Generate various opcodes
Opcodes =
  label: (value)-> [':', value]
  push: (value)-> { type:"PUSH", value:value}
  yield: ()-> {type:"YIELD"}
  local: (name, keys)-> {type:"VAR", name:name, sub_keys: keys}
  scoped_bool: (name)-> {type:"SCOPED_BOOL", name:name}
  scoped_local: (name, as)-> {type:"SCOPED_SINGLE", name:name, as:as}
  scoped_dict: (name, as1, as2)-> {type:"SCOPED_DICT", name:name, as:[as1, as2]}
  scope_end: (name)-> {type:"END_SCOPE", name: name}

  # Fold string constants.
  #
  # Takes a list of opcodes and returns a the list with neighbouring strings
  # concatenated.
  fold_constants: (list)->
    out = []
    string_buffer = []
    last_string = false
    for opcode in list
      if opcode.type == 'PUSH'
        last_string = true
        string_buffer.push opcode.value
      else
        if last_string
          # Flush the string buffer into the output buffer.
          out.push Opcodes.push( string_buffer.join('') )
          last_string = false
          string_buffer = []
        out.push opcode

    # Flush the string buffer
    out.push Opcodes.push( string_buffer.join('') )
    out



module.exports = Opcodes

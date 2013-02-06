_s = require 'underscore.string'

OpcodeAsm =
  # Create an assembler-like text representation for the compiled 
  # opcode stream.
  stringify: (list)->
    o = ["# Generated code"]
    for opcode in list
      instruction = opcode.type
      parameters =  []
      switch opcode.type
        when 'PUSH' then parameters = [ JSON.stringify(opcode.value)]
        when 'VAR' then parameters = [ opcode.name ]
        when 'SCOPE' then parameters = [ opcode.name ]
        when 'END_SCOPE' then parameters = [ opcode.name ]
        when 'SCOPED_SINGLE' then parameters = [ opcode.name, opcode.as ]
        when 'SCOPED_DICT' then parameters = [ opcode.name, opcode.as[0], opcode.as[1] ]

      o.push "#{_s.rpad instruction, 12 } #{ parameters.join(', ')}"
    o.join "\n"


module.exports = OpcodeAsm

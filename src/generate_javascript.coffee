_ = require 'underscore'


# Generate a javascript template from opcodes.
generate_javascript_code = (opcodes)->
  scopes = []
  o = ['function run_template(__locals, __mustard) {', 'var __buf=[];', "var __scope=__mustard.new_scope(__locals);"]

  for opcode in opcodes
    switch opcode.type
      when 'PUSH' then o.push "__buf.push(#{JSON.stringify opcode.value});"
      when 'VAR'
        o.push "__buf.push(#{_.flatten([opcode.name, opcode.sub_keys ]).join('.')});"
      when 'END_SCOPE'
        o.push "__mustard.end_scope(__scope);"
        o.push "}}"

      when 'SCOPED_BOOL'
        as = opcode.as
        ns = JSON.stringify opcode.name
        o.push "{ // Scope #{ opcode.name }"
        o.push "var __check_val = __mustard.get_bool( __scope,  #{ns});"
        o.push "if(__check_val) {"
        o.push "__mustard.start_scope( __scope, {} );"

      when 'SCOPED_SINGLE'
        as = opcode.as
        ns = JSON.stringify opcode.name
        objs_name = _.uniqueId '__objs'
        o.push "{ // Scope #{ opcode.name }"
        o.push "var #{objs_name} = __mustard.get_single( __scope,  #{ns});"
        o.push "for(var #{as}_i = 0; #{as}_i < #{objs_name}.length; ++#{as}_i) {"
        o.push "var #{as} = #{objs_name}[#{as}_i];"
        o.push "__mustard.start_scope( __scope, {'#{as}':#{as}});"

      when 'SCOPED_DICT'
        [as, as_val] = opcode.as
        ns = JSON.stringify opcode.name
        objs_name = _.uniqueId '__objs'
        o.push "{ // Scope #{ opcode.name }"
        o.push "var #{objs_name} = __mustard.get_dict( __scope,  #{ns});"
        o.push "for(var #{as}_i = 0; #{as}_i < #{objs_name}.length; ++#{as}_i) {"
        o.push "var #{as} = #{objs_name}[#{as}_i][0];"
        o.push "var #{as_val} = #{objs_name}[#{as}_i][1];"
        o.push "__mustard.start_scope( __scope, {'#{as}':#{as}, '#{as_val}':#{as_val} });"


  o.push "return __buf.join('');", '}', 'run_template(locals, mustard_runtime);'
  o.join "\n"

module.exports = generate_javascript_code

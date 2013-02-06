PEG = require("pegjs")
fs = require('fs')
path = require 'path'

_ = require 'underscore'
_s = require 'underscore.string'

argv = require('optimist')
  .boolean(['dump_ast','dump_opcode','dump_compiled'])
  .argv

mustard_runtime = require './src/mustard_runtime.coffee'
Stack = require './src/stack.coffee'


# Call tokens:
# ['CALL', name, ['PARAMETERS'], ['CONTENTS']]
#
# String tokens:
# ['STRING', <string>]


# opcodes:
#
# PUSH <STRING>  
# push a string to the buffer
# 
# CALL <SYMBOL> <PARAMETER_LINK_ID> <CONTENTS_LINK_ID>
# call the symbol


# A simple wrapper function the logging of verbose data
log_verbose = (args...)->
  process.stdout.write "#{ _.map( args, (e)-> if _.isString(e) then e else JSON.stringify(e) ).join(' | ')}\n"

# A wrapper for logging errors
log_error = (args...)->
  process.stderr.write "#{args.join(' | ')}\n"


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



# Any internal error tries to trigger a handler from these.
error_handlers =

  # Triggered on compilation syntax error.
  #
  # filename is the name of the template file
  # e is a PEGJS SyntaxError
  SyntaxError: (filename, e)->
    log_error "#{filename}:#{e.line}:#{e.column} Syntax Error: #{e.message}\n"


  IOError: (msg, filename, e)->
    log_error "IO Error", msg, filename, e
    

  ParseError: (msg, e)->
    log_error "Parse Error", msg, e
    


# Compile a single template using parser.
#
# returns null if any errors occured
compile_template = (parser, filename, options, data)->
  try
    res = parser.parse data
  catch e
    # re-throw anything other then syntax error
    throw e unless e.name == "SyntaxError"
    # call the error handler
    error_handlers.SyntaxError filename, e
    return null
  res
 


# A wrapper for saving a file.
#
# Options:
# json: <boolean, false>  Convert data to JSON before writing.
save_file = (filename, data, options={})->
  written_data = data
  options = _.defaults options, {json: false, pretty: false}

  # convert to json if necessary
  if options.json
    if options.pretty
      written_data = JSON.stringify written_data, null, 4
    else
      written_data =  JSON.stringify written_data, null, 4

  fs.writeFile filename, written_data, 'utf8', (err)->
    # handle errors
    if err
      error_handlers.IOError "Error while writing", filename, err
      return
    log_verbose "Written", filename, "#{written_data.length} bytes"



# Extract a list of definitions from the tokens
extract_definitions = ( tokens )->
  definitions = {}
  # all definitions are on the top level of the token stream
  for token in tokens
    continue if token.type != 'DEFINE'
    definitions[token.name] = token.contents

  definitions


# Extract all the blocks (list of tokens) deeper then the main token list
# into a separate list, get a copy of the top-level tokens with these references.
# This should enable to handle mustard templates in a more linear fashion.
#
# Returns
# [ list, linked_tokens]:
#
# ### list:   
#
# The collected list of blocks keyed by filename/id. 
# This is updated
#
# ### linked_tokens
#
# A list of the current level tokens replaced with their linked id.
create_block_list = (filename, tokens, list={})->
  linked_tokens = []
  for token in tokens
    if token.type == 'CALL' || token.type == 'DEFINE'
      contents = token.contents
      continue unless contents
      # Go recursive without adding the child tokens 
      # to the linked_tokens.
      create_block_list filename, contents, list
      # the id is the current length of the list
      id = "#{filename}:#{ _.size list }"
      list[id] = contents
      token.contents = [{ type: 'LINK', id: id }]

    # Add the -possibly modified token-
    # to the linked list
    linked_tokens.push token

  [list, linked_tokens]
  

# Extract the top level template content from the tokens
extract_content = (tokens)->
  contents = []
  # all definitions are on the top level of the token stream
  for token in tokens
    continue if token.type == 'DEFINE'
    contents.push token

  contents



evaluate_call = (call_token, definitions, blocks)->
  def = definitions[call_token.name]



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

  





# The main evaluator.
evaluate_contents = (o, content_tokens, blocks, definitions, stack, e_stack, contents = [])->
  for token in content_tokens
    switch token.type
      when 'STRING'
        o.push Opcodes.push( token.contents )
      when 'VARIABLE'
        # Check if the variable is available at compile time
        #local = stack.get_local token.name
        local = Stack.find_local e_stack, token.name
        # Avoid recursion if the name of the variable in the call
        # is the same name as a variable used inside the call.
        if local &&  local.length == 1 && local[0].type == 'VARIABLE' && local[0].name == token.name
          local = null
        # If the variable is avaialable at compile time, 
        # evaluate it and add it to the opcode list.
        if local
          evaluate_contents( o, local, blocks, definitions, stack, e_stack, contents)
        # If no such local is available, this should be a template
        # parameter.
        else
          o.push Opcodes.local( token.name, token.sub_keys )
      when 'SCOPE'
        scoped_local_name = token.open.name
        current_locals = Stack.get_current_locals(e_stack)
        scope_target = null
        is_compile_time = false
        # @_ is a special variable available at compile time,
        # contining all the parameters passed to the current
        # caller or all the locals when used at the top level.
        if scoped_local_name == '_'
          scope_target = current_locals
          is_compile_time = true
        else
          scope_target = Stack.find_local e_stack, scoped_local_name
          is_compile_time = Tokens.is_compile_time scope_target
          if is_compile_time
            scope_target = Tokens.compile_time_eval scope_target


        locals_count = token.locals.length
        switch locals_count
          when 0
            unless is_compile_time
              o.push Opcodes.scoped_bool( token.open.name)
              locals_used = {}
              # add a new level to the stack
              Stack.push_level e_stack, locals_used
              # Evaluate the contents of the scope.
              evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
              # Remove the locals from the scope from the stack.
              Stack.pop_level e_stack

          # If a single local is used, its either a single object
          # or an array iterating single objects.
          when 1
            l = token.locals[0]
            unless is_compile_time
              o.push Opcodes.scoped_local( token.open.name, l)
              locals_used = {}
              locals_used[l] = Opcodes.local(l)
              # add a new level to the stack
              Stack.push_level e_stack, locals_used
              # Evaluate the contents of the scope.
              evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
              # Remove the locals from the scope from the stack.
              Stack.pop_level e_stack

          # Two locals open a dictionnary by key/value pairs
          when 2
            [k,v] = token.locals
            unless is_compile_time
              locals_used = {}
              o.push Opcodes.scoped_dict( token.open.name, k, v)
              locals_used[k] = Opcodes.local(k)
              locals_used[v] = Opcodes.local(v)
              # add a new level to the stack
              Stack.push_level e_stack, locals_used
              # Evaluate the contents of the scope.
              evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
              # Remove the locals from the scope from the stack.
              Stack.pop_level e_stack

            else
              for k, v of scope_target
                as = token.locals
                locals_used = {}
                locals_used[as[0]] = [{ type: 'STRING', contents: k }]
                locals_used[as[1]] = v
                # add a new level to the stack
                Stack.push_level e_stack, locals_used
                # Evaluate the contents of the scope.
                evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
                # Remove the locals from the scope from the stack.
                Stack.pop_level e_stack


        ## Evaluate the contents of the scope.
        #evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
        ## Remove the locals from the scope from the stack.
        #Stack.pop_level e_stack
        #stack.pop()
        # Add the scope end opcode
        unless is_compile_time
          o.push Opcodes.scope_end( token.open.name )
      when 'YIELD'
        Stack.push_yield_context e_stack
        evaluate_contents(o, Stack.get_yield_contents(e_stack), blocks, definitions, stack, e_stack, [] )
        Stack.pop_yield_context e_stack
      when 'LINK'
        # Check if the linked block exists
        block_tokens = blocks[token.id]
        unless block_tokens
          error_handlers.ParseError( "Unknown linked block: #{token.id}", null) unless block_tokens
        else
          evaluate_contents(o, block_tokens, blocks, definitions, stack, e_stack, contents )
      when 'CALL'
        # Check if the linked block exists
        block_tokens = definitions[token.name]
        unless block_tokens
          error_handlers.ParseError( "Unknown symbol to call:", token.name) unless block_tokens
        else
          # Add the parameters to the stack.
          #stack.push token.name, token.parameters
          #stack.push_yield token.contents
          
          stack_frame_id = Stack.push_level e_stack, token.parameters
          Stack.push_yield_level e_stack, token.contents
          evaluate_contents(o, block_tokens, blocks, definitions, stack, e_stack, token.contents)
          Stack.pop_yield_level e_stack
          Stack.pop_level e_stack
          #stack.pop_yield
          # Pop the stack.
          #stack.pop()
  # return the constructed list
  o




# Fold string constants.
#
# Takes a list of opcodes and returns a the list with neighbouring strings
# concatenated.
opcode_fold_constants = (list)->
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

    
# Create an assembler-like text representation for the compiled 
# opcode stream.
format_opcode_list = (list)->
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



# Parse the prevously tokensized template.
parse_tokenized_template = (filename, tokens, options={})->
  log_verbose "started parsing", filename
  # create the block list
  [blocks, linked_tokens] = create_block_list filename, tokens

  # extract the definitions
  definitions = extract_definitions linked_tokens
  # extract the contents
  contents = extract_content linked_tokens

  # Dump all of these if requested
  if options.dump_compiled
    save_file "#{filename}.blocks.json", blocks, json:true
    save_file "#{filename}.linked.json", linked_tokens, json:true
    save_file "#{filename}.contents.json", contents, json:true
    save_file "#{filename}.defs.json", definitions, json:true

  e_stack = Stack.make_stack()
  opcode_list = evaluate_contents([], contents, blocks, definitions, null, e_stack)
  opcode_list = opcode_fold_constants opcode_list
  opcode_string = format_opcode_list opcode_list

  if options.dump_opcode
    save_file "#{filename}.opcodes.json", opcode_list, json:true
    save_file "#{filename}.opcodes.txt", opcode_string


  js_code = generate_javascript_code opcode_list
  save_file "#{filename}.js", js_code

  title = "TITLE"
  subtitle = "SUBTITLE"
  product = {name: "PRODUCT NAME", tagline: "PRODUCT TAGLINE", tags: ['product', 'small'] }
  product2 = {name: "PRODUCT2 NAME", tagline: "PRODUCT2 TAGLINE" , tags: ['product', 'large'] }
  page_subtitle = "PAGE SUBTITLE"
  current_user = { name: "Miles Davis", id:"miles.davis@gmail.com"}
  products = [ product, product2 ]
  locals = { products: products, current_user: current_user, users: [current_user] }
  console.log "--------------------"
  try
    console.log eval(js_code)
  catch e
    console.log e
  console.log "--------------------"



  log_verbose "parsed", filename




# The compile starter function.
compile_template_from_file = ( parser, filename, options )->
  #
  # Try to load the template file
  fs.readFile filename, 'utf8', (err, data)->
    throw err if err
    log_verbose "Compiling", filename
    # generate the AST
    ast = compile_template parser, filename, options, data
    return null unless ast
    # Save the ast as a json file.
    #
    ast_file_name = path.basename(filename)
    if options.dump_ast
      save_file "#{filename}.ast.json", ast, json:true
    # try to parse the stream
    parse_tokenized_template filename, ast, options
    





# Generate a new PEG parser from the grammar.
generate_parser = (parser_filename)->
  PEG.buildParser( fs.readFileSync(parser_filename, 'utf8') )





parser = generate_parser 'src/mustard.pegjs', trackLineAndColumn: true

for file in argv._
  compile_template_from_file parser, file, argv

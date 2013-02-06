PEG = require("pegjs")
fs = require('fs')
path = require 'path'

_ = require 'underscore'
_s = require 'underscore.string'

argv = require('optimist')
  .boolean(['dump_ast','dump_opcode','dump_compiled'])
  .argv


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
  scoped_local: (name, as)-> {type:"SCOPED_SINGLE", name:name, as:as}
  scoped_dict: (name, as1, as2)-> {type:"SCOPED_DICT", name:name, as:[as1, as2]}
  scope_end: (name)-> {type:"END_SCOPE", name: name}
  


# ## The evaluation Stack
#
# The template opcode is evaluated using this stack.
Stack =
  # Create a new stack
  make_stack: ->
    o = { current:'root', levels: {}, yields: [], yielded_from:[], used_yields:[] }
    o.levels.root = Stack.make_level 'root', null, {}
    o

  # Create a new level for the evaluation stack
  make_level: (id, parent_id, locals)->
    { id: id, locals: locals, parent_id: parent_id }

  # Create a yield stack, that references a specific
  # stack level as context.
  make_yield_level: (id, level_id, contents )->
    { id:id, contents: contents, level_id: level_id }


  # Add a new level to the stack, with parent_id as the
  # id of the stack level bellow it.
  #
  # Returns the id of the new stack level
  #
  # locals : The locals used on the current stack level.
  add_level: (stack, parent_id, locals)->
    id = _.uniqueId 'stack_'
    stack.levels[id] = Stack.make_level(id, parent_id, locals)
    id

  # Remove a level from the stack.
  remove_level: (stack, level_id)->
    delete stack.levels[level_id]


  # Get the current level of the stack.
  current_level: (stack)-> stack.levels[ stack.current ]

  get_current_locals: (stack)-> Stack.current_level(stack).locals

  # Push a new level on top of the running stack.
  push_level: (stack, locals)->
    current = Stack.current_level stack
    id = Stack.add_level stack, current.id, locals
    stack.current = id


  # Pop the topmost level of the stack
  pop_level: (stack)->
    current = Stack.current_level stack
    stack.current = current.parent_id
    id_to_remove = current.id
    Stack.remove_level stack, current.id




  push_yield_level: (stack, contents)->
    id = _.uniqueId 'yield_'
    level_id = stack.current
    stack.yields.push Stack.make_yield_level( id, level_id, contents )


  pop_yield_level: (stack)->
    stack.yields.pop()

  # Get the yield for the current context
  get_yield: (stack)->
    y = _.last stack.used_yields
    unless y
      console.log "Cannot find yield."
      console.log "STACK:-------------------------------"
      console.dir stack
    y

  # Get the contents of the yield for the current context.
  get_yield_contents: (stack)-> Stack.get_yield(stack).contents


  # Put the context of the yield on top of the existing stack (so it'll link
  # it to the original level where it was declared)
  push_yield_context: (stack)->
    current = Stack.current_level stack
    # Store the id of the current level so we can restore it later.
    stack.yielded_from.push current.id
    stack.used_yields.push stack.yields.pop()
    current_yield = Stack.get_yield stack
    # Create a new stack level and point it to the yield's context.
    id = Stack.add_level stack, current_yield.level_id, {}
    stack.current = id


  pop_yield_context: (stack)->
    old_context = stack.yielded_from.pop()
    Stack.remove_level stack, stack.current
    stack.current = old_context
    stack.yields.push stack.used_yields.pop()





  # Find a local in the stack.
  # 
  # id: the id of the top level of the stack to start the search
  # from. If null, the search starts from the current level of the stack.
  find_local: (stack, name, id=null)->
    id = stack.current if id == null
    level = stack.levels[id]
    if level == undefined
      #return null
      log_error "Cannot find level", JSON.stringify(id), 'in', stack.levels
      return null
    val = level.locals[name]
    return val if val != null
    return null if level.parent_id == null
    Stack.find_local stack, name, level.parent_id



    



# The stack for the evaluation of the templates
class EvaluationStack

  constructor: ->
    @locals = []
    @names = []
    @yield_stack = []
    @yield_indices = []


  # add a new layer to the stack
  push: (name, parameters)->
    @names.push name
    @locals.push parameters

  pop: ->
    @names.pop()
    @locals.pop()


  push_yield: (yield_contents)->
    @yield_stack.push yield_contents

  pop_yield: -> 
    @yield_stack.pop()

    

  get_yield: ->
    _.last( @yield_stack )

  
  get_local: (name)->
    local = @find_local @locals, name
    local



  # try to find a local in the layers
  find_local: (layers, name)->
    # not found if we hit the last layer
    return null if layers.length == 0
    # try to find it in the top layer
    if _.last(layers) == undefined
      log_verbose "undefined layer", layers
    local = _.last( layers )[name]
    return local if local
    # go recursive if not found
    @find_local( layers[0..-2], name )


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
        # @_ is a special variable available at compile time,
        # contining all the parameters passed to the current
        # caller or all the locals when used at the top level.
        if token.open == '_'
          for k, v of Stack.get_current_locals(e_stack)
            console.log "K,V",k,v
            as = token.locals
            locals_used = {}
            locals_used[as[0]] = [{ type: 'STRING', contents: k }]
            locals_used[as[1]] = v
            Stack.push_level e_stack, locals_used
            log_verbose 'stack', JSON.stringify(e_stack, null, 4)
            # Evaluate the contents of the scope.
            evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
            # Remove the locals from the scope from the stack.
            Stack.pop_level e_stack

          break

        locals_count = token.locals.length
        switch locals_count
          # If a single local is used, its either a single object
          # or an array iterating single objects.
          when 1
            l = token.locals[0]
            o.push Opcodes.scoped_local( token.open, l)
            locals_used = {}
            locals_used[l] = Opcodes.local(l)
            Stack.push_level e_stack, locals_used
          when 2
            [k,v] = token.locals
            o.push Opcodes.scoped_dict( token.open, k, v)
            locals_used = {}
            locals_used[k] = Opcodes.local(k)
            locals_used[v] = Opcodes.local(v)
            Stack.push_level e_stack, locals_used

        # Evaluate the contents of the scope.
        evaluate_contents( o, token.contents, blocks, definitions, stack, e_stack, contents)
        # Remove the locals from the scope from the stack.
        Stack.pop_level e_stack
        #stack.pop()
        # Add the scope end opcode
        o.push Opcodes.scope_end( token.open )
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
  o = ['function run_template(__locals) {', 'var __buf=[];', "var __scope=mustard_new_scope(__locals);"]

  for opcode in opcodes
    switch opcode.type
      when 'PUSH' then o.push "__buf.push(#{JSON.stringify opcode.value});"
      when 'VAR' 
        o.push "__buf.push(#{_.flatten([opcode.name, opcode.sub_keys ]).join('.')});"
      when 'SCOPE'
        o.push "function scope_#{_s.underscored opcode.name }() {"
      when 'END_SCOPE'
        o.push "}}"
      when 'SCOPED_SINGLE'
        as = opcode.as
        ns = JSON.stringify opcode.name
        o.push "{ // Scope #{ opcode.name }"
        o.push "var __objs = mustard_get_single( __scope,  #{ns});"
        o.push "for(var #{as}_i = 0; #{as}_i < __objs.length; ++#{as}_i) {"
        o.push "var #{as} = __objs[#{as}_i];"

      when 'SCOPED_DICT'
        [as, as_val] = opcode.as
        ns = JSON.stringify opcode.name
        o.push "{ // Scope #{ opcode.name }"
        o.push "var __objs = mustard_get_dict( __scope,  #{ns});"
        o.push "for(var #{as}_i = 0; #{as}_i < __objs.length; ++#{as}_i) {"
        o.push "var #{as} = __objs[#{as}_i][0];"
        o.push "var #{as_val} = __objs[#{as}_i][1];"


  o.push "return __buf.join('');", '}', 'run_template(locals);'
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

  stack = new EvaluationStack
  e_stack = Stack.make_stack()
  opcode_list = evaluate_contents([], contents, blocks, definitions, stack, e_stack)
  opcode_list = opcode_fold_constants opcode_list
  opcode_string = format_opcode_list opcode_list

  if options.dump_opcode
    save_file "#{filename}.opcodes.json", opcode_list, json:true
    save_file "#{filename}.opcodes.txt", opcode_string


  js_code = generate_javascript_code opcode_list
  save_file "#{filename}.js", js_code

  title = "TITLE"
  subtitle = "SUBTITLE"
  product = {name: "PRODUCT NAME", tagline: "PRODUCT TAGLINE" }
  product2 = {name: "PRODUCT2 NAME", tagline: "PRODUCT2 TAGLINE" }
  page_subtitle = "PAGE SUBTITLE"
  current_user = { name: "Miles Davis", id:"miles.davis@gmail.com"}
  products = [ product, product2 ]
  locals = { products: products, current_user: current_user }
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

mustard_new_scope = (locals)-> [locals]

# Start a scope.
mustard_start_scope = (scope, object)-> scope.push object
mustard_end_scope = (scope, object)-> scope.pop
mustard_get_single = (scope, name)->
  o = _.last( scope )[name]
  if _.isArray(o)
    o
  else
    [o]

mustard_get_dict = (scope, name)->
  o = _.last( scope )[name]
  if _.isObject(o)
    _.pairs o
  else
    []


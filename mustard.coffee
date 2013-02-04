PEG = require("pegjs")
argv = require('optimist').argv

fs = require('fs')
path = require 'path'

_ = require 'underscore'
_s = require 'underscore.string'


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
  local: (name)-> {type:"VAR", name:name}
  

# The stack for the evaluation of the templates
class EvaluationStack

  constructor: ->
    @locals = []
    @names = []


  # add a new layer to the stack
  push: (name, parameters)->
    @names.push name
    @locals.push parameters

  pop: ->
    @names.pop()
    @locals.pop()
    


  
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
evaluate_contents = (o, content_tokens, blocks, definitions, stack, contents = [])->
  for token in content_tokens
    switch token.type
      when 'STRING'
        o.push Opcodes.push( token.contents )
      when 'VARIABLE'
        # Check if the variable is available at compile time
        local = stack.get_local token.name
        # Avoid recursion if the name of the variable in the call
        # is the same name as a variable used inside the call.
        if local &&  local.length == 1 && local[0].type == 'VARIABLE' && local[0].name == token.name
          local = null
        # If the variable is avaialable at compile time, 
        # evaluate it and add it to the opcode list.
        if local
          evaluate_contents( o, local, blocks, definitions, stack, contents)
        # If no such local is available, this should be a template
        # parameter.
        else
          o.push Opcodes.local( token.name )
      when 'YIELD'
        evaluate_contents(o, contents, blocks, definitions, stack, [] )
      when 'LINK'
        # Check if the linked block exists
        block_tokens = blocks[token.id]
        unless block_tokens
          error_handlers.ParseError( "Unknown linked block: #{token.id}", null) unless block_tokens
        else
          evaluate_contents(o, block_tokens, blocks, definitions, stack, contents )
      when 'CALL'
        # Check if the linked block exists
        block_tokens = definitions[token.name]
        unless block_tokens
          error_handlers.ParseError( "Unknown caled symbol:", token.name) unless block_tokens
        else
          # Add the parameters to the stack.
          stack.push token.name, token.parameters
          evaluate_contents(o, block_tokens, blocks, definitions, stack, token.contents)
          # Pop the stack.
          stack.pop()
  # return the constructed list
  o




# Fold string constants 
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
    o.push "#{_s.rpad instruction, 6 } #{ parameters.join(', ')}"

  o.join "\n"


# Parse the prevously tokensized template.
parse_tokenized_template = (filename, tokens, options={})->
  log_verbose "started parsing", filename
  # create the block list
  [blocks, linked_tokens] = create_block_list filename, tokens
  save_file "#{filename}.blocks.json", blocks, json:true
  save_file "#{filename}.linked.json", linked_tokens, json:true

  # extract the definitions
  definitions = extract_definitions linked_tokens
  save_file "#{filename}.defs.json", definitions, json:true
  # extract the contents
  contents = extract_content linked_tokens
  save_file "#{filename}.contents.json", contents, json:true

  stack = new EvaluationStack
  opcode_list = evaluate_contents([], contents, blocks, definitions, stack)
  opcode_list = opcode_fold_constants opcode_list
  opcode_string = format_opcode_list opcode_list
  save_file "#{filename}.opcodes.json", contents, json:opcode_list
  save_file "#{filename}.opcodes.txt", opcode_string


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
    save_file "#{filename}.ast.json", ast, json:true
    # try to parse the stream
    parse_tokenized_template filename, ast, options
    





# Generate a new PEG parser from the grammar.
generate_parser = (parser_filename)->
  PEG.buildParser( fs.readFileSync(parser_filename, 'utf8') )





parser = generate_parser 'src/mustard.pegjs', trackLineAndColumn: true

for file in argv._
  compile_template_from_file parser, file, argv




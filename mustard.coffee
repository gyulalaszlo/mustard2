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
Tokens = require './src/tokens.coffee'
Opcodes = require './src/opcodes.coffee'
OpcodeAsm = require './src/opcode_asm_format.coffee'

generate_javascript_code = require './src/generate_javascript.coffee'
extract_definitions = require './src/extract_definitions.coffee'
extract_contents = require './src/extract_contents.coffee'
create_block_list = require './src/replace_tokens_with_links.coffee'


evaluate_contents = require './src/evaluate_contents.coffee'


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






evaluate_call = (call_token, definitions, blocks)->
  def = definitions[call_token.name]


  







# Parse the prevously tokensized template.
parse_tokenized_template = (filename, tokens, options={})->
  log_verbose "started parsing", filename
  # create the block list
  [blocks, linked_tokens] = create_block_list filename, tokens

  # extract the definitions
  definitions = extract_definitions linked_tokens
  # extract the contents
  contents = extract_contents linked_tokens

  # Dump all of these if requested
  if options.dump_compiled
    save_file "#{filename}.blocks.json", blocks, json:true
    save_file "#{filename}.linked.json", linked_tokens, json:true
    save_file "#{filename}.contents.json", contents, json:true
    save_file "#{filename}.defs.json", definitions, json:true

  e_stack = Stack.make_stack()
  opcode_list = evaluate_contents([], contents, blocks, definitions, null, e_stack)
  opcode_list = Opcodes.fold_constants opcode_list
  opcode_string = OpcodeAsm.stringify opcode_list

  if options.dump_opcode
    save_file "#{filename}.opcodes.json", opcode_list, json:true
    save_file "#{filename}.opcodes.txt", opcode_string


  js_code = generate_javascript_code opcode_list
  save_file "#{filename}.js", js_code

  console.log "TESTING:"

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

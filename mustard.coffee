PEG = require("pegjs")
argv = require('optimist').argv
fs = require('fs')


template_parser_grammar = null


# The template files to compile
templates_filename = argv._



error_handlers =
  SyntaxError: (filename, e)->
    process.stderr.write "#{filename}:#{e.line}:#{e.column} Syntax Error: #{e.message}\n"



# The compile starter function.
compile_template = ( parser, filename, options )->
  #
  # Try to load the template file
  fs.readFile filename, 'utf8', (err, data)->
    throw err if err
    console.log "Compiling", filename
    try
      res = parser.parse data
    catch e
      throw e unless e.name == "SyntaxError"
      error_handlers.SyntaxError filename, e
      return
    console.log res





# generate a new PEG parser
generate_parser = (parser_filename)->
  PEG.buildParser( fs.readFileSync(parser_filename, 'utf8') )


parser = generate_parser 'src/mustard.pegjs', trackLineAndColumn: true

for file in argv._
  compile_template parser, file, argv




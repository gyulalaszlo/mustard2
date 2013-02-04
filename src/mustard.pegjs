start
  = s:statement_list { return s; }

statement_list "statement list"
  = s:statement_with_separator* WS* { return s; }

statement_with_separator
  = s:statement SEP { return s; }


// A single statement
statement "statement"
  // yield has the highest priority.
  = yield_statement
  / assignment_statement
  / call_statement
  / string_statement
  ;


call_statement "call"
  //= name:ID contents:call_contents { return ['CALL', name, ['PARAMETERS'], contents]; }
  = name:ID parameters:call_parameters contents:call_contents { return {type: 'CALL', name:name, parameters:parameters, contents:contents}; }
  ;


call_parameters "call parameters"
  = f:call_parameter_single+ { var p={}; for(i=0; i < f.length; ++i) { var e = f[i]; p[e.name] = e.value; } return p; }
  / { return []; }
  ;

call_parameter_single
  = id:ID EQ s:string_statement { return {name:id, value:[s]}; }
  ;


call_contents "call contents block"
  = block:statement_block { return block; }
  // BRACE_OPEN statements:statement_list BRACE_CLOSE { return ['CONTENTS', statements]; }
  / string:string_statement { return [string]; }
  / { return []; }
  ;


// Assignment Statements
assignment_statement "assignment"
  = id:ID EQ value:assignment_value { return {type:'DEFINE', name:id, contents:value}; }
  ;

assignment_value "assignment value"
  = block:statement_block { return block; }
  / str:string_statement { return [str]; }
  ;




// String statements
//

string_statement "string"
  = s:STRING { return {type:'STRING', contents:s}; }
  / interpolation:interpolation_statement { return interpolation; }
  ;


yield_statement "yield"
  = YIELD { return {type:'YIELD'}; }
  ;


// Interpolation statement
interpolation_statement "interpolation"
  = v:VARIABLE_ID { return {type: 'VARIABLE', name: v}; }
  ;


// Common elements

statement_block "statement block"
  = BRACE_OPEN statements:statement_list BRACE_CLOSE { return statements; }
  ;

/* Tokens */


// Whitespace (ignored)
WS "whitespace" 
  = [ \t\n\r]+ { return; }
  / '//' [^\n\r]* { return; } 


SEP "Semicolon"
  = WS* ';'

BRACE_OPEN "opening brace"
  = WS* '{'

BRACE_CLOSE "closing brace"
  = WS* '}'

EQ "equal sign"
  = WS* '='

YIELD "yield statement"
  = WS* 'yield'


// An identified
ID "Identifier" 
  = WS*  id:ID_INTERNAL { return id; }

// An identified
VARIABLE_ID "variable identifier" 
  = WS* '@' id:ID_INTERNAL { return id; }

ID_INTERNAL
  = f:[a-zA-Z_] r:[a-zA-Z0-9\-_]+ { return f + r.join('') }
  / f:[a-zA-Z_] { return f; }

STRING = WS* "\"" str:[^"]* "\"" { return str.join(''); }



/*

additive
  = left:multiplicative "+" right:additive { return left + right; }
  / multiplicative

multiplicative
  = left:primary "*" right:multiplicative { return left * right; }
  / primary

primary
  = integer
  / "(" additive:additive ")" { return additive; }

integer "integer"
  = digits:[0-9]+ { return parseInt(digits.join(""), 10); }

*/

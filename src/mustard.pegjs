/*
 * Classic example grammar, which recognizes simple arithmetic expressions like
 * "2*(3+4)". The parser generated from this grammar then computes their value.
 */

start
  = s:statement_list WS* { return s; }

statement_list "statement list"
  = (s:statement SEP { return s; } )*


// A single statement
statement "statement"
  = call_statement
  / string_statement


call_statement "call"
  = name:ID params:call_parameters? { return ['CALL', name, params]; }


call_parameters "call parameters"
  = s:STRING { return ['CALL_PARAMETER', s]; }


string_statement "string"
  = s:STRING { return ['STRING', s]; }


/* Tokens */


// Whitespace (ignored)
WS "Whitespace" 
  = [ \t\n]+ { return; }


SEP "Semicolon"
  = WS* ';'

// An identified
ID "Identifier" 
  = WS*  id:ID_INTERNAL { return id; }

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

module.exports = grammar({

  name: "mql5",

  extras: $ => [
    /\s/,
    $.comment
  ],

  word: $ => $.identifier,

  conflicts: $ => [
    [$.preproc_define]
  ],

  precedences: $ => [
    [
      "unary",
      "multiplicative",
      "additive",
      "comparison",
      "logical",
      "assignment"
    ]
  ],

  rules: {

    source_file: $ => repeat(
      choice(
        $.preproc_include,
        $.preproc_define,
        $.class_definition,
        $.struct_definition,
        $.enum_definition,
        $.function_definition,
        $.variable_declaration
      )
    ),

    //----------------
    // PREPROCESSOR
    //----------------

    preproc_include: $ => seq(
      "#include",
      choice($.string_literal, $.system_lib_string)
    ),

    preproc_define: $ => choice(
      seq(
        '#define',
        $.identifier,
        $.expression
      ),
      seq(
        '#define',
        $.identifier
      )
    ),

    system_lib_string: $ => /<[^>]+>/,

    //----------------
    // CLASSES
    //----------------

    class_definition: $ => seq(
      "class",
      field("name", $.identifier),
      optional($.inheritance),
      "{",
      repeat(choice(
        $.function_definition,
        $.variable_declaration
      )),
      "}",
      optional(";")
    ),

    inheritance: $ => seq(":", $.identifier),

    //----------------
    // STRUCT
    //----------------

    struct_definition: $ => seq(
      "struct",
      $.identifier,
      "{",
      repeat($.variable_declaration),
      "}",
      optional(";")
    ),

    //----------------
    // ENUM
    //----------------

    enum_definition: $ => seq(
      "enum",
      $.identifier,
      "{",
      repeat(seq($.identifier, optional(","))),
      "}",
      optional(";")
    ),

    //----------------
    // FUNCTIONS
    //----------------

    function_definition: $ => seq(
      field("type", $.type),
      field("name", $.identifier),
      "(",
      optional($.parameter_list),
      ")",
      $.block
    ),

    parameter_list: $ => seq(
      $.parameter,
      repeat(seq(",", $.parameter))
    ),

    parameter: $ => seq(
      $.type,
      $.identifier
    ),

    //----------------
    // VARIABLES
    //----------------

    variable_declaration: $ => seq(
      optional(choice(
        "input",
        "extern",
        "static",
        "const"
      )),
      $.type,
      $.identifier,
      optional($.array),
      optional(seq("=", $.expression)),
      ";"
    ),

    array: $ => seq(
      "[",
      optional($.number_literal),
      "]"
    ),

    //----------------
    // TYPES
    //----------------

    type: $ => choice(

      "void",
      "int",
      "double",
      "float",
      "bool",
      "string",
      "datetime",
      "long",
      "short",
      "uchar",
      "uint",
      "ulong",
      "color",
      $.identifier
    ),

    //----------------
    // BLOCK
    //----------------

    block: $ => seq(
      "{",
      repeat(choice(
        $.variable_declaration,
        $.expression_statement,
        $.return_statement,
        $.if_statement,
        $.for_statement,
        $.while_statement
      )),
      "}"
    ),

    //----------------
    // STATEMENTS
    //----------------

    return_statement: $ => seq(
      "return",
      optional($.expression),
      ";"
    ),

    if_statement: $ => seq(
      "if",
      "(",
      $.expression,
      ")",
      $.block,
      optional(seq(
        "else",
        $.block
      ))
    ),

    for_statement: $ => seq(
      "for",
      "(",
      optional($.expression),
      ";",
      optional($.expression),
      ";",
      optional($.expression),
      ")",
      $.block
    ),

    while_statement: $ => seq(
      "while",
      "(",
      $.expression,
      ")",
      $.block
    ),

    expression_statement: $ => seq(
      $.expression,
      ";"
    ),

    //----------------
    // EXPRESSIONS
    //----------------

    expression: $ => choice(
      $.assignment_expression,
      $.binary_expression,
      $.unary_expression,
      $.function_call,
      $.member_expression,
      $.identifier,
      $.number_literal,
      $.string_literal
    ),

    assignment_expression: $ => prec.right("assignment", seq(
      $.identifier,
      "=",
      $.expression
    )),

    binary_expression: $ => choice(

      prec.left("multiplicative", seq(
        $.expression,
        choice("*", "/"),
        $.expression
      )),

      prec.left("additive", seq(
        $.expression,
        choice("+", "-"),
        $.expression
      )),

      prec.left("comparison", seq(
        $.expression,
        choice("==", "!=", "<", ">", "<=", ">="),
        $.expression
      )),

      prec.left("logical", seq(
        $.expression,
        choice("&&", "||"),
        $.expression
      ))
    ),

    unary_expression: $ => prec("unary", seq(
      choice("!", "-", "++", "--"),
      $.expression
    )),

    member_expression: $ => seq(
      $.identifier,
      ".",
      $.identifier
    ),

    function_call: $ => seq(
      $.identifier,
      "(",
      optional($.argument_list),
      ")"
    ),

    argument_list: $ => seq(
      $.expression,
      repeat(seq(",", $.expression))
    ),

    //----------------
    // TOKENS
    //----------------

    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    number_literal: $ => /\d+(\.\d+)?/,

    string_literal: $ => /"[^"]*"/,

    comment: $ => token(choice(
      seq("//", /.*/),
      seq(
        "/*",
        /[^*]*\*+([^/*][^*]*\*+)*/,
        "/"
      )
    ))

  }

})

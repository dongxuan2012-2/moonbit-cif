///|
/// UTF-8 byte half-open interval; 1-based scalar columns, tabs count as one.
pub(all) struct Span {
  start_line : Int
  start_col : Int
  end_line : Int
  end_col : Int
  start_offset : Int
  end_offset : Int
} derive(Debug, Eq, ToJson)

///|
pub(all) struct CifDiagnostic {
  code : String
  message : String
  span : Span
} derive(Debug, Eq, ToJson)

///|
pub(all) enum Version {
  Auto
  Cif1
  Cif2
} derive(Debug, Eq)

///|
pub(all) enum TokenKind {
  Word
  Quoted
  Triple
  Text
  OpenList
  CloseList
  OpenTable
  CloseTable
  Colon
  Trivia
  Comment
} derive(Debug, Eq)

///|
pub(all) struct Token {
  kind : TokenKind
  raw : String
  text : String
  span : Span
} derive(Debug, Eq)

///|
pub(all) enum Value {
  Scalar(Token)
  List(Array[Value], Span)
  Table(Array[(Token, Value)], Span)
} derive(Debug, Eq)

///|
pub(all) enum Entry {
  Pair(Token, Value)
  Loop(Array[Token], Array[Value], Span)
} derive(Debug, Eq)

///|
pub(all) struct Container {
  name : Token
  entries : Array[Entry]
  frames : Array[Container]
} derive(Debug, Eq)

///|
pub(all) struct CifFile {
  source : String
  tokens : Array[Token]
  blocks : Array[Container]
  version : Version
} derive(Debug, Eq)

///|
pub(all) struct ParseReport {
  file : CifFile
  diagnostics : Array[CifDiagnostic]
  raw_data : Array[Token]
} derive(Debug)

///|
pub fn ParseReport::is_valid(self : ParseReport) -> Bool {
  self.diagnostics.is_empty()
}

///|
pub fn Value::span(self : Value) -> Span {
  match self {
    Scalar(t) => t.span
    List(_, s) | Table(_, s) => s
  }
}

///|
/// Semantic JSON for consumers/oracles. Token kinds/raw lexemes remain in the AST.
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Scalar(t) => t.text.to_json()
    List(v, _) => v.map(Value::to_json).to_json()
    Table(v, _) => {
      let obj : Map[String, Json] = Map([])
      for pair in v {
        obj[pair.0.text] = pair.1.to_json()
      }
      obj.to_json()
    }
  }
}

///|
pub fn CifFile::rewrite_original(self : CifFile) -> String {
  self.source
}

///|
pub fn CifFile::find(self : CifFile, block : String, tag : String) -> Value? {
  for b in self.blocks {
    if name_key(b.name.text) == name_key("data_" + block) {
      for e in b.entries {
        if e is Pair(t, v) {
          if name_key(t.text) == name_key(tag) {
            return Some(v)
          }
        }
      }
    }
  }
  None
}

///|
fn joined_span(a : Span, b : Span) -> Span {
  {
    start_line: a.start_line,
    start_col: a.start_col,
    start_offset: a.start_offset,
    end_line: b.end_line,
    end_col: b.end_col,
    end_offset: b.end_offset,
  }
}

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A semantic symbol extracted from an AST node that overlaps the changed lines.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct AstSymbol {
    /// 1-based source line where this symbol starts
    pub line: usize,
    /// 1-based source line where this symbol ends
    pub end_line: usize,
    /// Coarse semantic category (e.g. "function_definition", "class_declaration")
    pub semantic_type: String,
    /// The symbol name (function name, class name, variable name …)
    pub name: String,
    /// Language of the source file
    pub language: String,
    /// Extra key/value metadata (visibility, is_async, is_test, …)
    pub metadata: HashMap<String, String>,
}

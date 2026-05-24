use std::collections::HashMap;
use std::path::Path;
use tree_sitter::{Node, Parser};

use crate::languages::SupportedLanguage;
use crate::models::AstSymbol;

// ---------------------------------------------------------------------------
// Public entry-point
// ---------------------------------------------------------------------------

/// Parse `file` with Tree-Sitter and return all named declaration nodes whose
/// source byte range overlaps any of the given `changed_lines` (1-based).
///
/// Returns an empty Vec on unsupported extensions, read errors, or parse errors.
pub fn analyze(file: &Path, changed_lines: &[usize]) -> Vec<AstSymbol> {
    // 1. Detect language
    let Some(lang) = SupportedLanguage::from_path(file) else {
        return vec![];
    };

    // 2. Read file bytes
    let Ok(source) = std::fs::read(file) else {
        eprintln!("diffuse-core: cannot read {:?}", file);
        return vec![];
    };

    // 3. Build parser
    let mut parser = Parser::new();
    if parser.set_language(&lang.tree_sitter_language()).is_err() {
        eprintln!("diffuse-core: failed to load grammar for {:?}", file);
        return vec![];
    }

    // 4. Parse
    let Some(tree) = parser.parse(&source, None) else {
        eprintln!("diffuse-core: parse failed for {:?}", file);
        return vec![];
    };

    // 5. Walk the tree collecting matching declarations
    let changed_set: std::collections::HashSet<usize> = changed_lines.iter().copied().collect();
    let mut symbols: Vec<AstSymbol> = Vec::new();
    walk_tree(tree.root_node(), &source, &changed_set, lang, &mut symbols);

    // 6. Deduplicate: keep only the innermost symbol per changed line
    deduplicate(symbols)
}

// ---------------------------------------------------------------------------
// Tree-walking
// ---------------------------------------------------------------------------

fn walk_tree(
    node: Node,
    source: &[u8],
    changed_lines: &std::collections::HashSet<usize>,
    lang: SupportedLanguage,
    out: &mut Vec<AstSymbol>,
) {
    let declaration_kinds = lang.declaration_node_kinds();

    // DFS — we recurse into children so we can find nested declarations.
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if declaration_kinds.contains(&child.kind()) {
            // 1-based lines
            let start_line = child.start_position().row + 1;
            let end_line = child.end_position().row + 1;

            // Does this node's line range overlap any changed line?
            let overlaps = changed_lines
                .iter()
                .any(|l| *l >= start_line && *l <= end_line);

            if overlaps {
                if let Some(sym) = build_symbol(child, source, lang, start_line, end_line) {
                    out.push(sym);
                }
            }

            // Always recurse to capture nested declarations (e.g. methods inside a class)
            walk_tree(child, source, changed_lines, lang, out);
        } else {
            walk_tree(child, source, changed_lines, lang, out);
        }
    }
}

// ---------------------------------------------------------------------------
// Symbol construction
// ---------------------------------------------------------------------------

fn build_symbol(
    node: Node,
    source: &[u8],
    lang: SupportedLanguage,
    start_line: usize,
    end_line: usize,
) -> Option<AstSymbol> {
    let semantic_type = map_semantic_type(node.kind(), lang);
    let name = extract_name(node, source).unwrap_or_else(|| "<anonymous>".into());
    let mut metadata = build_metadata(node, source, lang);

    // Security / auth tagging heuristics
    tag_security_metadata(&name, node, source, &mut metadata);

    Some(AstSymbol {
        line: start_line,
        end_line,
        semantic_type,
        name,
        language: lang.name().into(),
        metadata,
    })
}

/// Map Tree-Sitter node kind → coarse Diffuse semantic type string.
fn map_semantic_type(kind: &str, _lang: SupportedLanguage) -> String {
    match kind {
        // Functions & methods
        "function_declaration"
        | "function_item"
        | "function_definition"
        | "async_function_definition" => "function_definition",

        "method_definition"
        | "arrow_function"
        | "init_declaration"
        | "deinit_declaration"
        | "subscript_declaration" => "method_definition",

        // Classes & types
        "class_declaration" | "class_definition" => "class_declaration",
        "struct_declaration" | "struct_item" => "struct_declaration",
        "enum_declaration" | "enum_item" => "enum_declaration",
        "protocol_declaration" | "trait_item" => "protocol_declaration",
        "interface_declaration" => "interface_declaration",
        "type_alias_declaration" | "type_item" => "type_alias",
        "extension_declaration" | "impl_item" => "extension_declaration",
        "object_declaration" | "companion_object" => "object_declaration",
        "mod_item" => "module_declaration",

        // Properties / variables
        "property_declaration"
        | "computed_property"
        | "stored_property"
        | "const_item"
        | "static_item" => "property_declaration",

        "lexical_declaration" | "variable_declaration" => "variable_declaration",
        "secondary_constructor" => "constructor_declaration",
        "decorated_definition" => "decorated_definition",

        other => other,
    }
    .to_string()
}

/// Find the `name` or `identifier` child of a declaration node and return its text.
fn extract_name(node: Node, source: &[u8]) -> Option<String> {
    // Walk immediate children looking for a name / identifier node
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "identifier"
            | "type_identifier"
            | "property_identifier"
            | "simple_identifier"
            | "name" => {
                if let Ok(text) = child.utf8_text(source) {
                    return Some(text.to_string());
                }
            }
            _ => {}
        }
    }
    // Fallback: for arrow functions / anonymous: grab up to 32 chars of the node text
    if let Ok(text) = node.utf8_text(source) {
        let snippet: String = text.chars().take(48).collect();
        let snippet = snippet.trim().to_string();
        if !snippet.is_empty() {
            return Some(snippet);
        }
    }
    None
}

/// Build extra metadata fields from the AST.
fn build_metadata(node: Node, source: &[u8], lang: SupportedLanguage) -> HashMap<String, String> {
    let mut meta: HashMap<String, String> = HashMap::new();

    // Detect `async` / `override` / `public` / `private` / `open` modifiers
    let full_text = node.utf8_text(source).unwrap_or("");
    let first_100: &str = &full_text[..full_text.len().min(200)];

    // Modifiers — language-agnostic heuristics on the leading text
    if first_100.contains("async ") || first_100.contains("suspend ") {
        meta.insert("is_async".into(), "true".into());
    }
    if first_100.contains("override ") {
        meta.insert("is_override".into(), "true".into());
    }
    if first_100.contains("public ") || first_100.contains("open ") {
        meta.insert("visibility".into(), "public".into());
    } else if first_100.contains("private ") || first_100.contains("fileprivate ") {
        meta.insert("visibility".into(), "private".into());
    } else if first_100.contains("internal ") {
        meta.insert("visibility".into(), "internal".into());
    } else if first_100.contains("protected ") {
        meta.insert("visibility".into(), "protected".into());
    }

    // Test detection
    let is_test = match lang {
        SupportedLanguage::Swift => {
            full_text.contains("func test") || first_100.contains("@Test")
        }
        SupportedLanguage::Kotlin => {
            first_100.contains("@Test") || first_100.contains("fun test")
        }
        SupportedLanguage::TypeScript
        | SupportedLanguage::TSX
        | SupportedLanguage::JavaScript
        | SupportedLanguage::JSX => {
            full_text.starts_with("it(")
                || full_text.starts_with("test(")
                || full_text.starts_with("describe(")
        }
        SupportedLanguage::Python => {
            extract_name(node, source)
                .map(|n| n.starts_with("test_"))
                .unwrap_or(false)
        }
        SupportedLanguage::Rust => {
            // #[test] attribute on the parent or sibling — simplified check
            first_100.contains("#[test]") || first_100.contains("#[tokio::test]")
        }
    };
    if is_test {
        meta.insert("is_test".into(), "true".into());
    }

    // Line count (complexity proxy)
    let line_count = node.end_position().row - node.start_position().row + 1;
    meta.insert("line_count".into(), line_count.to_string());

    meta
}

/// Apply security / auth heuristic tagging based on name patterns.
fn tag_security_metadata(name: &str, _node: Node, _source: &[u8], meta: &mut HashMap<String, String>) {
    let lower = name.to_lowercase();

    let auth_keywords = [
        "auth", "authenticate", "authorize", "permission", "token", "session",
        "login", "logout", "sign_in", "sign_out", "credential", "password",
        "jwt", "oauth", "verify", "validate",
    ];
    let security_keywords = [
        "encrypt", "decrypt", "hash", "hmac", "secret", "key", "cert",
        "tls", "ssl", "signature", "sign", "checksum",
    ];
    let payment_keywords = [
        "payment", "checkout", "billing", "charge", "refund", "stripe",
        "subscription", "invoice", "purchase",
    ];
    let deletion_keywords = ["delete", "remove", "destroy", "purge", "wipe", "drop"];

    if auth_keywords.iter().any(|k| lower.contains(k)) {
        meta.insert("semantic_area".into(), "security_authentication".into());
        meta.insert("is_critical".into(), "true".into());
    } else if security_keywords.iter().any(|k| lower.contains(k)) {
        meta.insert("semantic_area".into(), "security_cryptography".into());
        meta.insert("is_critical".into(), "true".into());
    } else if payment_keywords.iter().any(|k| lower.contains(k)) {
        meta.insert("semantic_area".into(), "payment".into());
        meta.insert("is_critical".into(), "true".into());
    } else if deletion_keywords.iter().any(|k| lower.contains(k)) {
        meta.insert("semantic_area".into(), "data_deletion".into());
        meta.insert("is_critical".into(), "false".into());
    }
}

// ---------------------------------------------------------------------------
// Deduplication: remove exact duplicate (start_line, end_line) pairs that
// arise if the same node is visited more than once. We intentionally keep
// both an outer class and its inner method — they describe different scopes.
// ---------------------------------------------------------------------------

fn deduplicate(mut symbols: Vec<AstSymbol>) -> Vec<AstSymbol> {
    if symbols.len() <= 1 {
        return symbols;
    }

    // Sort by start_line, then by scope size ascending (innermost first)
    symbols.sort_by(|a, b| {
        a.line
            .cmp(&b.line)
            .then((a.end_line - a.line).cmp(&(b.end_line - b.line)))
    });

    // Only remove exact (start, end) duplicates
    let mut seen: std::collections::HashSet<(usize, usize)> = std::collections::HashSet::new();
    symbols.retain(|s| seen.insert((s.line, s.end_line)));

    symbols
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn write_tmp(content: &str, ext: &str) -> NamedTempFile {
        let mut f = tempfile::Builder::new()
            .suffix(&format!(".{ext}"))
            .tempfile()
            .unwrap();
        f.write_all(content.as_bytes()).unwrap();
        f
    }

    #[test]
    fn test_swift_function_extraction() {
        let src = r#"
import Foundation

struct MyService {
    func authenticate(user: String, password: String) -> Bool {
        return true
    }

    func fetchData() async -> [String] {
        return []
    }
}
"#;
        let f = write_tmp(src, "swift");
        // Line 5 is the start of `authenticate`
        let results = analyze(f.path(), &[5, 6, 7]);
        assert!(!results.is_empty(), "Expected at least one symbol");
        let auth = results.iter().find(|s| s.name.contains("authenticate"));
        assert!(auth.is_some(), "Expected authenticate symbol");
        let auth = auth.unwrap();
        assert_eq!(auth.semantic_type, "function_definition"); // swift uses function_declaration for methods too
        assert_eq!(auth.metadata.get("is_critical").map(|s| s.as_str()), Some("true"));
    }

    #[test]
    fn test_swift_no_match_outside_changed_lines() {
        let src = r#"
func foo() {}
func bar() {}
"#;
        let f = write_tmp(src, "swift");
        // Only line 3 changed (bar) — foo should NOT appear
        let results = analyze(f.path(), &[3]);
        assert!(results.iter().all(|s| s.name != "foo"));
    }

    #[test]
    fn test_unsupported_extension_returns_empty() {
        let f = write_tmp("SELECT 1;", "sql");
        let results = analyze(f.path(), &[1]);
        assert!(results.is_empty());
    }

    #[test]
    fn test_typescript_class_extraction() {
        let src = r#"
class AuthService {
    async login(username: string, password: string): Promise<void> {
        // authenticate
    }
}
"#;
        let f = write_tmp(src, "ts");
        let results = analyze(f.path(), &[3, 4]);
        assert!(!results.is_empty());
        // login or AuthService should be tagged as critical
        let critical = results.iter().any(|s| {
            s.metadata.get("is_critical").map(|v| v == "true").unwrap_or(false)
        });
        assert!(critical, "Expected a critical symbol from login/auth");
    }

    #[test]
    fn test_python_function_extraction() {
        let src = "def authenticate_user(username, password):\n    return True\n";
        let f = write_tmp(src, "py");
        let results = analyze(f.path(), &[1]);
        assert!(!results.is_empty());
        assert_eq!(results[0].semantic_type, "function_definition");
        assert_eq!(results[0].metadata.get("is_critical").map(|s| s.as_str()), Some("true"));
    }

    #[test]
    fn test_rust_function_extraction() {
        let src = "pub fn delete_account(user_id: u64) -> Result<(), Error> {\n    Ok(())\n}\n";
        let f = write_tmp(src, "rs");
        let results = analyze(f.path(), &[1, 2]);
        assert!(!results.is_empty());
        assert_eq!(results[0].semantic_type, "function_definition");
        assert_eq!(results[0].metadata.get("semantic_area").map(|s| s.as_str()), Some("data_deletion"));
    }
}

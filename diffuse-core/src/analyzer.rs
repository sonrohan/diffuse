use std::collections::HashMap;
use std::path::Path;
use tree_sitter::{Node, Parser};

use crate::languages::SupportedLanguage;
use crate::models::AstSymbol;

// ---------------------------------------------------------------------------
// Public entry-point: analyze a single file
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

    analyze_source(&source, lang, changed_lines)
}

/// Parse `file` and return all named declaration symbols.
pub fn analyze_all(file: &Path) -> Vec<AstSymbol> {
    let Some(lang) = SupportedLanguage::from_path(file) else {
        return vec![];
    };
    let Ok(source) = std::fs::read(file) else {
        eprintln!("diffuse-core: cannot read {:?}", file);
        return vec![];
    };
    analyze_source(&source, lang, &[])
}

/// Shared inner implementation used by both `analyze` and `compare_files`.
fn analyze_source(source: &[u8], lang: SupportedLanguage, changed_lines: &[usize]) -> Vec<AstSymbol> {
    // Build parser
    let mut parser = Parser::new();
    if parser.set_language(&lang.tree_sitter_language()).is_err() {
        return vec![];
    }

    // Parse
    let Some(tree) = parser.parse(source, None) else {
        return vec![];
    };

    // Walk the tree collecting matching declarations
    let changed_set: std::collections::HashSet<usize> = changed_lines.iter().copied().collect();
    let mut symbols: Vec<AstSymbol> = Vec::new();
    walk_tree(tree.root_node(), source, &changed_set, lang, &mut symbols);

    // Deduplicate: keep only the innermost symbol per changed line
    deduplicate(symbols)
}

// ---------------------------------------------------------------------------
// Public entry-point: compare base and head versions of a file (Step 4)
// ---------------------------------------------------------------------------

/// Compare two versions of the same file and return symbols from `head` that
/// have contract-level changes relative to `base` (signature, visibility).
///
/// `changed_lines` are the 1-based new-side lines from the diff for this file.
pub fn compare_files(base: &Path, head: &Path, changed_lines: &[usize]) -> Vec<AstSymbol> {
    let Some(lang) = SupportedLanguage::from_path(head) else {
        return vec![];
    };

    let Ok(base_source) = std::fs::read(base) else {
        eprintln!("diffuse-core: cannot read base {:?}", base);
        return vec![];
    };
    let Ok(head_source) = std::fs::read(head) else {
        eprintln!("diffuse-core: cannot read head {:?}", head);
        return vec![];
    };

    // Parse both with all lines (we compare the whole symbol surface)
    let all_lines_base: Vec<usize> = (1..=base_source.iter().filter(|&&b| b == b'\n').count() + 1).collect();
    let base_syms = analyze_source(&base_source, lang, &all_lines_base);
    let head_syms = analyze_source(&head_source, lang, changed_lines);

    // Build lookup: stable key → base symbol
    let base_map: HashMap<String, &AstSymbol> = base_syms
        .iter()
        .map(|s| (stable_key(s), s))
        .collect();

    // For each head symbol in the changed lines, compute contract delta
    head_syms
        .into_iter()
        .map(|mut head_sym| {
            let key = stable_key(&head_sym);
            if let Some(base_sym) = base_map.get(&key) {
                let is_surface = is_contract_surface(base_sym) || is_contract_surface(&head_sym);
                let base_sig = signature_fingerprint(base_sym);
                let head_sig = signature_fingerprint(&head_sym);
                if is_surface && base_sig != head_sig {
                    head_sym.metadata.insert("contract_signature_changed".into(), "true".into());
                }

                if is_surface {
                    compare_field_delta(
                        base_sym,
                        &mut head_sym,
                        "return_type",
                        "contract_return_type_changed",
                        "contract_old_return_type",
                        "contract_new_return_type",
                    );
                }

                // Compare visibility — materialize owned Strings before mutable borrow
                let base_vis: String = base_sym
                    .metadata
                    .get("visibility")
                    .cloned()
                    .unwrap_or_else(|| "internal".into());
                let head_vis: String = head_sym
                    .metadata
                    .get("visibility")
                    .cloned()
                    .unwrap_or_else(|| "internal".into());
                if base_vis != head_vis {
                    let is_new_public = head_vis == "public" || head_vis == "open";
                    head_sym.metadata.insert("contract_visibility_changed".into(), "true".into());
                    head_sym.metadata.insert("contract_old_visibility".into(), base_vis);
                    head_sym.metadata.insert("contract_new_visibility".into(), head_vis);
                    if is_new_public {
                        head_sym.metadata.insert("contract_is_new_public".into(), "true".into());
                    }
                }

                tag_behavioral_delta(base_sym, &mut head_sym);
            } else {
                // Symbol is new in head — if it is public, flag it
                let vis = head_sym.metadata.get("visibility").map(|s| s.as_str()).unwrap_or("internal");
                if vis == "public" || vis == "open" {
                    head_sym.metadata.insert("contract_is_new_public".into(), "true".into());
                }
                tag_new_symbol_behavior(&mut head_sym);
            }
            head_sym
        })
        .filter(|s| {
            // Only return symbols that have some contract delta
            s.metadata.keys().any(|k| k.starts_with("contract_") || k.ends_with("_added"))
        })
        .collect()
}

/// Build a stable identifier for a symbol that survives formatting changes.
/// Includes enclosing type/module metadata when available to avoid collisions
/// between common names such as `init`, `body`, `render`, or `testFoo`.
fn stable_key(sym: &AstSymbol) -> String {
    sym.metadata
        .get("symbol_key")
        .cloned()
        .unwrap_or_else(|| symbol_key(
            sym.metadata.get("scope").map(|s| s.as_str()).unwrap_or(""),
            &sym.semantic_type,
            &sym.name,
        ))
}

/// Extract a compact signature fingerprint from symbol metadata. This is
/// intentionally declaration-only; body text changes must not become contract
/// changes.
fn signature_fingerprint(sym: &AstSymbol) -> String {
    let async_flag = sym.metadata.get("is_async").map(|s| s.as_str()).unwrap_or("false");
    let throws_flag = sym.metadata.get("throws").map(|s| s.as_str()).unwrap_or("false");
    let vis = sym.metadata.get("visibility").map(|s| s.as_str()).unwrap_or("internal");
    let param_hash = sym.metadata.get("param_hash").map(|s| s.as_str()).unwrap_or("");
    let return_type = sym.metadata.get("return_type").map(|s| s.as_str()).unwrap_or("");
    format!(
        "{}::{}::async={}::throws={}::vis={}::params={}::returns={}",
        sym.semantic_type, sym.name, async_flag, throws_flag, vis, param_hash, return_type
    )
}

fn is_contract_surface(sym: &AstSymbol) -> bool {
    match sym.metadata.get("visibility").map(|s| s.as_str()) {
        Some("public") | Some("open") => true,
        Some("private") | Some("fileprivate") | Some("internal") | Some("protected") => false,
        _ => matches!(
            sym.language.as_str(),
            "typescript" | "javascript" | "python"
        ) || matches!(
            sym.semantic_type.as_str(),
            "interface_declaration" | "protocol_declaration" | "type_alias"
        ),
    }
}

fn compare_field_delta(
    base_sym: &AstSymbol,
    head_sym: &mut AstSymbol,
    field: &str,
    changed_key: &str,
    old_key: &str,
    new_key: &str,
) {
    let base_value = base_sym.metadata.get(field).cloned().unwrap_or_default();
    let head_value = head_sym.metadata.get(field).cloned().unwrap_or_default();
    if base_value != head_value {
        head_sym.metadata.insert(changed_key.into(), "true".into());
        head_sym.metadata.insert(old_key.into(), base_value);
        head_sym.metadata.insert(new_key.into(), head_value);
    }
}

fn tag_behavioral_delta(base_sym: &AstSymbol, head_sym: &mut AstSymbol) {
    for (presence_key, delta_key) in [
        ("has_control_flow", "control_flow_added"),
        ("has_error_handling", "error_handling_added"),
        ("has_async_behavior", "async_behavior_added"),
        ("has_persistence_write", "persistence_write_added"),
        ("has_network_call", "network_call_added"),
        ("has_auth_check", "auth_check_added"),
        ("has_deletion", "deletion_added"),
        ("has_logging", "logging_added"),
    ] {
        let had = base_sym.metadata.get(presence_key).map(|v| v == "true").unwrap_or(false);
        let has = head_sym.metadata.get(presence_key).map(|v| v == "true").unwrap_or(false);
        if has && !had {
            head_sym.metadata.insert(delta_key.into(), "true".into());
        }
    }
}

fn tag_new_symbol_behavior(head_sym: &mut AstSymbol) {
    for (presence_key, delta_key) in [
        ("has_control_flow", "control_flow_added"),
        ("has_error_handling", "error_handling_added"),
        ("has_async_behavior", "async_behavior_added"),
        ("has_persistence_write", "persistence_write_added"),
        ("has_network_call", "network_call_added"),
        ("has_auth_check", "auth_check_added"),
        ("has_deletion", "deletion_added"),
        ("has_logging", "logging_added"),
    ] {
        if head_sym.metadata.get(presence_key).map(|v| v == "true").unwrap_or(false) {
            head_sym.metadata.insert(delta_key.into(), "true".into());
        }
    }
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
            let overlaps = changed_lines.is_empty()
                || changed_lines.iter().any(|l| *l >= start_line && *l <= end_line);

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
    if let Some(scope) = enclosing_scope(node, source) {
        metadata.insert("scope".into(), scope);
    }

    // Security / auth tagging heuristics
    tag_security_metadata(&name, node, source, &mut metadata);

    // Behavioral body presence. These are not reported as changes unless
    // compare_files observes that the behavior is newly introduced.
    tag_behavioral_metadata(node, source, &mut metadata);

    // Direct callee extraction (Step 6)
    let callees = extract_callees(node, source, lang);
    if !callees.is_empty() {
        metadata.insert("callees".into(), callees.join(","));
    }

    // Parameter hash for contract comparison (Step 4)
    let param_hash = extract_param_hash(node, source, lang);
    if !param_hash.is_empty() {
        metadata.insert("param_hash".into(), param_hash);
    }
    if let Some(return_type) = extract_return_type(node, source) {
        metadata.insert("return_type".into(), return_type);
    }

    let scope = metadata.get("scope").cloned().unwrap_or_default();
    metadata.insert("qualified_name".into(), qualified_name(&scope, &name));
    metadata.insert("symbol_key".into(), symbol_key(&scope, &semantic_type, &name));

    let imports = extract_imports(source, lang);
    if !imports.is_empty() {
        metadata.insert("imports".into(), imports.join(","));
    }

    // throws / rethrows detection for contract comparison
    if let Ok(text) = node.utf8_text(source) {
        let first = &text[..text.len().min(300)];
        if first.contains("throws") || first.contains("rethrows") || first.contains("raise") {
            metadata.insert("throws".into(), "true".into());
        }
    }

    Some(AstSymbol {
        line: start_line,
        end_line,
        semantic_type,
        name,
        language: lang.name().into(),
        metadata,
    })
}

fn qualified_name(scope: &str, name: &str) -> String {
    if scope.is_empty() {
        name.to_string()
    } else {
        format!("{scope}.{name}")
    }
}

fn symbol_key(scope: &str, semantic_type: &str, name: &str) -> String {
    format!("{scope}::{semantic_type}::{name}")
}

fn enclosing_scope(node: Node, source: &[u8]) -> Option<String> {
    let mut parts: Vec<String> = Vec::new();
    let mut parent = node.parent();
    while let Some(p) = parent {
        match p.kind() {
            "class_declaration"
            | "class_definition"
            | "struct_declaration"
            | "struct_item"
            | "enum_declaration"
            | "enum_item"
            | "protocol_declaration"
            | "trait_item"
            | "interface_declaration"
            | "extension_declaration"
            | "impl_item"
            | "object_declaration"
            | "mod_item" => {
                if let Some(name) = extract_name(p, source) {
                    parts.push(name);
                }
            }
            _ => {}
        }
        parent = p.parent();
    }
    if parts.is_empty() {
        None
    } else {
        parts.reverse();
        Some(parts.join("."))
    }
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
    // Fallback: for arrow functions / anonymous: grab up to 48 chars of the node text
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
    let first_200: &str = &full_text[..full_text.len().min(200)];

    // Modifiers — language-agnostic heuristics on the leading text
    if first_200.contains("async ") || first_200.contains("suspend ") {
        meta.insert("is_async".into(), "true".into());
    }
    if first_200.contains("override ") {
        meta.insert("is_override".into(), "true".into());
    }
    if first_200.contains("public ") || first_200.contains("open ") {
        meta.insert("visibility".into(), "public".into());
    } else if first_200.contains("private ") || first_200.contains("fileprivate ") {
        meta.insert("visibility".into(), "private".into());
    } else if first_200.contains("internal ") {
        meta.insert("visibility".into(), "internal".into());
    } else if first_200.contains("protected ") {
        meta.insert("visibility".into(), "protected".into());
    }

    // Test detection
    let is_test = match lang {
        SupportedLanguage::Swift => {
            full_text.contains("func test") || first_200.contains("@Test")
        }
        SupportedLanguage::Kotlin => {
            first_200.contains("@Test") || first_200.contains("fun test")
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
            first_200.contains("#[test]") || first_200.contains("#[tokio::test]")
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
// Step 5: Behavioral diff metadata
// Scans the symbol body text for patterns indicating kinds of behavior change.
// ---------------------------------------------------------------------------

fn tag_behavioral_metadata(node: Node, source: &[u8], meta: &mut HashMap<String, String>) {
    let body_text = node.utf8_text(source).unwrap_or("").to_lowercase();

    // Control flow: if/guard/switch/when/match/for/while
    if contains_any(&body_text, &["if ", "guard ", "switch ", " when ", " match ", "for ", "while "]) {
        meta.insert("has_control_flow".into(), "true".into());
    }

    // Error handling: throws/try/catch/Result/Error
    if contains_any(&body_text, &["throws", " try ", " catch ", "result<", "error>", "?."])  {
        meta.insert("has_error_handling".into(), "true".into());
    }

    // Async / concurrency
    if contains_any(&body_text, &["await ", "async ", " async{", "completionhandler", "dispatchqueue", "coroutinescope"]) {
        meta.insert("has_async_behavior".into(), "true".into());
    }

    // Persistence writes
    if contains_any(&body_text, &[
        ".save(", ".insert(", ".update(", ".write(", ".persist(",
        ".commit(", "managedcontext", "realm.write", "userdefaults",
        "context.save", "coredatastack",
    ]) {
        meta.insert("has_persistence_write".into(), "true".into());
    }

    // Network calls
    if contains_any(&body_text, &[
        "urlsession", "fetch(", "http", ".get(", ".post(", ".put(", ".delete(",
        "request(", "axios", "alamofire", "okhttp", "retrofit",
        "nsurlsession", "datatask", "uploadtask",
    ]) {
        meta.insert("has_network_call".into(), "true".into());
    }

    // Authorization checks
    if contains_any(&body_text, &[
        "authorize(", "checkpermission", "requiresauth", "isauthenticated",
        "hasrole(", "canaccess(", "guardauth", "accesscontrol",
    ]) {
        meta.insert("has_auth_check".into(), "true".into());
    }

    // Deletion / destructive operations
    if contains_any(&body_text, &[
        "delete(", ".remove(", "destroy(", "purge(", "wipe(", "drop(",
        "deletefrom", "truncate", "harddelete",
    ]) {
        meta.insert("has_deletion".into(), "true".into());
    }

    // Logging / metrics / audit
    if contains_any(&body_text, &[
        "log(", "logger.", "print(", "nspredicate", "analytics.",
        "metrics.", "telemetry.", "audit.", "nslog(", "debugprint",
        "firebase.log", "crashlytics",
    ]) {
        meta.insert("has_logging".into(), "true".into());
    }
}

/// Returns true if `text` contains any of the given patterns.
fn contains_any(text: &str, patterns: &[&str]) -> bool {
    patterns.iter().any(|p| text.contains(p))
}

// ---------------------------------------------------------------------------
// Step 6: Direct callee extraction
// Walks the symbol body for call expressions and collects callee names.
// ---------------------------------------------------------------------------

fn extract_callees(node: Node, source: &[u8], lang: SupportedLanguage) -> Vec<String> {
    let call_kinds = call_expression_kinds(lang);
    let mut callees: Vec<String> = Vec::new();
    collect_calls(node, source, &call_kinds, &mut callees);

    // Deduplicate while preserving order
    let mut seen = std::collections::HashSet::new();
    callees.retain(|c| seen.insert(c.clone()));

    // Cap at 20 callees to keep JSON compact
    callees.truncate(20);
    callees
}

/// Language-specific node kinds that represent a function/method call.
fn call_expression_kinds(lang: SupportedLanguage) -> &'static [&'static str] {
    match lang {
        SupportedLanguage::Swift => &[
            "call_expression",
            "function_call_expression",
        ],
        SupportedLanguage::Kotlin => &[
            "call_expression",
            "function_call_expression",
        ],
        SupportedLanguage::TypeScript
        | SupportedLanguage::TSX
        | SupportedLanguage::JavaScript
        | SupportedLanguage::JSX => &[
            "call_expression",
            "new_expression",
        ],
        SupportedLanguage::Python => &[
            "call",
        ],
        SupportedLanguage::Rust => &[
            "call_expression",
            "macro_invocation",
            "method_call_expression",
        ],
    }
}

fn collect_calls(node: Node, source: &[u8], call_kinds: &[&str], out: &mut Vec<String>) {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        if call_kinds.contains(&child.kind()) {
            // Try to get the callee name from the function/identifier child
            if let Some(name) = callee_name(child, source) {
                if !name.is_empty() && name != "<anonymous>" {
                    out.push(name);
                }
            }
        }
        // Recurse into all children
        collect_calls(child, source, call_kinds, out);
    }
}

/// Extract the callee name from a call_expression node.
fn callee_name(node: Node, source: &[u8]) -> Option<String> {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            // Swift / Kotlin: direct identifier
            "identifier" | "simple_identifier" => {
                if let Ok(text) = child.utf8_text(source) {
                    return Some(text.to_string());
                }
            }
            // TS/JS: call_expression → identifier or member_expression
            "member_expression" | "field_expression" => {
                // Get the property/method name (right side of the dot)
                let mut mc = child.walk();
                for mc_child in child.children(&mut mc) {
                    if mc_child.kind() == "property_identifier"
                        || mc_child.kind() == "identifier"
                        || mc_child.kind() == "field_identifier"
                    {
                        if let Ok(text) = mc_child.utf8_text(source) {
                            return Some(text.to_string());
                        }
                    }
                }
            }
            // Python: call → identifier or attribute
            "attribute" => {
                let mut ac = child.walk();
                for ac_child in child.children(&mut ac) {
                    if ac_child.kind() == "identifier" {
                        if let Ok(text) = ac_child.utf8_text(source) {
                            return Some(text.to_string());
                        }
                    }
                }
            }
            // Rust macro_invocation: the macro path (scoped only — identifier already matched above)
            "scoped_identifier" => {
                if let Ok(text) = child.utf8_text(source) {
                    return Some(text.to_string());
                }
            }
            _ => {}
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Step 4: Parameter hash extraction (signature fingerprint support)
// ---------------------------------------------------------------------------

/// Extract a compact hash of the parameter list to detect signature changes.
/// Returns an empty string if the grammar does not expose a parameter node;
/// body text is intentionally never used as a fallback.
fn extract_param_hash(node: Node, source: &[u8], _lang: SupportedLanguage) -> String {
    // First try to find a structured parameter node
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "parameter_clause"
            | "parameters"
            | "formal_parameters"
            | "function_value_parameters"
            | "parameter_list" => {
                if let Ok(text) = child.utf8_text(source) {
                    let hash: u32 = text.bytes().fold(0u32, |acc, b| acc.wrapping_add(b as u32));
                    return format!("{hash:04x}");
                }
            }
            _ => {}
        }
    }
    if let Ok(text) = node.utf8_text(source) {
        let header = text.split('{').next().unwrap_or(text).trim();
        if !header.is_empty() && header.len() < text.len() {
            let hash: u32 = header.bytes().fold(0u32, |acc, b| acc.wrapping_mul(31).wrapping_add(b as u32));
            return format!("{hash:08x}");
        }
    }
    String::new()
}

fn extract_return_type(node: Node, source: &[u8]) -> Option<String> {
    let mut cursor = node.walk();
    for child in node.children(&mut cursor) {
        match child.kind() {
            "return_type"
            | "type"
            | "type_identifier"
            | "user_type"
            | "function_type"
            | "generic_type" => {
                if let Ok(text) = child.utf8_text(source) {
                    let trimmed = text.trim();
                    if !trimmed.is_empty() {
                        return Some(trimmed.to_string());
                    }
                }
            }
            _ => {}
        }
    }
    if let Ok(text) = node.utf8_text(source) {
        let header = text.split('{').next().unwrap_or(text).trim();
        if let Some(idx) = header.rfind("->") {
            let ret = header[idx + 2..].trim();
            if !ret.is_empty() {
                return Some(ret.to_string());
            }
        }
    }
    None
}

fn extract_imports(source: &[u8], lang: SupportedLanguage) -> Vec<String> {
    let Ok(text) = std::str::from_utf8(source) else { return vec![] };
    let mut imports = Vec::new();
    for line in text.lines().map(str::trim) {
        let candidate = match lang {
            SupportedLanguage::Swift if line.starts_with("import ") => Some(line.trim_start_matches("import ").trim()),
            SupportedLanguage::Kotlin if line.starts_with("import ") => Some(line.trim_start_matches("import ").trim()),
            SupportedLanguage::Python if line.starts_with("import ") => Some(line.trim_start_matches("import ").trim()),
            SupportedLanguage::Python if line.starts_with("from ") => Some(line.trim_start_matches("from ").split_whitespace().next().unwrap_or("")),
            SupportedLanguage::Rust if line.starts_with("use ") => Some(line.trim_start_matches("use ").trim_end_matches(';').trim()),
            SupportedLanguage::TypeScript
            | SupportedLanguage::TSX
            | SupportedLanguage::JavaScript
            | SupportedLanguage::JSX if line.starts_with("import ") => {
                line.split(" from ")
                    .nth(1)
                    .map(|s| s.trim().trim_matches(';').trim_matches('"').trim_matches('\''))
            }
            _ => None,
        };
        if let Some(value) = candidate {
            if !value.is_empty() {
                imports.push(value.to_string());
            }
        }
    }
    imports.sort();
    imports.dedup();
    imports
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

    #[test]
    fn test_behavioral_metadata_network_call() {
        let src = "func fetchUser(id: Int) async -> User? {\n    let data = await URLSession.shared.data(from: url)\n    return data\n}\n";
        let f = write_tmp(src, "swift");
        let results = analyze(f.path(), &[1, 2, 3]);
        assert!(!results.is_empty());
        let sym = &results[0];
        assert_eq!(sym.metadata.get("has_network_call").map(|s| s.as_str()), Some("true"), "Expected network call metadata");
        assert_eq!(sym.metadata.get("has_async_behavior").map(|s| s.as_str()), Some("true"), "Expected async behavior metadata");
    }

    #[test]
    fn test_behavioral_metadata_persistence_write() {
        let src = "func saveUser(user: User) {\n    context.save()\n}\n";
        let f = write_tmp(src, "swift");
        let results = analyze(f.path(), &[1, 2]);
        assert!(!results.is_empty());
        assert_eq!(
            results[0].metadata.get("has_persistence_write").map(|s| s.as_str()),
            Some("true"),
            "Expected persistence write metadata"
        );
    }

    #[test]
    fn test_callee_extraction_rust() {
        let src = "pub fn process(x: i32) -> i32 {\n    let a = validate(x);\n    let b = transform(a);\n    persist(b)\n}\n";
        let f = write_tmp(src, "rs");
        let results = analyze(f.path(), &[1, 2, 3, 4]);
        assert!(!results.is_empty());
        let callees = results[0].metadata.get("callees").unwrap_or(&String::new()).clone();
        assert!(!callees.is_empty(), "Expected callees to be populated");
    }

    #[test]
    fn test_symbol_identity_metadata_includes_scope() {
        let src = "struct AuthService {\n    public func login(user: String) -> Bool {\n        true\n    }\n}\n";
        let f = write_tmp(src, "swift");
        let results = analyze(f.path(), &[2, 3]);
        let login = results.iter().find(|s| s.name == "login").expect("login symbol");
        assert_eq!(
            login.metadata.get("qualified_name").map(|s| s.as_str()),
            Some("AuthService.login")
        );
        assert_eq!(
            login.metadata.get("symbol_key").map(|s| s.as_str()),
            Some("AuthService::function_definition::login")
        );
    }

    #[test]
    fn test_compare_files_signature_change() {
        let base_src = "public func greet(name: String) -> String {\n    return \"Hello \\(name)\"\n}\n";
        let head_src = "public func greet(name: String, greeting: String) -> String {\n    return \"\\(greeting) \\(name)\"\n}\n";
        let base_f = write_tmp(base_src, "swift");
        let head_f = write_tmp(head_src, "swift");
        let results = compare_files(base_f.path(), head_f.path(), &[1, 2, 3]);
        // greet changed signature — should be flagged
        let flagged = results.iter().any(|s| {
            s.metadata.get("contract_signature_changed").map(|v| v == "true").unwrap_or(false)
        });
        assert!(flagged, "Expected contract_signature_changed for greet");
    }

    #[test]
    fn test_compare_files_signature_change_after_line_shift() {
        let base_src = "public func greet(name: String) -> String {\n    return \"Hello \\(name)\"\n}\n";
        let head_src = "\npublic func greet(name: String, greeting: String) -> String {\n    return \"\\(greeting) \\(name)\"\n}\n";
        let base_f = write_tmp(base_src, "swift");
        let head_f = write_tmp(head_src, "swift");
        let results = compare_files(base_f.path(), head_f.path(), &[2, 3, 4]);
        let flagged = results.iter().any(|s| {
            s.name == "greet"
                && s.line == 2
                && s.metadata.get("contract_signature_changed").map(|v| v == "true").unwrap_or(false)
        });
        assert!(flagged, "Expected symbol-key matching to survive line movement");
    }

    #[test]
    fn test_compare_files_new_public_symbol() {
        let base_src = "func helper() {}\n";
        let head_src = "func helper() {}\npublic func newApi() -> Int { 42 }\n";
        let base_f = write_tmp(base_src, "swift");
        let head_f = write_tmp(head_src, "swift");
        let results = compare_files(base_f.path(), head_f.path(), &[2]);
        let flagged = results.iter().any(|s| {
            s.metadata.get("contract_is_new_public").map(|v| v == "true").unwrap_or(false)
        });
        assert!(flagged, "Expected contract_is_new_public for newApi");
    }
}

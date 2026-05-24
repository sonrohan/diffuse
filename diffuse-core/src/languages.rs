use tree_sitter::Language;
use tree_sitter_kotlin_ng as tree_sitter_kotlin;

/// All languages the sidecar can parse.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SupportedLanguage {
    Swift,
    Kotlin,
    TypeScript,
    TSX,
    JavaScript,
    JSX,
    Python,
    Rust,
}

impl SupportedLanguage {
    /// Detect the language from a file path extension.
    pub fn from_path(path: &std::path::Path) -> Option<Self> {
        let ext = path.extension()?.to_str()?.to_lowercase();
        let filename = path.file_name()?.to_str()?.to_lowercase();

        // Skip TypeScript declaration files
        if filename.ends_with(".d.ts") {
            return None;
        }

        match ext.as_str() {
            "swift" => Some(Self::Swift),
            "kt" | "kts" => Some(Self::Kotlin),
            "ts" => Some(Self::TypeScript),
            "tsx" => Some(Self::TSX),
            "js" | "mjs" | "cjs" => Some(Self::JavaScript),
            "jsx" => Some(Self::JSX),
            "py" => Some(Self::Python),
            "rs" => Some(Self::Rust),
            _ => None,
        }
    }

    /// Human-readable name for JSON output.
    pub fn name(self) -> &'static str {
        match self {
            Self::Swift => "swift",
            Self::Kotlin => "kotlin",
            Self::TypeScript | Self::TSX => "typescript",
            Self::JavaScript | Self::JSX => "javascript",
            Self::Python => "python",
            Self::Rust => "rust",
        }
    }

    /// Return the tree-sitter [`Language`] for this variant.
    ///
    /// All grammar crates at v0.23+ expose a `LANGUAGE: LanguageFn` constant which
    /// converts into `tree_sitter::Language` via the `Into` trait (available since tree-sitter 0.23).
    pub fn tree_sitter_language(self) -> Language {
        match self {
            Self::Swift => tree_sitter_swift::LANGUAGE.into(),
            Self::Kotlin => tree_sitter_kotlin::LANGUAGE.into(),
            Self::TypeScript | Self::TSX => tree_sitter_typescript::LANGUAGE_TYPESCRIPT.into(),
            Self::JavaScript | Self::JSX => tree_sitter_javascript::LANGUAGE.into(),
            Self::Python => tree_sitter_python::LANGUAGE.into(),
            Self::Rust => tree_sitter_rust::LANGUAGE.into(),
        }
    }

    /// Top-level node kinds that represent named declarations for this language.
    /// These are what we walk over to find symbols that intersect changed lines.
    pub fn declaration_node_kinds(self) -> &'static [&'static str] {
        match self {
            Self::Swift => &[
                "function_declaration",
                "init_declaration",
                "deinit_declaration",
                "subscript_declaration",
                "class_declaration",
                "struct_declaration",
                "enum_declaration",
                "protocol_declaration",
                "extension_declaration",
                "computed_property",
                "stored_property",
            ],
            Self::Kotlin => &[
                "function_declaration",
                "class_declaration",
                "object_declaration",
                "companion_object",
                "property_declaration",
                "secondary_constructor",
            ],
            Self::TypeScript | Self::TSX => &[
                "function_declaration",
                "arrow_function",
                "method_definition",
                "class_declaration",
                "interface_declaration",
                "type_alias_declaration",
                "enum_declaration",
                "lexical_declaration",
            ],
            Self::JavaScript | Self::JSX => &[
                "function_declaration",
                "arrow_function",
                "method_definition",
                "class_declaration",
                "lexical_declaration",
                "variable_declaration",
            ],
            Self::Python => &[
                "function_definition",
                "async_function_definition",
                "class_definition",
                "decorated_definition",
            ],
            Self::Rust => &[
                "function_item",
                "impl_item",
                "struct_item",
                "enum_item",
                "trait_item",
                "type_item",
                "const_item",
                "static_item",
                "mod_item",
            ],
        }
    }
}

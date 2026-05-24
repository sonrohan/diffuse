mod analyzer;
mod languages;
mod models;

use clap::{Parser, Subcommand};
use std::path::PathBuf;

/// diffuse-core — AST analysis sidecar for the Diffuse macOS app.
/// Parses source files using Tree-Sitter and returns semantic symbol
/// information as JSON for the changed line ranges provided.
#[derive(Parser)]
#[command(author, version, about)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Analyze a file's AST and extract symbols intersecting the given changed lines.
    Analyze {
        /// Path to the source file to analyze
        #[arg(short, long)]
        file: PathBuf,

        /// Comma-separated list of 1-based line numbers that were changed
        #[arg(short, long, value_delimiter = ',')]
        lines: Vec<usize>,
    },

    /// Analyze every declaration in a source file.
    Index {
        /// Path to the source file to index
        #[arg(short, long)]
        file: PathBuf,
    },

    /// Compare base and head versions of a file and return symbols with contract-level changes.
    ///
    /// Emits symbols from head that have `contract_signature_changed`,
    /// `contract_visibility_changed`, or `contract_is_new_public` metadata set.
    Compare {
        /// Path to the base (old) version of the file
        #[arg(long)]
        base: PathBuf,

        /// Path to the head (new) version of the file
        #[arg(long)]
        head: PathBuf,

        /// Comma-separated list of 1-based line numbers that were changed in the head file
        #[arg(short, long, value_delimiter = ',')]
        lines: Vec<usize>,
    },
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Analyze { file, lines } => {
            let results = analyzer::analyze(&file, &lines);
            match serde_json::to_string_pretty(&results) {
                Ok(json) => println!("{json}"),
                Err(e) => {
                    eprintln!("diffuse-core: serialization error: {e}");
                    std::process::exit(1);
                }
            }
        }

        Commands::Index { file } => {
            let results = analyzer::analyze_all(&file);
            match serde_json::to_string_pretty(&results) {
                Ok(json) => println!("{json}"),
                Err(e) => {
                    eprintln!("diffuse-core: serialization error: {e}");
                    std::process::exit(1);
                }
            }
        }

        Commands::Compare { base, head, lines } => {
            let results = analyzer::compare_files(&base, &head, &lines);
            match serde_json::to_string_pretty(&results) {
                Ok(json) => println!("{json}"),
                Err(e) => {
                    eprintln!("diffuse-core: serialization error: {e}");
                    std::process::exit(1);
                }
            }
        }
    }
}

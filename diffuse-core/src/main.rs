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
    }
}

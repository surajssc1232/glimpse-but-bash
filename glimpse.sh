#!/bin/bash

# workspace_copy.sh - A script to copy workspace content for LLMs
# Features:
# - Detects clipboard system (Wayland/X11) automatically
# - Uses tree for directory structure visualization
# - Uses bat for code display
# - Copies all subdirectories and their content

set -e  # Exit on error

# Function to check if a command exists
command_exists() {
  command -v "$1" &> /dev/null
}

# Check for required tools
required_tools=("tree" "find" "file")
missing_tools=()

for tool in "${required_tools[@]}"; do
  if ! command_exists "$tool"; then
    missing_tools+=("$tool")
  fi
done

# Optional but recommended tool: bat
has_bat=false
if command_exists "bat"; then
  has_bat=true
elif command_exists "batcat"; then
  # On some distros, bat is installed as batcat
  has_bat=true
  alias bat="batcat"
fi

# Check if we're running in Wayland or X11
is_wayland=false
if [[ -n "$WAYLAND_DISPLAY" ]]; then
  is_wayland=true
  if ! command_exists "wl-copy"; then
    missing_tools+=("wl-copy")
  fi
else
  # Assuming X11
  if ! command_exists "xclip"; then
    missing_tools+=("xclip")
  fi
fi

# If there are missing tools, inform the user and exit
if [[ ${#missing_tools[@]} -gt 0 ]]; then
  echo "Error: The following required tools are missing:"
  for tool in "${missing_tools[@]}"; do
    echo "  - $tool"
  done
  echo "Please install them and try again."
  exit 1
fi

if [[ ! $has_bat ]]; then
  echo "Note: 'bat' is not installed. Will fall back to 'cat' for code display."
  echo "Consider installing 'bat' for syntax highlighting: https://github.com/sharkdp/bat"
fi

# Function to copy to clipboard based on the detected environment
copy_to_clipboard() {
  if [[ $is_wayland == true ]]; then
    wl-copy
  else
    xclip -selection clipboard
  fi
}

# Function to process a workspace directory
process_workspace() {
  local workspace_dir="$1"
  local temp_file=$(mktemp)
  
  # Validate directory
  if [[ ! -d "$workspace_dir" ]]; then
    echo "Error: '$workspace_dir' is not a directory."
    exit 1
  fi
  
  # Change to the workspace directory
  cd "$workspace_dir" || exit 1
  
  # Get directory structure
  echo "Generating directory structure..."
  echo -e "# Workspace Structure\n" >> "$temp_file"
  echo -e "\`\`\`" >> "$temp_file"
  tree -a -I "node_modules|.git" . >> "$temp_file"
  echo -e "\`\`\`\n" >> "$temp_file"
  
  # Process all files, skipping common binary files and large directories
  echo "Processing files..."
  echo -e "# Workspace Files\n" >> "$temp_file"
  
  # Use a direct loop to avoid subshell issues with variables
  while IFS= read -r file; do
    # Skip empty files
    if [[ ! -s "$file" ]]; then
      echo -e "## $file\n\n(Empty file)\n" >> "$temp_file"
      continue
    fi
    
    # Get file extension for code blocks
    file_ext="${file##*.}"
    
    # Comprehensive list of code and text file extensions
    code_extensions=(
      # Web development
      "js" "jsx" "ts" "tsx" "html" "htm" "css" "scss" "sass" "less" "json" "xml" "svg" "php" "vue" "astro" "svelte"
      # System/Shell
      "sh" "bash" "zsh" "fish" "cmd" "bat" "ps1" "awk" "sed"
      # Configuration
      "yml" "yaml" "toml" "ini" "conf" "cfg" "properties" "env" "gitignore" "gitattributes" "editorconfig"
      # C/C++ family
      "c" "cpp" "cc" "cxx" "h" "hpp" "hxx" "inl"
      # Java/JVM family
      "java" "kt" "kts" "groovy" "scala" "clj" "gradle"
      # C#/.NET
      "cs" "vb" "fs" "xaml" "cshtml" "razor"
      # Python
      "py" "pyw" "pyx" "pxd" "pxi" "rpy" "ipynb"
      # Ruby
      "rb" "erb" "rakefile" "gemspec"
      # Go
      "go" "mod" "sum"
      # Rust
      "rs" "toml"
      # Swift/Objective-C
      "swift" "m" "mm"
      # JavaScript alternatives
      "coffee" "ts" "ls"
      # PHP
      "php" "phtml" "php4" "php5" "php7" "phps"
      # Documentation and text
      "md" "markdown" "rst" "txt" "text" "adoc" "tex" "ltx" "log"
      # Data formats
      "csv" "tsv" "sql" "graphql" "gql"
      # Dart/Flutter
      "dart"
      # Haskell
      "hs" "lhs"
      # Elixir/Erlang
      "ex" "exs" "erl" "hrl"
      # PowerShell
      "ps1" "psm1" "psd1"
      # Lua
      "lua"
      # R
      "r" "rmd"
      # Assembly
      "asm" "s"
    )
    
    # Check if the file has a code extension (case insensitive)
    is_code_file=false
    file_ext_lower=$(echo "$file_ext" | tr '[:upper:]' '[:lower:]')
    for ext in "${code_extensions[@]}"; do
      if [[ "$file_ext_lower" == "$ext" ]]; then
        is_code_file=true
        break
      fi
    done
    
    # If not a known extension, try to detect if it's text
    if [[ "$is_code_file" == "false" ]]; then
      # Check for shebang in the first line
      if head -n 1 "$file" | grep -q "^#!"; then
        is_code_file=true
      elif file --mime-type "$file" | grep -q -E "text/|application/json|application/xml|application/javascript"; then
        is_code_file=true
      elif file "$file" | grep -i -E "text|ascii|utf-8|script|source|program" > /dev/null; then
        is_code_file=true
      fi
    fi
    
    if [[ "$is_code_file" == "true" ]]; then
      echo -e "## $file\n" >> "$temp_file"
      echo -e "\`\`\`$file_ext_lower" >> "$temp_file"
      
      # Use bat with plain mode if available, otherwise use cat
      if [[ $has_bat == true ]]; then
        bat --plain --color=never "$file" >> "$temp_file"
      else
        cat "$file" >> "$temp_file"
      fi
      
      echo -e "\`\`\`\n" >> "$temp_file"
    else
      # Try to read the first few bytes to see if it might be text
      if head -c 1000 "$file" 2>/dev/null | grep -q "[[:print:][:space:]]\+"; then
        echo -e "## $file\n" >> "$temp_file"
        echo -e "\`\`\`" >> "$temp_file"
        cat "$file" >> "$temp_file"
        echo -e "\`\`\`\n" >> "$temp_file"
      else
        echo -e "## $file\n\n(Binary file, not displayed)\n" >> "$temp_file"
      fi
    fi
  done < <(find . -type f -not -path "*/node_modules/*" -not -path "*/.git/*" | sort)
  
  # Copy to clipboard
  cat "$temp_file" | copy_to_clipboard
  
  echo "Workspace content has been copied to clipboard!"
  echo "Total files processed: $(find . -type f -not -path "*/node_modules/*" -not -path "*/.git/*" | wc -l)"
  
  # Clean up
  rm "$temp_file"
}

# Main execution
if [[ $# -eq 0 ]]; then
  # No argument provided, use current directory
  process_workspace "$(pwd)"
else
  # Use the provided directory
  process_workspace "$1"
fi

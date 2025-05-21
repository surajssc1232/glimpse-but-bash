#!/bin/bash

set -e

command_exists() {
  command -v "$1" &> /dev/null
}

required_tools=("tree" "find" "file")
missing_tools=()

for tool in "${required_tools[@]}"; do
  if ! command_exists "$tool"; then
    missing_tools+=("$tool")
  fi
done

has_bat=false
if command_exists "bat"; then
  has_bat=true
elif command_exists "batcat"; then
  has_bat=true
  alias bat="batcat"
fi

is_wayland=false
if [[ -n "$WAYLAND_DISPLAY" ]]; then
  is_wayland=true
  if ! command_exists "wl-copy"; then
    missing_tools+=("wl-copy")
  fi
else
  if ! command_exists "xclip"; then
    missing_tools+=("xclip")
  fi
fi

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

copy_to_clipboard() {
  if [[ $is_wayland == true ]]; then
    wl-copy
  else
    xclip -selection clipboard
  fi
}

process_workspace() {
  local workspace_dir="$1"
  local temp_file=$(mktemp)
  
  if [[ ! -d "$workspace_dir" ]]; then
    echo "Error: '$workspace_dir' is not a directory."
    exit 1
  fi
  
  cd "$workspace_dir" || exit 1
  
  echo "Generating directory structure..."
  echo -e "# Workspace Structure\n" >> "$temp_file"
  echo -e "\`\`\`" >> "$temp_file"
  tree -a -I "node_modules|dist|build|.git|.next|target|venv|__pycache__|.idea|.vscode|out" . >> "$temp_file"
  echo -e "\`\`\`\n" >> "$temp_file"
  
  echo "Processing files..."
  echo -e "# Workspace Files\n" >> "$temp_file"
  
  find . -type f \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/.next/*" \
    -not -path "*/target/*" \
    -not -path "*/venv/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.idea/*" \
    -not -path "*/.vscode/*" \
    -not -path "*/out/*" \
    -print0 | while IFS= read -r -d $'\0' file; do
    
    if [[ ! -s "$file" ]]; then
      echo -e "## File: $file\n\n(Empty file)\n" >> "$temp_file"
      continue
    fi
    
    file_ext="${file##*.}"
    if [[ "$file_ext" == "$file" ]]; then
      file_ext="text"
    fi
    
    code_extensions=(
      "js" "jsx" "ts" "tsx" "html" "htm" "css" "scss" "sass" "less" "json" "xml" "svg" "php" "vue" "astro" "svelte"
      "sh" "bash" "zsh" "fish" "cmd" "bat" "ps1" "awk" "sed" "makefile" "dockerfile"
      "yml" "yaml" "toml" "ini" "conf" "cfg" "properties" "env" "gitignore" "gitattributes" "editorconfig"
      "c" "cpp" "cc" "cxx" "h" "hpp" "hxx" "inl"
      "java" "kt" "kts" "groovy" "scala" "clj" "gradle"
      "cs" "vb" "fs" "xaml" "cshtml" "razor"
      "py" "pyw" "pyx" "pxd" "pxi" "rpy" "ipynb"
      "rb" "erb" "rakefile" "gemspec"
      "go" "mod" "sum"
      "rs" "toml"
      "swift" "m" "mm"
      "coffee" "ts" "ls"
      "php" "phtml" "php4" "php5" "php7" "phps"
      "md" "markdown" "rst" "txt" "text" "adoc" "tex" "ltx" "log" "nfo"
      "csv" "tsv" "sql" "graphql" "gql"
      "dart"
      "hs" "lhs"
      "ex" "exs" "erl" "hrl"
      "ps1" "psm1" "psd1"
      "lua"
      "r" "rmd"
      "asm" "s"
      "tsv" "csv" "jsonl"
    )
    
    is_code_file=false
    file_ext_lower=$(echo "$file_ext" | tr '[:upper:]' '[:lower:]')
    for ext in "${code_extensions[@]}"; do
      if [[ "$file_ext_lower" == "$ext" ]]; then
        is_code_file=true
        break
      fi
    done
    
    if [[ "$is_code_file" == "false" ]]; then
      if head -n 1 "$file" | grep -q "^#!"; then
        is_code_file=true
      elif file --mime-type "$file" | grep -q -E "text/|application/json|application/xml|application/javascript"; then
        is_code_file=true
      elif file "$file" | grep -i -E "text|ascii|utf-8|script|source|program" > /dev/null; then
        is_code_file=true
      fi
    fi
    
    if [[ "$is_code_file" == "true" ]]; then
      echo -e "## File: $file\n" >> "$temp_file"
      echo -e "\`\`\`$file_ext_lower" >> "$temp_file"
      
      if [[ $has_bat == true ]]; then
        bat --color=never "$file" >> "$temp_file"
      else
        cat "$file" >> "$temp_file"
      fi
      
      echo -e "\`\`\`\n" >> "$temp_file"
    else
      if head -c 1024 "$file" 2>/dev/null | LC_ALL=C grep -q "[[:print:][:space:]]\+"; then
        echo -e "## File: $file\n" >> "$temp_file"
        echo -e "\`\`\`text" >> "$temp_file"
        cat "$file" >> "$temp_file"
        echo -e "\`\`\`\n" >> "$temp_file"
      else
        echo -e "## File: $file\n\n(Binary file, not displayed)\n" >> "$temp_file"
      fi
    fi
  done
  
  cat "$temp_file" | copy_to_clipboard
  
  echo "Workspace content has been copied to clipboard!"
  echo "Total files processed: $(find . -type f -not -path "*/node_modules/*" -not -path "*/.git/*" | wc -l)"
  
  rm "$temp_file"
}

if [[ $# -eq 0 ]]; then
  process_workspace "$(pwd)"
else
  process_workspace "$1"
fi

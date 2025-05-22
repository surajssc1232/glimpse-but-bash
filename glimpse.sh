#!/bin/bash

# workspace_copy.sh - A script to copy workspace content for LLMs
# Features:
# - Detects clipboard system (Wayland/X11) automatically
# - Uses tree for directory structure visualization
# - Uses bat for code display
# - Copies all subdirectories and their content
# - Improved exclusion for large workspaces and binary files
# - Enhanced language detection and markdown formatting
# - ADDED DEBUGGING OUTPUT TO DIAGNOSE MISSED FILES
# - **FIXED: Robust clipboard copying for Wayland**

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
  alias bat="batcat" # Create an alias for consistency
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

# **IMPORTANT CHANGE**: Removed copy_to_clipboard function,
# as wl-copy is more reliable when directly redirecting from a file.
# The logic will be inlined into process_workspace for clarity and direct control.

# Define common directories/files to exclude for LLM context
EXCLUDE_PATTERNS=(
  ".git" "node_modules" "target" "build" "dist" "out" "bin"
  "__pycache__" "venv" "env"
  ".vscode" ".idea" ".DS_Store" "Thumbs.db"
  "*.log" "*.tmp" "*.swp"
  "*.min.js" "*.min.css" # Minified assets (rarely useful for LLM)
  "package-lock.json" "yarn.lock" "pnpm-lock.yaml"
  ".next" ".svelte-kit" ".parcel-cache" ".nuxt"
  "coverage"
)

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
  
  echo "--- DEBUG INFO ---" >> /dev/stderr
  echo "Current directory: $(pwd)" >> /dev/stderr
  echo "Temp file for output: $temp_file" >> /dev/stderr
  echo "--- END DEBUG INFO ---" >> /dev/stderr

  # --- Workspace Structure ---
  echo "Generating directory structure..." >> /dev/stderr
  echo -e "# Workspace Structure\n" >> "$temp_file"
  echo -e "\`\`\`" >> "$temp_file"
  
  local tree_exclude_str=$(IFS='|'; echo "${EXCLUDE_PATTERNS[*]}")
  tree -a -I "$tree_exclude_str" . >> "$temp_file"
  echo -e "\`\`\`\n" >> "$temp_file"
  echo -e "---\n" >> "$temp_file" # Separator
  
  # --- Workspace Files ---
  echo "Processing files..." >> /dev/stderr
  echo -e "# Workspace Files\n" >> "$temp_file"
  
  local code_extensions=(
    "js" "jsx" "ts" "tsx" "html" "htm" "css" "scss" "sass" "less" "json" "xml" "svg" "php" "vue" "astro" "svelte" "pug" "hbs" "ejs"
    "sh" "bash" "zsh" "fish" "cmd" "bat" "ps1" "awk" "sed" "makefile" "dockerfile" "nginx" "apache" "conf" "cfg" "ini" "editorconfig" "gitattributes" "gitignore" "npmrc" "prettierrc" "eslintrc" "browserslistrc" "yarnrc" "pnpmfile.js"
    "yml" "yaml" "toml" "env" "properties"
    "c" "cpp" "cc" "cxx" "h" "hpp" "hxx" "inl"
    "java" "kt" "kts" "groovy" "scala" "clj" "gradle" "pom.xml" "build.gradle" "settings.gradle"
    "cs" "vb" "fs" "xaml" "cshtml" "razor" "csproj" "fsproj" "vbproj"
    "py" "pyw" "pyx" "pxd" "pxi" "rpy" "ipynb" "pyproject.toml" "requirements.txt" "Pipfile" "Pipfile.lock"
    "rb" "erb" "rakefile" "gemspec" "Gemfile" "Gemfile.lock"
    "go" "mod" "sum"
    "rs" "cargo.toml" "cargo.lock"
    "swift" "m" "mm" "h"
    "coffee" "ls" "ts"
    "md" "markdown" "rst" "txt" "text" "adoc" "tex" "ltx" "nfo" "log" "rtf"
    "csv" "tsv" "sql" "graphql" "gql" "jsonl"
    "dart" "pubspec.yaml" "pubspec.lock"
    "hs" "lhs"
    "ex" "exs" "erl" "hrl"
    "ps1" "psm1" "psd1"
    "lua"
    "r" "rmd"
    "asm" "s"
    "zig" "nim" "v" "rkt" "clj" "cljs" "purs" "elm" "coq" "agda" "lean" "scm" "ss"
  )

  local find_cmd="find . -type f"
  # You can uncomment or adjust the size limit here for very large workspaces
  # find_cmd+=" -size -10M" # Example: Limit to files under 10MB
  
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    # Ensure patterns with wildcards work correctly with -path
    # For directory patterns like 'node_modules', ensure a trailing '/'
    # For file patterns like '*.log', ensure no trailing '/'
    if [[ "$pattern" == *.* ]]; then # Likely a file pattern
      find_cmd+=" -not -path \"*/$pattern\""
    else # Likely a directory pattern
      find_cmd+=" -not -path \"*/$pattern/*\""
    fi
  done
  
  find_cmd+=" -print0"

  echo "--- DEBUG: Running find command: $find_cmd ---" >> /dev/stderr

  eval "$find_cmd" | while IFS= read -r -d $'\0' file; do
    echo "--- DEBUG: Processing file: $file ---" >> /dev/stderr

    if [[ ! -r "$file" ]]; then
        echo -e "---\n## File: $file\n\n(Permission denied - file not read)\n" >> "$temp_file"
        echo "--- DEBUG: Permission denied for $file ---" >> /dev/stderr
        continue
    fi

    if [[ ! -s "$file" ]]; then
      echo -e "---\n## File: $file\n\n(Empty file)\n" >> "$temp_file"
      echo "--- DEBUG: $file is empty ---" >> /dev/stderr
      continue
    fi
    
    file_ext="${file##*.}"
    if [[ "$file_ext" == "$file" ]]; then
      case "$(basename "$file" | tr '[:upper:]' '[:lower:]')" in
        "makefile"|"dockerfile"|"caddyfile"|"vagrantfile"|"rakefile"|"gemfile"|"pipfile"|"npmrc"|".bashrc"|".zshrc"|".profile"|"hosts"|"fstab")
          file_ext_lower=$(basename "$file" | tr '[:upper:]' '[:lower:]')
          ;;
        *)
          file_ext_lower="text"
          ;;
      esac
    else
      file_ext_lower=$(echo "$file_ext" | tr '[:upper:]' '[:lower:]')
    fi
    
    is_code_file=false
    for ext in "${code_extensions[@]}"; do
      if [[ "$file_ext_lower" == "$ext" ]]; then
        is_code_file=true
        break
      fi
    done
    
    if [[ "$is_code_file" == "false" ]]; then
      if head -n 1 "$file" | grep -q "^#!"; then
        is_code_file=true
        echo "--- DEBUG: $file detected as script by shebang ---" >> /dev/stderr
        if head -n 1 "$file" | grep -q "python"; then file_ext_lower="python";
        elif head -n 1 "$file" | grep -q "node"; then file_ext_lower="javascript";
        elif head -n 1 "$file" | grep -q "bash"; then file_ext_lower="bash";
        elif head -n 1 "$file" | grep -q "perl"; then file_ext_lower="perl";
        elif head -n 1 "$file" | grep -q "ruby"; then file_ext_lower="ruby";
        fi
      elif file --mime-type "$file" | grep -q -E "text/|application/json|application/xml|application/javascript|application/x-sh|application/x-python|application/octet-stream"; then
        is_code_file=true
        echo "--- DEBUG: $file detected as text/code by MIME type ---" >> /dev/stderr
        if file --mime-type "$file" | grep -q "application/json"; then file_ext_lower="json";
        elif file --mime-type "$file" | grep -q "application/xml"; then file_ext_lower="xml";
        elif file --mime-type "$file" | grep -q "application/javascript"; then file_ext_lower="javascript";
        elif file --mime-type "$file" | grep -q "application/x-sh"; then file_ext_lower="bash";
        elif file --mime-type "$file" | grep -q "application/x-python"; then file_ext_lower="python";
        elif file --mime-type "$file" | grep -q "application/octet-stream"; then
            if head -c 1024 "$file" 2>/dev/null | LC_ALL=C grep -q "[[:print:][:space:]]\+"; then
                file_ext_lower="text"
            else
                is_code_file=false
            fi
        fi
      elif file "$file" | grep -i -E "text|ascii|utf-8|script|source|program" > /dev/null; then
        is_code_file=true
        echo "--- DEBUG: $file detected as text/code by generic file output ---" >> /dev/stderr
      fi
    fi
    
    if [[ "$is_code_file" == "true" ]]; then
      echo -e "---\n## File: $file\n" >> "$temp_file"
      echo -e "\`\`\`$file_ext_lower" >> "$temp_file"
      
      echo "--- DEBUG: Including $file as code/text with language hint: $file_ext_lower ---" >> /dev/stderr
      if [[ $has_bat == true ]]; then
        bat --color=never --paging=never "$file" >> "$temp_file" || { echo "--- DEBUG: bat failed for $file, falling back to cat ---" >> /dev/stderr; cat "$file" >> "$temp_file"; }
      else
        cat "$file" >> "$temp_file"
      fi
      
      echo -e "\`\`\`\n" >> "$temp_file"
    else
      if file --mime-type "$file" | grep -q -E "image/|video/|audio/|application/zip|application/x-tar|application/gzip|application/pdf|font/"; then
        echo -e "---\n## File: $file\n\n(Binary file, not displayed)\n" >> "$temp_file"
        echo "--- DEBUG: $file explicitly identified as binary, not displayed ---" >> /dev/stderr
      elif head -c 1024 "$file" 2>/dev/null | LC_ALL=C grep -q "[[:print:][:space:]]\+"; then
        echo -e "---\n## File: $file\n\n(Detected as plain text, displaying content)\n" >> "$temp_file"
        echo -e "\`\`\`text" >> "$temp_file"
        cat "$file" >> "$temp_file"
        echo "--- DEBUG: $file treated as generic plain text ---" >> /dev/stderr
      else
        echo -e "---\n## File: $file\n\n(Undetermined or truly binary file, not displayed)\n" >> "$temp_file"
        echo "--- DEBUG: $file is truly undetermined/binary, not displayed ---" >> /dev/stderr
      fi
    fi
  done
  
  # **THE CRITICAL CHANGE FOR WAYLAND COPYING**
  echo "--- DEBUG: Attempting final clipboard copy ---" >> /dev/stderr
  if [[ $is_wayland == true ]]; then
    # Direct redirection from the temporary file to wl-copy is more reliable
    wl-copy < "$temp_file"
    # Added a small sleep to ensure clipboard manager has time to process (might not be necessary)
    sleep 0.1
  else
    cat "$temp_file" | xclip -selection clipboard
  fi
  echo "--- DEBUG: Clipboard operation completed ---" >> /dev/stderr

  echo "Workspace content has been copied to clipboard!"
  local included_files_count=$(grep -c "## File: " "$temp_file")
  echo "Total files included in clipboard: $included_files_count"
  
  # Clean up
  rm "$temp_file"
}

# Main execution
if [[ $# -eq 0 ]]; then
  process_workspace "$(pwd)"
else
  process_workspace "$1"
fi

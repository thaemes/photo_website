#!/usr/bin/env bash
# update.sh — rebuild site-data.js from photos/ and writing/
# Usage:
#   ./update.sh               — rebuild everything (no prompts)
#   ./update.sh photos        — add a new gallery interactively
#   ./update.sh writing       — convert .md files and rebuild articles
#   ./update.sh help          — show this message

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PHOTOS_DIR="photos"
WRITING_DIR="writing"
OUTPUT="site-data.js"

# ── Colour helpers ───────────────────────────────────────────
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
blue()   { printf '\033[0;34m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }

# ── Markdown → HTML (pure bash, no deps) ─────────────────────
# Handles: headings, bold, italic, code blocks, inline code,
#          blockquotes, unordered/ordered lists, links, images, hr, paragraphs
md_to_html() {
  local input="$1"
  local output=""
  local in_code=0
  local in_ul=0
  local in_ol=0
  local code_buf=""
  local para_buf=""
  local lang=""

  flush_para() {
    if [[ -n "$para_buf" ]]; then
      local line
      line=$(inline_md "$para_buf")
      output+="<p>$line</p>\n"
      para_buf=""
    fi
  }

  flush_list() {
    if [[ $in_ul -eq 1 ]]; then output+="</ul>\n"; in_ul=0; fi
    if [[ $in_ol -eq 1 ]]; then output+="</ol>\n"; in_ol=0; fi
  }

  inline_md() {
    local s="$1"
    # images before links
    s=$(echo "$s" | sed -E 's/!\[([^]]*)\]\(([^)]+)\)/<img src="\2" alt="\1">/g')
    # links
    s=$(echo "$s" | sed -E 's/\[([^]]+)\]\(([^)]+)\)/<a href="\2">\1<\/a>/g')
    # bold
    s=$(echo "$s" | sed -E 's/\*\*([^*]+)\*\*/<strong>\1<\/strong>/g')
    s=$(echo "$s" | sed -E 's/__([^_]+)__/<strong>\1<\/strong>/g')
    # italic
    s=$(echo "$s" | sed -E 's/\*([^*]+)\*/<em>\1<\/em>/g')
    s=$(echo "$s" | sed -E 's/_([^_]+)_/<em>\1<\/em>/g')
    # inline code
    s=$(echo "$s" | sed -E 's/`([^`]+)`/<code>\1<\/code>/g')
    echo "$s"
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Fenced code blocks
    if [[ "$line" =~ ^\`\`\`(.*)$ ]]; then
      if [[ $in_code -eq 0 ]]; then
        flush_para; flush_list
        lang="${BASH_REMATCH[1]}"
        in_code=1; code_buf=""
        continue
      else
        local lang_attr=""
        [[ -n "$lang" ]] && lang_attr=" class=\"language-$lang\""
        output+="<pre><code$lang_attr>$(echo "$code_buf" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</code></pre>\n"
        in_code=0; lang=""
        continue
      fi
    fi
    if [[ $in_code -eq 1 ]]; then
      [[ -n "$code_buf" ]] && code_buf+=$'\n'
      code_buf+="$line"; continue
    fi

    # HR
    if [[ "$line" =~ ^(---+|\*\*\*+|___+)$ ]]; then
      flush_para; flush_list; output+="<hr>\n"; continue
    fi

    # Blank line
    if [[ -z "$line" ]]; then
      flush_para; flush_list; continue
    fi

    # Headings
    if [[ "$line" =~ ^(#{1,6})[[:space:]](.+)$ ]]; then
      flush_para; flush_list
      local level="${#BASH_REMATCH[1]}"
      local text
      text=$(inline_md "${BASH_REMATCH[2]}")
      output+="<h$level>$text</h$level>\n"
      continue
    fi

    # Blockquote
    if [[ "$line" =~ ^\>[[:space:]]?(.*)$ ]]; then
      flush_para; flush_list
      local bq
      bq=$(inline_md "${BASH_REMATCH[1]}")
      output+="<blockquote><p>$bq</p></blockquote>\n"
      continue
    fi

    # Unordered list
    if [[ "$line" =~ ^[-*+][[:space:]](.+)$ ]]; then
      flush_para
      if [[ $in_ol -eq 1 ]]; then output+="</ol>\n"; in_ol=0; fi
      if [[ $in_ul -eq 0 ]]; then output+="<ul>\n"; in_ul=1; fi
      local li
      li=$(inline_md "${BASH_REMATCH[1]}")
      output+="<li>$li</li>\n"; continue
    fi

    # Ordered list
    if [[ "$line" =~ ^[0-9]+\.[[:space:]](.+)$ ]]; then
      flush_para
      if [[ $in_ul -eq 1 ]]; then output+="</ul>\n"; in_ul=0; fi
      if [[ $in_ol -eq 0 ]]; then output+="<ol>\n"; in_ol=1; fi
      local li
      li=$(inline_md "${BASH_REMATCH[1]}")
      output+="<li>$li</li>\n"; continue
    fi

    # Paragraph accumulation
    flush_list
    [[ -n "$para_buf" ]] && para_buf+=" "
    para_buf+="$line"
  done < <(echo "$input")

  flush_para; flush_list
  [[ $in_code -eq 1 ]] && output+="<pre><code>$(echo "$code_buf" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</code></pre>\n"

  printf '%s' "$output"
}

# ── JSON helpers ─────────────────────────────────────────────
json_str() {
  # Escape a string for safe embedding in a JSON string value.
  # HTML structure comes from tags, not whitespace — collapse newlines to spaces.
  local s="$1"
  s="${s//\\/\\\\}"          # backslash → \\
  s="${s//\"/\\\"}"            # double-quote → \"
  s="$(printf '%s' "$s" | tr '\n\r\t' '   ')"  # newlines/tabs → space
  printf '%s' "$s"
}

# ── Build galleries array ─────────────────────────────────────
build_galleries() {
  local json="["
  local first=1

  if [[ ! -d "$PHOTOS_DIR" ]]; then
    echo "[]"; return
  fi

  # Read gallery order from photos/_order if it exists, else sort by name
  local dirs=()
  if [[ -f "$PHOTOS_DIR/_order" ]]; then
    while IFS= read -r d; do
      [[ -n "$d" && -d "$PHOTOS_DIR/$d" ]] && dirs+=("$d")
    done < "$PHOTOS_DIR/_order"
  else
    while IFS= read -r d; do
      dirs+=("$d")
    done < <(find "$PHOTOS_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r | xargs -I{} basename {})
  fi

  for dir in "${dirs[@]}"; do
    local full="$PHOTOS_DIR/$dir"
    [[ ! -d "$full" ]] && continue

    # Read meta
    local title="$dir"
    local desc=""
    if [[ -f "$full/_meta" ]]; then
      while IFS='=' read -r key val; do
        key="$(echo "$key" | tr -d '[:space:]')"
        val="$(echo "$val" | sed 's/^[[:space:]]*//')"
        [[ "$key" == "title" ]] && title="$val"
        [[ "$key" == "desc"  ]] && desc="$val"
      done < "$full/_meta"
    fi

    # Collect images (sorted)
    local photos_json="["
    local pfirst=1
    while IFS= read -r img; do
      local relpath="$full/$(basename "$img")"
      [[ $pfirst -eq 0 ]] && photos_json+=","
      photos_json+="\"$(json_str "$relpath")\""
      pfirst=0
    done < <(find "$full" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) | sort)
    photos_json+="]"

    # Skip empty galleries
    [[ "$photos_json" == "[]" ]] && continue

    [[ $first -eq 0 ]] && json+=","
    json+="{\"title\":\"$(json_str "$title")\",\"desc\":\"$(json_str "$desc")\",\"dir\":\"$(json_str "$full")\",\"photos\":$photos_json}"
    first=0
  done

  json+="]"
  echo "$json"
}

# ── Build articles array ──────────────────────────────────────
build_articles() {
  local json="["
  local first=1

  if [[ ! -d "$WRITING_DIR" ]]; then
    echo "[]"; return
  fi

  # Collect .md files and sort by date (filename convention: YYYY-MM-DD-slug.md)
  local files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(find "$WRITING_DIR" -maxdepth 1 -name "*.md" | sort -r)

  for filepath in "${files[@]}"; do
    local filename
    filename="$(basename "$filepath" .md)"

    # Extract date and slug from filename (YYYY-MM-DD-slug or just slug)
    local date=""
    local slug="$filename"
    if [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})-(.+)$ ]]; then
      date="${BASH_REMATCH[1]}"
      slug="${BASH_REMATCH[2]}"
    fi

    # Read frontmatter (lines between --- markers at top of file)
    local title="$slug"
    local desc=""
    local fm_date="$date"
    local body_start=1
    local content
    content="$(cat "$filepath")"

    if [[ "$content" =~ ^--- ]]; then
      local in_fm=0
      local lineno=0
      while IFS= read -r line; do
        ((lineno++))
        if [[ $lineno -eq 1 && "$line" == "---" ]]; then in_fm=1; continue; fi
        if [[ $in_fm -eq 1 && "$line" == "---" ]]; then body_start=$((lineno+1)); break; fi
        if [[ $in_fm -eq 1 ]]; then
          if [[ "$line" =~ ^title:[[:space:]]*(.+)$ ]]; then title="${BASH_REMATCH[1]}"; fi
          if [[ "$line" =~ ^date:[[:space:]]*(.+)$ ]];  then fm_date="${BASH_REMATCH[1]}"; fi
          if [[ "$line" =~ ^desc:[[:space:]]*(.+)$ ]];  then desc="${BASH_REMATCH[1]}"; fi
        fi
      done <<< "$content"
      date="$fm_date"
    fi

    # Strip frontmatter to get body
    local body
    body="$(tail -n +"$body_start" "$filepath")"

    # Convert markdown to HTML
    local html
    html="$(md_to_html "$body")"

    [[ $first -eq 0 ]] && json+=","
    json+="{\"slug\":\"$(json_str "$slug")\",\"title\":\"$(json_str "$title")\",\"date\":\"$(json_str "$date")\",\"desc\":\"$(json_str "$desc")\",\"html\":\"$(json_str "$html")\"}"
    first=0
  done

  json+="]"
  echo "$json"
}

# ── Add new gallery interactively ────────────────────────────
add_gallery() {
  blue "=== Add new photo gallery ==="
  echo ""

  read -rp "Gallery folder name (no spaces, e.g. paris-2024): " folder
  if [[ -z "$folder" ]]; then red "Folder name required."; exit 1; fi
  if [[ "$folder" =~ [[:space:]] ]]; then red "No spaces in folder name."; exit 1; fi

  read -rp "Gallery title (e.g. Paris, Summer 2024): " title
  [[ -z "$title" ]] && title="$folder"

  read -rp "One-line description (optional): " desc

  local target="$PHOTOS_DIR/$folder"
  if [[ -d "$target" ]]; then
    yellow "Directory $target already exists."
  else
    mkdir -p "$target"
    green "Created $target"
  fi

  # Write meta file
  cat > "$target/_meta" << EOF
title = $title
desc = $desc
EOF

  green "Meta written to $target/_meta"
  echo ""
  yellow "→ Now copy your photos into: $target/"
  yellow "→ Then run: ./update.sh  to rebuild site-data.js"
  echo ""
}

# ── Add new article interactively ────────────────────────────
add_article() {
  blue "=== Add new article ==="
  echo ""

  local today
  today="$(date +%Y-%m-%d)"

  read -rp "Article slug (e.g. my-trip-to-lisbon): " slug
  if [[ -z "$slug" ]]; then red "Slug required."; exit 1; fi

  read -rp "Title: " title
  [[ -z "$title" ]] && title="$slug"

  read -rp "One-line description (optional): " desc

  local filename="$WRITING_DIR/${today}-${slug}.md"
  mkdir -p "$WRITING_DIR"

  if [[ -f "$filename" ]]; then
    yellow "File $filename already exists, skipping creation."
  else
    cat > "$filename" << EOF
---
title: $title
date: $today
desc: $desc
---

Write your article here. Markdown is supported.

## Section heading

Paragraph text goes here.
EOF
    green "Created $filename"
  fi

  echo ""
  yellow "→ Edit $filename, then run: ./update.sh  to rebuild"
  echo ""
}

# ── Write site-data.js ───────────────────────────────────────
rebuild() {
  blue "Scanning photos..."
  local galleries
  galleries="$(build_galleries)"

  blue "Scanning writing..."
  local articles
  articles="$(build_articles)"

  cat > "$OUTPUT" << EOF
// AUTO-GENERATED by update.sh — do not edit by hand
const siteData = {
  galleries: $galleries,
  articles: $articles
};
EOF

  green "Written: $OUTPUT"

  # Count entries
  local g_count a_count
  g_count=$(echo "$galleries" | grep -o '"title"' | wc -l | tr -d ' ')
  a_count=$(echo "$articles"  | grep -o '"slug"'  | wc -l | tr -d ' ')
  green "  $g_count gallery/galleries, $a_count article(s)"
}

# ── Main ─────────────────────────────────────────────────────
case "${1:-rebuild}" in
  photos|gallery)
    add_gallery
    rebuild
    ;;
  writing|article|blog)
    add_article
    rebuild
    ;;
  rebuild|"")
    rebuild
    ;;
  help|--help|-h)
    echo ""
    echo "  update.sh            — rebuild site-data.js from all photos/ and writing/"
    echo "  update.sh photos     — add a new photo gallery interactively, then rebuild"
    echo "  update.sh writing    — create a new article stub, then rebuild"
    echo "  update.sh help       — this message"
    echo ""
    ;;
  *)
    red "Unknown command: $1"
    echo "Run: ./update.sh help"
    exit 1
    ;;
esac
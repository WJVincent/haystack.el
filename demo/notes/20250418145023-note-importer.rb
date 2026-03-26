# title: Note Importer
# date: 2025-04-18
# %%% pkm-end-frontmatter %%%

# A Ruby script for importing notes from external sources into a
# Haystack-compatible plain-text notes corpus.
#
# Handles three common import scenarios:
# 1. Markdown files from Obsidian (with wikilink conversion)
# 2. Exported org files from org-roam (with ID-based link stripping)
# 3. Plain text files with no frontmatter (adds Haystack frontmatter)
#
# The importer normalizes all incoming notes to the flat zettelkasten
# directory structure expected by Haystack, with timestamped filenames
# and pkm-end-frontmatter sentinels.

require "fileutils" require "date" require "pathname"

SENTINEL = "%%% pkm-end-frontmatter %%%" TIMESTAMP_FORMAT = "%Y%m%d%H%M%S"

# Generate a zettelkasten-style timestamped filename.
# @param title [String]
# @param ext [String] without dot
# @param time [Time]
# @return [String]
def generate_filename(title, ext: "org", time: Time.now)
  timestamp = time.strftime(TIMESTAMP_FORMAT)
  slug = title.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-|-$/, "")
  "#{timestamp}-#{slug}.#{ext}"
end

# Write org-style frontmatter to an IO object, followed by the sentinel.
# @param io [IO]
# @param title [String]
# @param date [String] ISO date
def write_org_frontmatter(io, title:, date: Date.today.to_s)
  io.puts "#+TITLE: #{title}"
  io.puts "#+DATE: #{date}"
  io.puts "# #{SENTINEL}"
  io.puts
end

# Write YAML frontmatter for a Markdown note.
# @param io [IO]
# @param title [String]
# @param date [String]
def write_markdown_frontmatter(io, title:, date: Date.today.to_s)
  io.puts "---"
  io.puts "title: #{title}"
  io.puts "date: #{date}"
  io.puts "---"
  io.puts "<!-- #{SENTINEL} -->"
  io.puts
end

# Convert Obsidian wikilinks [[Note Title]] to plain text or org links.
# Haystack uses search rather than hard-coded links, so we can strip them
# or convert to a format that preserves the reference text.
# @param content [String]
# @return [String]
def convert_wikilinks(content)
  content.gsub(/\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/) do
    display = $2 || $1
    display # Just keep the display text; Haystack search will find the target
  end
end

# Strip org-roam :ID: properties from org frontmatter.
# We want clean notes without database-specific metadata.
# @param content [String]
# @return [String]
def strip_org_roam_properties(content)
  content
    .gsub(/:PROPERTIES:\n.*?:END:\n/m, "")
    .gsub(/^:ID:\s*.+\n/, "")
    .gsub(/^:ROAM_ALIASES:\s*.+\n/, "")
end

# Import a single note file into the target notes directory.
# @param source_path [Pathname]
# @param target_dir [Pathname]
# @param format [:org, :markdown, :auto]
def import_note(source_path, target_dir:, format: :auto)
  content = source_path.read(encoding: "utf-8")
  ext = source_path.extname.downcase

  # Detect format if auto
  fmt = case format
        when :auto then ext == ".md" ? :markdown : :org
        else format
        end

  # Extract or generate a title for the note
  title = content.match(/^(?:#\+)?title:\s*(.+)/i)&.captures&.first&.strip ||
          source_path.basename(".*").to_s.gsub(/[-_]/, " ").capitalize

  # Extract date from filename if zettelkasten-style, otherwise use file mtime
  mtime = source_path.stat.mtime
  file_date = mtime.strftime("%Y-%m-%d")

  # Clean up content
  body = strip_org_roam_properties(content)
  body = convert_wikilinks(body) if fmt == :markdown

  # Strip any existing frontmatter (before the sentinel or before first heading)
  if body.include?(SENTINEL)
    body = body.split(SENTINEL, 2).last.lstrip
  elsif body.start_with?("---")
    body = body.sub(/\A---\n.*?---\n/m, "").lstrip
  end

  # Generate output filename and write
  out_filename = generate_filename(title, ext: fmt == :markdown ? "md" : "org", time: mtime)
  out_path = target_dir / out_filename

  out_path.open("w", encoding: "utf-8") do |f|
    if fmt == :markdown
      write_markdown_frontmatter(f, title: title, date: file_date)
    else
      write_org_frontmatter(f, title: title, date: file_date)
    end
    f.write(body)
  end

  puts "Imported: #{source_path.basename} -> #{out_filename}"
  out_path
end

# Import all notes from a source directory.
# @param source_dir [String]
# @param target_dir [String]
def import_directory(source_dir, target_dir)
  src = Pathname(source_dir).expand_path
  tgt = Pathname(target_dir).expand_path
  FileUtils.mkdir_p(tgt)

  Dir.glob(src / "**" / "*.{org,md}") do |path|
    import_note(Pathname(path), target_dir: tgt)
  rescue StandardError => e
    warn "Error importing #{path}: #{e.message}"
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.length < 2
    abort "Usage: #{$PROGRAM_NAME} SOURCE_DIR TARGET_DIR"
  end
  import_directory(ARGV[0], ARGV[1])
end

# title: Corpus Statistics
# date: 2025-04-21
# %%% pkm-end-frontmatter %%%

# Corpus statistics tool for a Haystack-managed plain-text notes directory.
#
# Computes metrics useful for understanding the health and composition
# of a zettelkasten or second-brain corpus:
# - Note count by format (org, md, code files)
# - Total and average word counts
# - Notes per month (creation activity over time)
# - Most and least frequently referenced notes (via rg link scanning)
# - Vocabulary richness (unique meaningful words across the corpus)

require "pathname" require "date" require "set"

SENTINEL    = "%%% pkm-end-frontmatter %%%"
STOPWORDS   = %w[the a an and or but in on at to for of with is are was were be been
                 it its this that these those i we you he she they my your his her our
                 from by as into through about above over after before not no nor so if].to_set

# Parse a note file, returning metadata and body separately.
# @param path [Pathname]
# @return [Hash]
def parse_note(path)
  lines = path.readlines(encoding: "utf-8")
  meta  = { path: path, filename: path.basename.to_s, title: "", date: "", tags: [] }
  body_lines = []
  in_body = false

  lines.each do |line|
    if line.include?(SENTINEL)
      in_body = true
      next
    end
    if in_body
      body_lines << line
    else
      m = line.match(/^(?:#\+)?(\w+):\s*(.+)/i)
      meta[m[1].downcase.to_sym] = m[2].strip if m
    end
  end

  meta[:body]       = body_lines.join
  meta[:word_count] = body_lines.join.scan(/\S+/).size
  meta[:ext]        = path.extname.downcase
  # Extract creation date from zettelkasten-style filename
  if (ts = path.basename.to_s.match(/^(\d{8})/))
    meta[:created_on] = Date.strptime(ts[1], "%Y%m%d") rescue nil
  end
  meta
end

# Load all notes from a directory.
# @param notes_dir [String]
# @param extensions [Array<String>]
# @return [Array<Hash>]
def load_corpus(notes_dir, extensions: %w[org md])
  dir = Pathname(notes_dir).expand_path
  glob_patterns = extensions.map { |e| dir / "*.#{e}" }
  paths = glob_patterns.flat_map { |p| Pathname.glob(p) }
  paths.map { |p| parse_note(p) }.compact
end

# Print a summary statistics report for the corpus.
# @param notes [Array<Hash>]
def print_report(notes)
  total        = notes.size
  total_words  = notes.sum { |n| n[:word_count] }
  avg_words    = total.positive? ? (total_words.to_f / total).round(1) : 0
  by_ext       = notes.group_by { |n| n[:ext] }.transform_values(&:count)

  puts "=" * 60
  puts "Corpus Statistics"
  puts "=" * 60
  puts "Total notes:       #{total}"
  puts "Total words:       #{total_words}"
  puts "Average words:     #{avg_words} per note"
  puts
  puts "By format:"
  by_ext.sort.each { |ext, count| puts "  #{ext.ljust(6)} #{count}" }
  puts

  # Notes per month
  dated = notes.select { |n| n[:created_on] }
  if dated.any?
    puts "Activity (notes per month, recent 12):"
    by_month = dated.group_by { |n| n[:created_on].strftime("%Y-%m") }
    by_month.sort.last(12).each do |month, ns|
      bar = "#" * ns.size
      puts "  #{month}  #{bar} (#{ns.size})"
    end
    puts
  end

  # Vocabulary richness: unique meaningful words
  all_words = notes.flat_map { |n| n[:body].downcase.scan(/[a-z]{3,}/) }
  unique_words = all_words.reject { |w| STOPWORDS.include?(w) }.uniq.size
  puts "Unique non-stopword vocabulary: #{unique_words} terms"
  puts

  # Longest and shortest notes
  sorted_len = notes.sort_by { |n| n[:word_count] }
  if sorted_len.any?
    puts "Shortest note: #{sorted_len.first[:title] || sorted_len.first[:filename]}" \
         " (#{sorted_len.first[:word_count]} words)"
    puts "Longest note:  #{sorted_len.last[:title]  || sorted_len.last[:filename]}" \
         " (#{sorted_len.last[:word_count]} words)"
  end
  puts "=" * 60
end

if $PROGRAM_NAME == __FILE__
  notes_dir = ARGV[0] || File.expand_path("~/notes")
  corpus    = load_corpus(notes_dir)
  if corpus.empty?
    warn "No notes found in #{notes_dir}"
    exit 1
  end
  print_report(corpus)
end

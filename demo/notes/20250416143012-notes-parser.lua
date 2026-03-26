-- title: Notes Parser
-- date: 2025-04-16
-- %%% pkm-end-frontmatter %%%

--[[
  A Lua module for parsing plain-text notes (zettel) with org or Markdown
  frontmatter. This parser handles the pkm-end-frontmatter sentinel used
  by Haystack and extracts title, date, and arbitrary key-value metadata.

  Designed to be embedded in Neovim plugins, Pandoc filters, or standalone
  corpus processing scripts.
--]]

local M = {}

M.SENTINEL = "%%% pkm-end-frontmatter %%%"

--- Parse frontmatter from a note file string.
--- Returns a table with metadata fields and the body text separately.
--- @param content string The full file content as a string
--- @return table meta, string body
function M.parse(content)
  local meta = {}
  local body_lines = {}
  local in_body = false

  for line in content:gmatch("[^\n]*\n?") do
    if line:find(M.SENTINEL, 1, true) then
      in_body = true
    elseif in_body then
      table.insert(body_lines, line)
    else
      -- Try org-style: #+KEY: value
      local org_key, org_val = line:match("^#%+(%w+):%s*(.+)")
      if org_key then
        meta[org_key:lower()] = org_val:match("^%s*(.-)%s*$")
      else
        -- Try YAML-style: key: value (not inside --- delimiters for simplicity)
        local yaml_key, yaml_val = line:match("^(%w+):%s*(.+)")
        if yaml_key and yaml_key ~= "---" then
          meta[yaml_key:lower()] = yaml_val:match("^%s*(.-)%s*$")
        end
      end
    end
  end

  local body = table.concat(body_lines)
  -- Fallback title from filename hint is handled at call site
  return meta, body
end

--- Count words in the body of a note.
--- @param body string Note body text
--- @return number
function M.word_count(body)
  local count = 0
  for _ in body:gmatch("%S+") do
    count = count + 1
  end
  return count
end

--- Extract the creation timestamp from a zettelkasten-style filename.
--- Expects filenames like 20250416143012-some-title.org
--- @param filename string
--- @return table|nil date table with year/month/day/hour/min/sec or nil
function M.parse_filename_date(filename)
  local y, mo, d, h, mi, s = filename:match("^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)-")
  if y then
    return {
      year = tonumber(y), month = tonumber(mo), day = tonumber(d),
      hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
    }
  end
  return nil
end

--- Check if a note body contains any term from an expansion group.
--- This mirrors Haystack's rg alternation approach but in pure Lua.
--- @param body string
--- @param group table list of synonym strings
--- @return boolean
function M.body_matches_group(body, group)
  local lower_body = body:lower()
  for _, term in ipairs(group) do
    if lower_body:find(term:lower(), 1, true) then
      return true
    end
  end
  return false
end

--- Read and parse a note file from disk.
--- @param filepath string
--- @return table|nil note record or nil on error
function M.read_note(filepath)
  local f, err = io.open(filepath, "r")
  if not f then
    return nil, err
  end
  local content = f:read("*a")
  f:close()

  local meta, body = M.parse(content)
  local filename = filepath:match("[^/\\]+$") or filepath
  meta.path = filepath
  meta.filename = filename
  meta.body = body
  meta.word_count = M.word_count(body)
  meta.file_date = M.parse_filename_date(filename)

  -- Use filename stem as fallback title for notes without explicit title
  if not meta.title then
    meta.title = filename:match("^%d+%-(.-)%.[^.]+$") or filename
  end

  return meta
end

return M
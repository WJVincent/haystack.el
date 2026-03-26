-- title: Text Search in Lua
-- date: 2025-04-17
-- %%% pkm-end-frontmatter %%%

--[[
  Lua utilities for text search over a notes corpus.
  Provides both a ripgrep (rg) subprocess wrapper and a pure-Lua
  fallback for environments where rg is not available.

  The rg-backed search mirrors Haystack's primary search path.
  The pure-Lua search is slower but dependency-free, useful for
  embedded environments or small corpora.
--]]

local M = {}

M.EXTENSIONS = { "org", "md", "txt" }

--- Build an rg alternation pattern from an expansion group.
--- @param terms table list of synonym strings
--- @return string rg-compatible alternation pattern
function M.build_alternation(terms)
  -- Escape special regex characters in each term
  local escaped = {}
  for _, term in ipairs(terms) do
    table.insert(escaped, term:gsub("([%(%)%.%+%*%?%[%]%^%$%%|])", "%%%1"))
  end
  return "(" .. table.concat(escaped, "|") .. ")"
end

--- Expand a query using configured synonym groups.
--- Returns the original query if no group matches.
--- @param query string
--- @param groups table list of synonym lists
--- @return string expanded query or alternation pattern
function M.expand_query(query, groups)
  local lower_q = query:lower()
  for _, group in ipairs(groups) do
    for _, term in ipairs(group) do
      if term:lower() == lower_q then
        return M.build_alternation(group)
      end
    end
  end
  return query
end

--- Run ripgrep (rg) and collect matching file paths.
--- @param query string
--- @param notes_dir string
--- @param extensions table
--- @return table list of matching file paths
function M.rg_search(query, notes_dir, extensions)
  extensions = extensions or M.EXTENSIONS
  local glob_args = ""
  for _, ext in ipairs(extensions) do
    glob_args = glob_args .. " --glob='*." .. ext .. "'"
  end

  -- Build the rg command; --files-with-matches returns only file paths
  local cmd = string.format(
    "rg --files-with-matches --ignore-case %s %q %q 2>/dev/null",
    glob_args, query, notes_dir
  )

  local results = {}
  local handle = io.popen(cmd, "r")
  if handle then
    for line in handle:lines() do
      if line ~= "" then
        table.insert(results, line)
      end
    end
    handle:close()
  end
  return results
end

--- Pure-Lua substring search across files in a directory.
--- Slower than rg but works without any external dependencies.
--- @param query string
--- @param notes_dir string
--- @param extensions table
--- @return table list of matching file paths
function M.lua_search(query, notes_dir, extensions)
  extensions = extensions or M.EXTENSIONS
  local ext_set = {}
  for _, e in ipairs(extensions) do ext_set["." .. e] = true end

  local lower_q = query:lower()
  local results = {}

  -- Use ls to enumerate files; popen is the only portable Lua I/O for dirs
  local handle = io.popen("ls -1 " .. notes_dir .. " 2>/dev/null")
  if not handle then return results end

  for filename in handle:lines() do
    local ext = filename:match("(%.[^.]+)$")
    if ext_set[ext] then
      local filepath = notes_dir .. "/" .. filename
      local f = io.open(filepath, "r")
      if f then
        local content = f:read("*a"):lower()
        f:close()
        if content:find(lower_q, 1, true) then
          table.insert(results, filepath)
        end
      end
    end
  end
  handle:close()
  return results
end

--- Unified search: try rg first, fall back to pure-Lua search.
--- @param query string
--- @param notes_dir string
--- @param expansion_groups table
--- @return table list of matching file paths
function M.search(query, notes_dir, expansion_groups)
  expansion_groups = expansion_groups or {}
  local expanded = M.expand_query(query, expansion_groups)

  -- Check if rg is available
  local rg_check = io.popen("rg --version 2>/dev/null")
  local rg_available = rg_check and rg_check:read("*l") ~= nil
  if rg_check then rg_check:close() end

  if rg_available then
    return M.rg_search(expanded, notes_dir, M.EXTENSIONS)
  else
    -- Fall back to pure-Lua search; can't use alternation without rg
    return M.lua_search(query, notes_dir, M.EXTENSIONS)
  end
end

return M
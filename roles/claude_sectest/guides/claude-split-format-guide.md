# Claude Split Format Guide

This document describes the expected format for consolidated files to be processed by the `claude-split.py` script. Following this format ensures proper extraction and file creation when splitting multi-file content into a directory structure.

## Format Requirements

Each file section in the consolidated output must:

1. Begin with a file path marker
2. Contain the complete file content
3. Be properly separated from other file sections

### File Path Markers

File path markers follow this syntax:
```
# path/to/file.ext
```

The marker **must**:
- Start with a hash/pound sign `#` followed by exactly one space
- Continue with the relative file path including subdirectories
- Appear on its own line

### Content Format

After each file path marker, include the complete file content, exactly as it should appear in the final file.

### Section Separation

File sections can be separated in one of these ways:
1. Directly followed by the next file path marker
2. Separated by a blank line from the next file path marker
3. Separated by a line with only `---` from the next file path marker (this will be stripped)

## Example

Here's an example of a properly formatted consolidated file:

```
# defaults/main.yml
---
# Default variables
example_variable: example_value
another_variable: another_value

# tasks/main.yml
---
- name: Example task
  debug:
    msg: "This is an example task"

- name: Include another task file
  include_tasks: another.yml

# tasks/another.yml
---
- name: Another task
  debug:
    msg: "This is another task"

# templates/example.conf.j2
# This is a template file
example_setting = {{ example_variable }}
another_setting = {{ another_variable }}
```

## Important Notes

1. The script will create all necessary directories based on the file paths
2. Binary files (like images) can't be properly represented in this format
3. Executable files will have proper permissions set if the path contains `/bin/`
4. The contents of a file marker will be read until the next file marker or end of file
5. Trailing document separators (`---`) will be automatically stripped from the content

## Using with Claude

When requesting Claude to generate code for an Ansible role (or other multi-file project), ask it to use the "Claude Split Format" and reference this guide. This ensures the output will be properly processed by the `claude-split.py` script.

## Processing the Output

Save Claude's output to a file, then run:

```bash
python3 claude-split.py -f consolidated_file.txt -o output_directory
```

The script will process the file and create the appropriate directory structure with all files properly placed.

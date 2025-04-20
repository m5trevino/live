#!/usr/bin/python3

# -*- coding: utf-8 -*-
import os
import sys
from itertools import cycle

# --- Configuration ---
OUTPUT_FILENAME = "merged_content.txt" # Name of the final merged file

# Define the dividers as pairs (top line, bottom line)
DIVIDERS = [
    ("╭━─━─━─≪✠≫─━─━─━╮", "╰━─━─━─≪✠≫─━─━─━╯"),
    ("┎━─━─━─━─━─━─━─━─━┒", "┖━─━─━─━─━─━─━─━─━┚"),
    ("┍──━──━──┙◆┕──━──━──┑", "┕──━──━──┑◆┍──━──━──┙"),
    ("╔═══━━━─── • ───━━━═══╗", "╚═══━━━─── • ───━━━═══╝"),
    ("╔══════════•⊱✦⊰•══════════╗", "╚══════════•⊱✦⊰•══════════╝"),
    ("╭────────────────────────╮", "╰────────────────────────╯"),
    # For the '❍' divider, we'll format the filename line separately for consistency
    ("┏━━━━•❅•°•❈•°•❅•━━━━┓", "┗━━━━•❅•°•❈•°•❅•━━━━┛"),
]

# --- Functions ---

def get_directory_from_user():
    """Prompts the user for a directory path and validates it."""
    while True:
        target_dir = input("Enter the path to the directory containing the files: ")
        if os.path.isdir(target_dir):
            # Return the absolute path for clarity
            return os.path.abspath(target_dir)
        else:
            print(f"Error: '{target_dir}' is not a valid directory. Please try again.", file=sys.stderr)

def find_files(target_dir):
    """Recursively finds all files within the target directory."""
    file_paths = []
    print(f"Scanning for files in: {target_dir}")
    for root, _, files in os.walk(target_dir):
        for filename in files:
            full_path = os.path.join(root, filename)
            # Basic check to avoid processing the output file if it exists in the tree
            # This is a simple check, might need refinement if output is complexly named/located
            if os.path.basename(full_path).lower() == OUTPUT_FILENAME.lower() and os.path.dirname(full_path) == os.getcwd():
                 print(f"  Skipping potential output file: {filename}")
                 continue
            file_paths.append(full_path)
    return sorted(file_paths) # Sort for consistent processing order

def merge_files_content(file_paths, target_dir, output_filepath):
    """Reads content from file_paths and writes to output_filepath with dividers."""
    if not file_paths:
        print("No files found to process.")
        return

    print(f"\nFound {len(file_paths)} files. Merging into: {output_filepath}")

    divider_cycler = cycle(DIVIDERS) # Create an iterator that cycles through dividers

    try:
        with open(output_filepath, 'w', encoding='utf-8') as outfile:
            is_first_file = True
            for file_path in file_paths:
                relative_path = os.path.relpath(file_path, target_dir)
                print(f"  Processing: {relative_path}")

                divider_top, divider_bottom = next(divider_cycler)

                # Add spacing before the next file block, except for the very first one
                if not is_first_file:
                    outfile.write("\n\n")
                else:
                    is_first_file = False

                # Write the header block
                outfile.write(f"{divider_top}\n")
                # Using a simple, consistent format for the filename line
                outfile.write(f"--- File: {relative_path} ---\n")
                outfile.write(f"{divider_bottom}\n\n") # Add a blank line between header and content

                # Write the file content
                try:
                    # Try reading with UTF-8, fallback to ignoring errors for problematic files
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as infile:
                        content = infile.read()
                        outfile.write(content)
                except Exception as read_err:
                    error_msg = f"Error reading file: {read_err}"
                    print(f"    WARNING: Could not read '{relative_path}'. Error: {read_err}", file=sys.stderr)
                    # Write error message into the merged file for context
                    outfile.write(f"\n[! ERROR PROCESSING FILE: {relative_path} !]\n")
                    outfile.write(f"[! {error_msg} !]\n")

        print(f"\nSuccessfully merged content into '{output_filepath}'")

    except IOError as write_err:
        print(f"\nError: Could not write to output file '{output_filepath}'.", file=sys.stderr)
        print(f"Error details: {write_err}", file=sys.stderr)
        sys.exit(1) # Exit if we can't write the output
    except Exception as e:
        print(f"\nAn unexpected error occurred during merging: {e}", file=sys.stderr)
        sys.exit(1)

# --- Main Execution ---
if __name__ == "__main__":
    input_dir = get_directory_from_user()
    files_to_process = find_files(input_dir)

    # Place the output file in the current working directory
    # (where the script is run from)
    output_path = os.path.join(os.getcwd(), OUTPUT_FILENAME)

    # Warn if output file already exists (optional)
    if os.path.exists(output_path):
       print(f"Warning: Output file '{output_path}' already exists and will be overwritten.")
       # Optionally add a confirmation prompt here

    merge_files_content(files_to_process, input_dir, output_path)
    print("Script finished.")
